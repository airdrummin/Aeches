# Aeches — Seat Swipe & Sizing Interaction: Implementation Spec

> Authoritative implementation reference for the **swipe** gestures and **hold-to-size** system
> on the Aeches poker table, layered on top of the existing tap/click system. A fresh AI engineer
> should be able to implement everything here from this document alone.
>
> Companion docs: `README.md` (current app state), `PokerActionReference.md` (poker action logic),
> `Aeches/Architecture Plan.md` (original plan). The tap/click system this builds on is already
> implemented and must not regress.

---

## 1. Scope

Adds two things to the **top-half table UI** only:

1. **Swipe actions** (Phase 1) — directional swipes on a seat that record a *specific* action in one
   gesture and advance, parallel to the existing tap routing.
2. **Hold-to-size** (Phase 2) — press-and-hold a seat and slide to attach a size (e.g. `2.5x`, `40%`,
   `All-in`) to a bet/raise, shown as a pill on the seat's bottom rim.

**Out of scope / must not change:**
- The Action Controller Bar (bottom bar) and all its handlers.
- Tap routing, cycling, jumps, rewind, next-street, street-close, fold-out, showdown — all unchanged.
- The seat **action symbols** (`→` bet, `↑↑`/pip raises, `✓` call, `—` check, `✕` fold). Untouched.
- **No chip/pot engine.** Sizes are stored as **relative labels only** (notation, not amounts).

**Key files:**
| File | Role |
|---|---|
| `Aeches/HandEntryView.swift` | All tap/swipe logic, state machine, street management |
| `Aeches/SeatSelectionView.swift` | `TableOvalView`, `SeatButtonView`, `SeatState` — gesture plumbing + size pill render |
| `Aeches/Models.swift` | `ActionType`, `RaiseSizing`, `SizingType` (already present) |

---

## 2. Core principle

- **Tap = edit in place** (unchanged): cycles the on-clock seat Call→Raise→Fold→… for refining.
- **Swipe = decisive**: records a specific action **and advances** to the next actor — exactly like
  pressing an Action Controller Bar button, but performed directly on the seat.

"Decisive" means it records the action and moves the highlight to the next player — it does **not**
advance the street. A swipe that *closes* the street keeps the highlight on the seat that just acted
(advancing onto an already-acted player is confusing) and lights the Flop / Turn / River button.
**Only that button advances a street** — swipes and taps never do. (The Action Controller Bar's own
auto-advance is a separate, out-of-scope path.)

---

## 3. The swipe map (strict)

Four directions, resolved by context. **Strict**: a direction that isn't legal in the current
context is a **no-op** (no fallback aliasing).

| Swipe | Facing a wager (preflop always, or post-flop bet live) | No wager yet (post-flop opener) |
|---|---|---|
| **← Left** | Fold | Fold |
| **↑ Up** | Raise | *(no-op)* |
| **→ Right** | *(no-op)* | Bet |
| **↓ Down** | Call | Check |

Notes:
- Preflop is **always** a bet context (the blind is a live wager), so preflop: ↑ = raise, ↓ = call,
  ← = fold, → = no-op. Preflop aggression is always `.raise` (an `.open` only ever occurs post-flop).
- The `→`/`↑` split mirrors the seat symbols: `→` = bet (`.open`), `↑↑` = raise (`.raise`).

### 3.1 Resolver

```swift
enum SwipeDirection { case up, down, left, right }

/// Maps a swipe direction to the action it records for `seat`, or nil when the direction is
/// illegal in the current context (strict — caller treats nil as a no-op).
private func swipeAction(_ dir: SwipeDirection, for seat: Int) -> ActionType? {
    let betContext = currentStreet == .preflop || seatFacesBet(seat)
    switch dir {
    case .left:  return .fold
    case .down:  return betContext ? .call : .check
    case .up:    return betContext ? .raise : nil   // raise only when a wager exists
    case .right: return betContext ? nil   : .open   // bet only when no wager exists
    }
}
```

---

## 4. Gesture plumbing

**File:** `SeatSelectionView.swift`

