# Sizing Overhaul — Implementation Plan

## Summary

Replace the hold-and-drag sizing gesture on seat buttons with a hold-on-action-button
system. Holding the **Raise** or **Bet** action button triggers a scrollable sizing chip
row in the control bar. Quick tap on either button remains decisive and unsized — no
behavior change for the fast path.

---

## What We Are Removing

### `SeatSelectionView.swift`

**State variables** (lines 52–56) — delete all five:
```swift
@State private var holdActive: Bool = false
@State private var holdTimer: DispatchWorkItem? = nil
@State private var sizingSeat: Int? = nil
@State private var sizingLabel: String = ""
@State private var sizingThumb: CGPoint = .zero
```

**`TableOvalView` parameters** (lines 42–43) — remove both:
```swift
var sizingStrip: (Int) -> [String] = { _ in [] }
var onSeatSize: (Int, String) -> Void = { _, _ in }
```

**Inside `DragGesture.onChanged`** — remove the hold-timer arm block and the
`holdActive` drag-tracking branch. The gesture simplifies to: track movement for swipe
detection only. Tap vs. swipe classification is unchanged.

**Inside `DragGesture.onEnded`** — remove the `wasHold` branch entirely. Only the
swipe branch and the tap branch remain.

**Floating sizing readout overlay** (`if sizingSeat != nil` block, lines 348–359) —
delete. No visual feedback lives on the felt during sizing any more.

**Sizing helper statics** (lines 369–388) — delete all three:
```swift
private static func sizeIndex(for:count:) -> Int?
private static func sizeLabel(for:strip:) -> String
private static func committedLabel(for:strip:) -> String?
```

**Note:** The existing comment block on the gesture (lines 243–250) explaining why a
single `DragGesture(minimumDistance: 0)` is used remains valid — keep it. The gesture
is still one recognizer; we are only removing the hold branch from inside it.

---

### `HandEntryView.swift`

**Functions to delete** (seat-level sizing, now orphaned):
```swift
private func sizingStrip(for seat: Int) -> [String]
private func handleSeatSize(_ seat: Int, _ label: String)
```

**`TableOvalView` call-site** — remove the two deleted parameters:
```swift
sizingStrip: sizingStrip(for:)   // remove
onSeatSize: handleSeatSize        // remove
```

**Keep everything else in the sizing data layer** — these are reused by the new system:
```swift
private func makeSizing(_ label: String) -> RaiseSizing   // keep
private static let multipleStrip: [String]                // keep, update contents
private static let betStrip: [String]                     // keep, update contents
```

---

## What We Are Adding

### New sizing strips (updated contents)

**`multipleStrip`** — preflop raise / post-flop re-raise. Curated multiples + All-in.
```swift
private static let multipleStrip: [String] = [
    "2x", "2.2x", "2.5x", "2.8x", "3x", "3.2x", "3.5x", "4x", "5x", "All-in"
]
```

**`betStrip`** — post-flop opening bet. Curated % values + Pot + overbets + All-in.
```swift
private static let betStrip: [String] = [
    "10%", "25%", "33%", "50%", "67%", "75%", "90%",
    "Pot",
    "1.1x", "1.2x", "1.5x", "2x",
    "All-in"
]
```

---

### Hold-on-button sizing — `ControlBar` in `HandEntryView.swift`

#### New state (on `HandEntryView`, passed into `ControlBar`)

```swift
@State private var sizingRowVisible: Bool = false
@State private var holdWorkItem: DispatchWorkItem? = nil
```

#### Raise button — hold behavior

The raise is written to the log the moment the hold fires — identical to how cycling
writes immediately. The sizing row is an annotation layer on top of that logged action.
This means Undo needs no special handling: it peels the raise from the log just like
any other action, and we simply also dismiss the sizing row.

- **Quick tap** → existing `onAction(.raise)` path. Decisive, unsized, advances. No change.
- **Hold (0.3s)** → `recordAction(.raise, for: highlightedSeat)` then
  `sizingRowVisible = true`. Raise is in the log (unsized). Seat shows ↑↑. Raise button
  renders as "selected" (gold fill, dark text). Release hold — row stays up.
- **Tap a chip** → `removeLastAction(of: highlightedSeat)` then
  `recordAction(.raise, for: highlightedSeat, sizing: makeSizing(label))` then
  `settleAfterCommit(highlightedSeat)` — advances ring, `sizingRowVisible = false`.
- **Undo while row is visible** → existing Undo peels the `.raise` from the log (no
  special case). Add only: `if sizingRowVisible { sizingRowVisible = false }` at the
  top of the Undo handler. Seat returns to its previous state.

#### Bet button — identical mechanism, different strip

- Same hold delay, same pattern: `recordAction(.open, for: highlightedSeat)` on hold,
  `removeLastAction` + `recordAction(.open, sizing:)` + `settleAfterCommit` on chip tap.
- Strip used: `betStrip` instead of `multipleStrip`.
- `.open` is the correct action type for a post-flop opening bet (distinct from `.raise`).

#### Chip color coding in the sizing row

Colored by kind. The bet strip's `x` chips are gone (overbets are now `%`), so an `x`
chip only ever means a raise multiple → purple. Purple keeps raises distinct from the
gold Raise button and the gold All-in.

| Chip type | Background | Border | Text |
|-----------|-----------|--------|------|
| `%` chips (sub-pot + overbets, `10%`…`200%`) | `#111A0D` | `#3A6020` | `#7AB840` (green) |
| `Pot` | `#252010` | `#C9A84C` | `#E8D5A3` (gold) |
| Raise multiples (`2x`…`5x`) | `#16101A` | `#7A3FA0` | `#B07AD0` (purple) |
| `All-in` | `#2A1A05` | `#E8D5A3` | `#E8D5A3` (light gold) |

#### Raise/Bet button appearance while sizing row is visible

```
Normal state:   background #252010, border #C9A84C, text #C9A84C
Selected state: background #C9A84C, border #C9A84C, text #0D0D0D
```

The button turning solid gold signals "I'm staged — tap a chip or tap me again." There
is no "tap me again to commit unsized" behavior — if the user decides not to size, they
tap Undo to clear the staged state, then quick-tap Raise/Bet for an unsized commit.

#### `ControlBar` new parameters

```swift
let isSizingRaiseVisible: Bool          // drives sizing row + button appearance
let isSizingBetVisible: Bool
let sizingChips: [String]               // the strip to render (multipleStrip or betStrip)
let onSizedAction: (ActionType, String) -> Void   // chip tap callback
let onRaiseHoldBegan: () -> Void        // 0.3s hold fired
let onBetHoldBegan: () -> Void
```

#### Layout when sizing row is visible

The chips fill the **utility row to the right of Undo**. Undo stays pinned; the Next
Street button is **hidden while sizing** (a staged raise/bet never closes the street, so
it would be disabled anyway), so the chips get the full width. The action row never moves.

```
┌─────────────────────────────────────┐
│ ↺Undo [2x][2.2x][2.5x][2.8x][3x]…  │  ← utility row: Undo · scrolling chips (no Next Street)
│─────────────────────────────────────│
│  [ Fold ]  [ Call ]  [■ Raise ■]   │  ← action row (fixed); Raise = selected gold
└─────────────────────────────────────┘
```

The chips fade in (`.transition(.opacity)`) when `sizingRowVisible` becomes true and
fade out on dismissal. Chip height matches the Undo/Next Street buttons (38pt) so the
row height is stable.

---

## Swipe Gestures — No Change

Swipes remain fully decisive and always unsized. The seat `DragGesture` is simpler now
(hold branch removed) but the swipe → action mapping is unchanged:

| Swipe | Action |
|-------|--------|
| ← | Fold |
| ↑ | Raise (bet context) |
| → | Bet (no-bet context) |
| ↓ | Call / Check |