**Use exactly ONE gesture per seat** — a single `DragGesture(minimumDistance: 0)` that classifies
tap vs. swipe vs. hold-to-size inside its own handlers. Do **not** layer `.onTapGesture` +
`.simultaneousGesture` + `.highPriorityGesture`; SwiftUI's arbitration between them is fragile (it
sacrifices one gesture to feed another, and iOS 18 has a confirmed `simultaneousGesture`
mis-recognition bug). One gesture = nothing to arbitrate.

How the single gesture classifies, in `onEnded`:
- **tap** — `translation ≈ .zero` (at `minimumDistance: 0`, `onEnded` fires even for a stationary
  tap, so no separate `TapGesture` is needed).
- **swipe** — `translation` magnitude past a threshold (~12pt); direction = dominant axis.
- **hold-to-size** — engaged by a 0.3s timer armed on touch-down (since `onChanged` is silent while
  the finger is still). If the finger hasn't moved past the threshold when the timer fires, switch
  into sizing; from then on `onChanged` drives the floating readout and `onEnded` commits.

```swift
// TableOvalView gains: onSeatSwipe, sizingStrip, onSeatSize, plus transient @State:
//   touchSeat, touchMoved, holdActive, holdTimer (DispatchWorkItem?), sizingSeat/Label/Thumb.
.gesture(
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            if touchSeat != i {                       // new touch on this seat
                touchSeat = i; touchMoved = false; holdActive = false
                let work = DispatchWorkItem {         // arm the hold → sizing timer
                    guard touchSeat == i, !touchMoved, !sizingStrip(i).isEmpty else { return }
                    holdActive = true; sizingSeat = i; sizingThumb = pos; sizingLabel = ""
                }
                holdTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
            let moved = hypot(value.translation.width, value.translation.height)
            if holdActive {                            // sizing: update floating readout
                sizingThumb = CGPoint(x: pos.x + value.translation.width, y: pos.y + value.translation.height)
                sizingLabel = Self.sizeLabel(for: value.translation, strip: sizingStrip(i))
            } else if moved > 12 {                      // it's a drag → cancel the hold
                touchMoved = true; holdTimer?.cancel()
            }
        }
        .onEnded { value in
            holdTimer?.cancel()
            let seat = touchSeat ?? i, wasHold = holdActive, t = value.translation
            let moved = hypot(t.width, t.height)
            touchSeat = nil; touchMoved = false; holdActive = false; sizingSeat = nil; sizingLabel = ""
            if wasHold {
                if let label = Self.committedLabel(for: t, strip: sizingStrip(seat)) { onSeatSize(seat, label) }
            } else if moved > 12 {
                if abs(t.width) > abs(t.height) { onSeatSwipe(seat, t.width > 0 ? .right : .left) }
                else { onSeatSwipe(seat, t.height > 0 ? .down : .up) }   // SwiftUI y grows downward
            } else {
                onSeatTap(seat)
            }
        }
)
```

`SwipeDirection` is defined at file scope (same module, both files see it). `HandEntryView` passes
`onSeatSwipe: handleSeatSwipe`, `sizingStrip: sizingStrip(for:)`, `onSeatSize: handleSeatSize`.

**Why this and not multiple gestures (learned the hard way):**
- Layering `.onTapGesture` + `.simultaneousGesture`/`.highPriorityGesture` repeatedly broke one of
  the three interactions (taps died, or swipes died). SwiftUI gesture composition can't reliably
  split tap/swipe/hold across separate recognizers — and iOS 18 worsens it.
- A shared "a hold happened" flag to mute the swipe gets stuck `true` after a sizing and kills later
  swipes. The single-gesture design has no flag to get stuck.
- `minimumDistance: 0` is correct **here** precisely because there is no other gesture to compete
  with — the same `minimumDistance: 0` was what broke taps earlier *only* because a second gesture
  was present.
- Tuning dials: tap/swipe threshold `12`, hold delay `0.3s`, and the `12/190` drag→value map in
  `sizeIndex`. The fully bulletproof alternative is iOS-18 `UIGestureRecognizerRepresentable`
  (UIKit bridge) if the single-gesture approach ever proves insufficient.