---

## Seat Cycling — No Change

Cycling through actions via seat tap (Call → Raise → Fold → … or Check → Bet → …)
remains unchanged. Cycling to the Raise or Bet state does **not** trigger the sizing
row — the hold gesture on the button is the only trigger.

---

## Undo Interaction

| State | First Undo press | Second Undo press |
|-------|-----------------|-------------------|
| Sizing row visible | Dismisses row + peels raise/bet from log → seat returns to previous state | Continues normal peel |
| Ring on empty waiting seat | Returns cue to last actor | Deletes that action |
| Ring on Next Street button | Returns cue to last actor | Deletes that action |
| Normal | Deletes last action | Continues peeling |

The raise/bet is in the log the moment the hold fires, so Undo treats it as any normal
action. The only sizing-row-specific code in the Undo handler is one guard:
`if sizingRowVisible { sizingRowVisible = false }` — everything else is handled by the
existing peel logic.

---

## Reference Doc Updates

### `README.md`

**Section: Core Feature → Recording → Hold-to-size bullet** — replace the existing
bullet with:

> **Hold-to-size** (optional) — press and hold the **Raise** or **Bet** action button
> (0.3s) to open a scrollable sizing chip row above the action buttons. Raise opens
> multiples (`2.0x`…`5.0x`, All-in); Bet opens pot fractions (`20%`…`90%`, Pot,
> overbets, All-in). Tap a chip to commit the action with that size and advance the
> ring. Quick tap on Raise/Bet is always decisive and unsized. Swipes are always unsized.
> Sizes are relative notation only — no chip/pot math. Shown as a pill on the seat's
> bottom rim.

**Section: Known Limitations — seat gesture note** — update the note about the single
`DragGesture`. Remove the mention of hold-to-size as one of the classified inputs;
update to: "Tap and swipe are classified inside a single `DragGesture(minimumDistance: 0)`."
The rationale for one recognizer still applies.

---

### `PokerActionReference.md`

**Section: Swipes** — remove the phrase "a press-and-hold attaches a size to a
bet/raise." Swipes are always unsized. Update the paragraph to:

> **Swipes** are a decisive shortcut layered over this same model: a directional swipe
> records a chosen action in one gesture — picking the action directly instead of cycling
> to it — and advances the ring to the next player without seeding any action on it.
> Swipes are **always unsized**. Quick swipe = action recorded, no size attached.

**Section: Action buttons** — add a paragraph after the existing action-button
description:

> **Hold-to-size on Raise / Bet.** Holding the Raise or Bet button for 0.3s opens a
> scrollable sizing chip row in the control bar. The action is staged (shown on the seat
> visually) but not written to the log. Tapping a chip commits the action with that size
> and advances the ring — identical settle path to a quick tap, plus sizing attached.
> Undo while the sizing row is visible clears the staged state without deleting any log
> entry (nothing was written). Quick tap on Raise or Bet (no hold) commits unsized and
> advances immediately — the existing decisive behavior is unchanged.

---

## Files Touched

| File | Change type |
|------|------------|
| `SeatSelectionView.swift` | Remove: hold state vars, hold timer arm, holdActive drag branch, wasHold onEnded branch, floating readout overlay, sizeIndex/sizeLabel/committedLabel statics, sizingStrip + onSeatSize params |
| `HandEntryView.swift` | Remove: sizingStrip(for:), handleSeatSize(_:_:), TableOvalView call-site params. Add: sizingRowVisible + holdWorkItem state, hold gesture on Raise/Bet buttons, sizing chip row in ControlBar, onSizedAction path |
| `README.md` | Update hold-to-size bullet, update Known Limitations seat gesture note |
| `PokerActionReference.md` | Update Swipes section, update Action buttons section |

---

## Out of Scope for This Pass

- Configurable per-session sizing presets ("I always raise to 2.2x at this game")
- BBs or dollar amounts as a sizing type (SizingType already models these — future pass)
- Sizing on swipe gestures