---

## 5. Swipe routing (mirrors tap routing)

**File:** `HandEntryView.swift`

A swipe = "set seat S to action A, decisively." Getting *to* S reuses the tap routing (guards +
auto-fold/auto-check of skipped seats); only the **landing action** differs (A instead of the
default). `handleSeatSwipe` resolves the direction to an action, then hands off to `routeDecisive` —
the shared router used by both swipes and hold-to-size (§7); the only difference for sizing is a
non-nil `sizing`.

```swift
private func handleSeatSwipe(_ seat: Int, _ dir: SwipeDirection) {
    guard phase == .recordingHand else { return }
    guard let action = swipeAction(dir, for: seat) else { return }   // illegal direction → no-op
    routeDecisive(action, to: seat, sizing: nil)
}

/// Shared decisive routing for swipes and sized holds — mirrors the tap routing but always lands a
/// specific action. `sizing` (Phase 2) is attached to the landed action.
private func routeDecisive(_ action: ActionType, to seat: Int, sizing: RaiseSizing?) {
    withAnimation(.easeInOut(duration: 0.15)) {
        // On-clock seat → record + move to next player. Routed through finishSwipe (NOT commitAction)
        // so a swipe never auto-advances the street — only the Next Street button does.
        // A decisive gesture SETS the seat's current decision: if it already has a standing turn-action
        // (e.g. cycled to Call) supersede it instead of stacking. owesAction == true means it owes a
        // fresh response (never acted, or facing new aggression) — that's a separate action, keep it.
        if seat == highlightedSeat {
            if hasActed(seat) && !owesAction(seat) { removeLastAction(of: seat) }
            finishSwipe(on: seat, action: action, sizing: sizing)
            return
        }

        guard activeSeatSequence.contains(seat) else { return }                  // dead seat
        if hasActed(seat) && !owesAction(seat) { return }                        // resolved
        if let hs = highlightedSeat, hasActed(hs) && owesAction(hs) { return }   // re-aggression

        if currentStreet != .preflop && openBetExists {
            // Bet context: STRICT — only the exact next owing seat; no auto-call/fold by skipping.
            guard seat == nextOwingSeat(after: highlightedSeat ?? seat) else { return }
            commitSwipeStrict(to: seat, action: action, sizing: sizing)
        } else {
            // Navigation context (preflop, or post-flop with no wager): cannot skip an acted seat.
            let between = seatsStrictlyBetween(from: highlightedSeat ?? seat, to: seat, in: activeSeatSequence)
            if between.contains(where: { hasActed($0) }) { return }
            commitSwipeJump(to: seat, action: action, sizing: sizing)
        }
    }
}
```

### 5.1 Shared skip helper (DRY refactor of the existing jumps)

Extract the skip logic that `preflopJump` and `postflopJump` already perform, so swipes reuse it.
After extraction, the existing tap jumps call it too (behavior identical to today).

```swift
/// Auto-resolves the seats skipped going clockwise from the highlight to `seat`:
/// preflop they FOLD, post-flop (no wager) they CHECK. The on-clock seat is included if it
/// never acted. All are flagged isAutoFolded so one Rewind press removes the batch.
/// Returns true if a fold-out ended the hand (caller must stop).
@discardableResult
private func autoResolveSkipped(to seat: Int) -> Bool {
    let skipped: [Int] = {
        var s: [Int] = []
        if let from = highlightedSeat, activeSeatSequence.contains(from), !hasActed(from) { s.append(from) }
        s += seatsStrictlyBetween(from: highlightedSeat ?? seat, to: seat, in: activeSeatSequence)
            .filter { !hasActed($0) }
        return s
    }()
    if currentStreet == .preflop {
        return autoFoldSeats(skipped, autoFolded: true)        // existing helper; may trigger fold-out
    } else {
        for s in skipped { recordAction(.check, for: s, autoFolded: true) }
        return false                                           // checks never reduce the active count
    }
}
```

Then refactor the existing tap jumps to use it (no behavior change):
- `preflopJump(to:)` → `if autoResolveSkipped(to: seat) { return }; highlightedSeat = seat; recordAction(.call, for: seat)`
- `postflopJump(to:)` → `_ = autoResolveSkipped(to: seat); highlightedSeat = seat; recordAction(.check, for: seat)`

### 5.2 The two swipe landings

```swift
/// Navigation-context swipe: auto-resolve skipped seats, then land `action` on the destination.
private func commitSwipeJump(to seat: Int, action: ActionType, sizing: RaiseSizing? = nil) {
    if autoResolveSkipped(to: seat) { return }   // fold-out already ended the hand
    finishSwipe(on: seat, action: action, sizing: sizing)
}

/// Strict bet-context swipe (the seat IS the next owing seat): commit the on-clock seat's
/// default response first, then land `action` on the destination.
private func commitSwipeStrict(to seat: Int, action: ActionType, sizing: RaiseSizing? = nil) {
    if let cur = highlightedSeat, owesAction(cur) {
        recordAction(seatFacesBet(cur) ? .call : .check, for: cur)
    }
    finishSwipe(on: seat, action: action, sizing: sizing)
}

/// Shared tail: record the action on `seat`, handle fold-out, then move to the next seat that owes
/// action and SEED its default (call facing a bet, else check) — exactly what the tap flow does on
/// arrival, so the next seat is "live" (prior action shows as a pill, not as current) and Rewind has
/// its entry to peel instead of skipping past it. If THIS action closes the street, stay on the
/// acting seat and let the Flop / Turn / River button advance. Swipes never auto-advance the street.
private func finishSwipe(on seat: Int, action: ActionType, sizing: RaiseSizing? = nil) {
    recordAction(action, for: seat, sizing: sizing)
    if action == .fold && activeSeatSequence.count == 1 { triggerFoldOut(); return }
    highlightedSeat = seat
    guard !streetIsClosed() else { return }
    if let next = nextOwingSeat(after: seat) {
        highlightedSeat = next
        recordAction(seatFacesBet(next) ? .call : .check, for: next)   // seed the next seat's default
    }
}
```

This reuses, unchanged: `recordAction`, `advanceHighlight`, `streetIsClosed`, `autoResolveSkipped`,
`autoFoldSeats`, `seatsStrictlyBetween`, `nextOwingSeat`, `owesAction`, `hasActed`, `seatFacesBet`,
`triggerFoldOut`. (`commitAction` / `checkStreetClose` belong to the ACB path and are NOT used by
swipes — that's what keeps swipes from auto-advancing the street.)

---

## 6. Worked examples (must pass)

**Preflop, decisive swipe advances one seat.** UTG, CO, SB, BB in. UTG raise → CO call. SB 3-bets via
**up-swipe on SB**: commits SB's raise, advances **one seat to BB** (next in line, owes the 3-bet).
*(If SB 3-bets via clicks instead — tap=call, tap again=raise — the highlight stays on SB, because
cycling is edit-in-place.)*

**Preflop navigation by swipe folds the skipped seat.** Continuing: to act on UTG, **swipe on UTG**
(a non-highlighted seat): auto-folds the skipped BB, lands UTG at the swiped action, advances. E.g.
**swipe ↓ (call) on UTG** → BB folds, UTG calls, highlight advances to CO.

**Post-flop opener jump (aggressive).** Flop, UTG/CO/BTN active, action on UTG. **Swipe → (bet) on
BTN**: auto-checks UTG and CO (skipped), records BET on BTN, then bounces the highlight **back to the
first responder = UTG**. Result: UTG `✓`, CO `✓`, BTN `→`, highlight on UTG.

**Strict facing a live bet.** Flop, BTN has bet, UTG and CO owe, action on UTG. **Swipe on CO** (not
the next-to-act) → **no-op**. Only a swipe (or tap) on **UTG** registers. No auto-call/auto-fold by
skipping into a bet.

**Re-aggression.** While the on-clock seat has acted and owes a response to new aggression, a swipe on
any *other* seat is a **no-op** — it must respond first.

---

## 7. Sizing — hold-to-size (Phase 2)

Sizing is **optional and additive**: a quick swipe records an **unsized** bet/raise (`sizing = nil`,
exactly as today); **press-and-hold + slide** records the same bet/raise **with a size**. Hold only
applies to aggressive actions (bet/raise) — fold/call/check are never sized. The context engine
decides bet vs. raise (same `swipeAction` logic: facing a wager → raise; no wager → bet).

### 7.1 Storage — relative labels only

Use the existing `RaiseSizing` on `Action.sizing` (currently always nil). Add an optional param to
`recordAction` (default nil keeps every existing call unchanged):

```swift
private func recordAction(_ type: ActionType, for seat: Int,
                          autoFolded: Bool = false, sizing: RaiseSizing? = nil) {
    actionsThisStreet.append(Action(seatIndex: seat, position: positionFor(seat: seat),
                                    actionType: type, sizing: sizing, isAutoFolded: autoFolded))
    recomputeDerivedState()
}
```

No chip math, no pot/stack tracking. `RaiseSizing.label` holds the display string (`"2.5x"`, `"40%"`,
`"Pot"`, `"1.5x"`, `"All-in"`); `type`/`value` use existing `SizingType` for future use.

### 7.2 The two strips

There are exactly two strip shapes; the context engine picks which to show.

**Multiple strip** — every multiplied action: preflop open, preflop re-raise, post-flop raise.
- Values **2.0x → 5.0x**, **0.1x steps**, then **All-in**.
- Reference differs (open = ×BB, raise = ×last wager) but the label is just `"2.5x"` etc.; the action
  symbol (`↑↑` raise vs the implied open) conveys the reference.
- Minimum 2.0x is a convention (a raise is at least 2x), not enforced chip-legal math.

**Bet strip** — only the post-flop opening bet (no prior wager; the pot is the reference).
- **5% → Pot**, **5% steps** (labels `"5%"`, `"10%"`, … `"95%"`, **`"Pot"`** at 100%), then
- **1.1x → 5.0x ×pot**, **0.1x steps** (labels `"1.1x"` … `"5.0x"`), then **All-in**.

Both strips terminate in **All-in** (drag all the way out = jam).

### 7.3 Gesture & UI — floating readout

Chosen design: a **floating value bubble that follows the thumb** — no ruler, no tick scale.

- **Enter sizing:** a `LongPressGesture` on a seat (≈0.3s) enters sizing mode for that seat's
  aggressive action (bet or raise, resolved by the same context logic as `swipeAction`). Once the
  long-press fires, the seat's quick-swipe handling is suppressed for that touch.
- **Slide to size:** as the thumb drags, a large value bubble (~19pt bold, gold border `#C9A84C`,
  dark fill `#1C1C1C`, gold text `#E8D5A3`) tracks just ahead of the thumb and updates live. Map
  **drag distance → value**, snapped to the strip increment (0.1x or 5%). Dragging **further out
  grows** the size, pulling **back shrinks** it; past the strip's last value the bubble reads
  **All-in**.
- **Faint anchors only:** show at most 1–2 low-contrast reference markers along the path — the floor
  (**2x**, or **Pot** on the bet strip) and **All-in** at the far end — for orientation. No full tick
  scale, no other labels.
- **Commit:** release → record the bet/raise with the `RaiseSizing` whose `label` is the bubble's
  current value, then advance (decisive, like any swipe).
- **Cancel:** release while the thumb is back **over the seat** (below the floor) → no action recorded.
- **Edge-proof:** because the bubble floats at the thumb instead of anchoring a fixed scale to the
  seat, it behaves identically for every seat, including those at the top/edges of the oval.

**Implementation note — disambiguating quick-swipe vs. hold-to-size.** Both start as a finger-down +
drag; they differ by **time held before moving**. This is handled inside the *single* seat gesture
(§4), not by a second recognizer: a 0.3s `DispatchWorkItem` timer is armed on touch-down and engages
sizing only if the finger hasn't moved past the swipe threshold by then. Moving first cancels the
timer (→ swipe); holding first engages sizing. The `0.3s` delay and `12pt` threshold are the dials.

### 7.4 Display — size pill on the bottom rim (Option C)

**File:** `SeatSelectionView.swift`, `SeatButtonView`. Symbols stay exactly as they are. When (and only
when) `state.action.sizing != nil`, render a small **capsule on the bottom edge** of the seat circle
(straddling the border, like the dealer button rides the corner):

- Capsule, dark fill `#14110A`, **1.2pt** stroke `#C9A84C`, gold text `#E8D5A3`, ~11pt bold.
- Centered horizontally, vertical center near `+size * 0.5` (on the bottom rim of the 50pt circle).
- Text = the size label (`2.5x`, `40%`, `Pot`, `1.5x`, `All-in`).
- This is distinct from the prior-action badges, which ride the **top** edge — no collision.

`SeatState` needs to carry the current action's size label (e.g. add `var sizeLabel: String? = nil`),
populated in `syncSeatActions()` from the most-recent action's `sizing?.label`.

---

## 8. Architecture / DRY notes

- **Single source of truth unchanged.** All swipe paths funnel through `recordAction(...)` +
  `recomputeDerivedState()`; never mutate derived state directly.
- **Reuse over rebuild.** On-clock swipes reuse `commitAction`. Jumps reuse the extracted
  `autoResolveSkipped` (which the tap jumps now also call). Advancing reuses `advanceHighlight` +
  `checkStreetClose`. No parallel copies of routing logic.
- **Rewind is already correct.** Auto-folds/auto-checks from a swipe-jump use `isAutoFolded: true`, so
  one Rewind press removes the batch — no changes to `undoLastAction()`.
- **Symbols & ACB untouched.** Do not modify the seat symbols or any Action Controller Bar handler.
- **Phase order:** ship **Phase 1 (swipe actions)** first — fully usable without sizing. **Phase 2
  (hold-to-size)** layers on without touching the action routing.

---

## 9. Verification checklist

| # | Test | Expected |
|---|---|---|
| 1 | Swipe ↓ on the on-clock seat (facing a bet) | Records Call, advances one seat |
| 2 | Swipe ↑ on the on-clock seat (facing a bet) | Records Raise, advances to first responder |
| 3 | Swipe → on the on-clock seat (post-flop, no bet) | Records Bet, advances to first responder |
| 4 | Swipe → preflop | No-op (preflop is always a bet context) |
| 5 | Swipe ↑ post-flop with no bet | No-op |
| 6 | Swipe ← on any actionable seat | Fold, advances / fold-out if last |
| 7 | Preflop: SB 3-bets via up-swipe | Highlight advances to BB (next in line) |
| 8 | Preflop: swipe ↓ on a later seat | Skipped seats fold, that seat calls, advance |
| 9 | Post-flop: swipe → (bet) on BTN with UTG on clock | UTG+CO auto-check, BTN bets, highlight back to UTG |
| 10 | Facing a live bet: swipe a non-next seat | No-op |
| 11 | Re-aggression: swipe another seat while on-clock owes | No-op |
| 12 | Short drag (< threshold) | Treated as a tap (cycle/edit) — unchanged |
| 13 | Swipe that closes a street | Stays on the acting seat, lights the Next Street button — never auto-advances |
| 14 | Rewind after a swipe-jump | Whole auto-action batch removed in one press |
| 14b | Cycle on-clock seat to Call, then swipe/hold a Raise | Raise supersedes the cycled Call (one current action), prior-round actions kept |
| 14c | Swipe a raise that the action moves past a re-acting seat | That seat is seeded with its default (prior action shows as a pill, not as current); Rewind peels the seed and lands on the raiser — never skips it |
| 15 | (P2) Quick swipe vs hold | Quick = unsized; hold+slide = sized |
| 16 | (P2) Hold a raise, slide to 2.5x | Records raise with `2.5x`, pill on bottom rim |
| 17 | (P2) Hold a post-flop bet, slide past Pot | Shows `1.1x…5.0x` ×pot, then All-in |
| 18 | (P2) Size pill placement | Bottom rim, never collides with top-edge prior-action badges |
| 19 | (P2) Cancel a hold | Slide back onto seat / off strip → no action recorded |
