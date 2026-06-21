# Phase 1 — Data Model, Entry Logic, Notation & Doc

**Prerequisite:** read [INDEX.md](INDEX.md) in full (spec, current-code map, conventions). This phase
makes the *behavior* correct; the strip can look interim. All edits are in
`Aeches/HandEntryView.swift` except the doc update in `ShorthandReference.md`.

**Goal:** after this phase, entering hands produces the correct shorthand in the on-screen transcript
(the "HAND" panel) and Copy output for all three suit modes, with the two-tier dimming enforcing
"rank first." Verify against the Worked Examples at the bottom.

---

## Step 1 — Replace the slot model with a group model

Remove `qualifier` from the frame; introduce a group type that owns the suit mode. Place these near
the existing `CardSlot` definition (and rename usages).

```swift
/// One card frame: a rank, plus a bound suit that is only meaningful in `.bound` mode.
struct CardFrame: Equatable {
    var rank: String? = nil          // "A","K",…,"2"
    var suit: String? = nil          // "♠" "♥" "♦" "♣" — used only when the group is .bound
    var isEmpty: Bool { rank == nil }
}

/// A street's group of frames plus its single suit mode. Hole = 2 frames, flop = 3, turn/river = 1.
struct CardGroup: Equatable {
    enum SuitMode: Equatable { case none, bound, footnote, relationship }

    var frames: [CardFrame]
    var mode: SuitMode = .none
    var footnote: [String] = []      // ordered suit letters ("s/h/d/c" or "x"); used only in .footnote
    var footnoteCursor: Int = 0      // wrap-replace pointer once footnote is full
    var relationship: String? = nil  // "s","o" (hole) | "r","m","tt" (flop); used only in .relationship

    var capacity: Int { frames.count }
    var ranksFilled: Int { frames.filter { $0.rank != nil }.count }
    var isFull: Bool { ranksFilled == capacity }
    var hasAnyRank: Bool { ranksFilled > 0 }
    var firstEmptyIndex: Int? { frames.firstIndex(where: { $0.isEmpty }) }

    init(capacity: Int) { self.frames = Array(repeating: CardFrame(), count: capacity) }

    mutating func reset() {
        frames = Array(repeating: CardFrame(), count: capacity)
        mode = .none; footnote = []; footnoteCursor = 0; relationship = nil
    }
}
```

Replace the per-group `@State` in `HandEntryView`:

```swift
@State private var holeGroup  = CardGroup(capacity: 2)
@State private var flopGroup  = CardGroup(capacity: 3)
@State private var turnGroup  = CardGroup(capacity: 1)
@State private var riverGroup = CardGroup(capacity: 1)

@State private var entryStreet: CardStreet? = nil
@State private var focusIndex: Int = 0          // cursor within the open group
```

Add an accessor that returns a binding/inout to the open group so handlers mutate the right one:

```swift
private func group(for street: CardStreet) -> CardGroup {
    switch street { case .hole: holeGroup; case .flop: flopGroup; case .turn: turnGroup; case .river: riverGroup }
}
private func setGroup(_ street: CardStreet, _ g: CardGroup) {
    switch street {
    case .hole:  holeGroup  = g
    case .flop:  flopGroup  = g
    case .turn:  turnGroup  = g
    case .river: riverGroup = g
    }
}
```

> Note: `resetHandState()` currently re-initialises `heroCards/flopCards/turnCard/riverCard`. Update it
> to re-init the four `CardGroup`s instead (`holeGroup = CardGroup(capacity: 2)`, etc.), and reset
> `entryStreet = nil`, `focusIndex = 0`.

---

## Step 2 — Entry state machine

All handlers operate on `group(for: entryStreet)`, mutate a local copy, and write back via
`setGroup`. Single-frame groups (turn/river) never enter footnote/relationship (capacity 1: the
first-suit rule always lands on bound, and there are no shortcut buttons).

### `openCardEntry`

```swift
private func openCardEntry(_ street: CardStreet) {
    entryStreet = street
    let g = group(for: street)
    focusIndex = g.firstEmptyIndex ?? 0      // left-most empty, else 0 (full → start of replace cycle)
}
```

Update the strip's tap callsites to call `openCardEntry(.hole)` etc. **without** a `focus:` argument
(the tapped index is intentionally ignored — see INDEX spec rule "tapping focuses left-most empty").

### `rankTapped`

```swift
private func rankTapped(_ r: String) {
    guard let street = entryStreet else { return }
    var g = group(for: street)

    if g.isFull {
        // Replace: typing into a full group starts a clean ranks-only entry.
        g.mode = .none; g.footnote = []; g.footnoteCursor = 0; g.relationship = nil
        for i in g.frames.indices { g.frames[i].suit = nil }
        g.frames[focusIndex].rank = r
        focusIndex = (focusIndex + 1) % g.capacity
    } else if g.frames[focusIndex].isEmpty {
        // Fill the cursor frame; cursor stays so a following suit can bind here (interleaving).
        g.frames[focusIndex].rank = r
    } else {
        // Cursor frame already ranked; fill the next empty and move the cursor there.
        if let i = g.firstEmptyIndex { g.frames[i].rank = r; focusIndex = i }
    }
    setGroup(street, g)
}
```

### `suitTapped` (handles `♠ ♥ ♦ ♣` and the unknown `x`)

Pass the suit symbol for the four suits, and `nil` (or a sentinel) for `x`. Convert symbols to letters
with the existing `suitLetter(_:)` helper.

```swift
private func suitTapped(_ symbol: String?) {        // symbol nil == the "x" (unknown) button
    guard let street = entryStreet else { return }
    var g = group(for: street)
    guard g.hasAnyRank else { return }              // gating belt-and-suspenders (button is also dimmed)

    if g.mode == .none {
        g.mode = (g.firstEmptyIndex != nil) ? .bound : .footnote
    }

    switch g.mode {
    case .bound:
        // Bind to the just-ranked card (the cursor). "x" leaves the suit unrecorded (nil).
        g.frames[focusIndex].suit = symbol            // nil for x
    case .footnote:
        let letter = symbol.map(suitLetter) ?? "x"
        if g.footnote.count < g.capacity {
            g.footnote.append(letter)
        } else {
            g.footnote[g.footnoteCursor] = letter
            g.footnoteCursor = (g.footnoteCursor + 1) % g.capacity
        }
    case .relationship, .none:
        break                                          // relationship is set only via shortcutTapped
    }
    setGroup(street, g)
}
```

> Wire the suit buttons: `suitSquare("♠")` → `suitTapped("♠")`, etc.; `unknownSuitSquare()` →
> `suitTapped(nil)`.

### `shortcutTapped` (replaces `relationshipTapped` + `textureTapped`)

```swift
private func shortcutTapped(_ value: String) {        // "s","o" | "r","m","tt"
    guard let street = entryStreet else { return }
    var g = group(for: street)
    guard g.isFull else { return }                    // gating belt-and-suspenders (button is also dimmed)
    g.mode = .relationship
    g.relationship = value
    g.footnote = []; g.footnoteCursor = 0
    for i in g.frames.indices { g.frames[i].suit = nil }
    setGroup(street, g)
}
```

### `clearEntryGroup` / `closeEntry`

```swift
private func clearEntryGroup() {
    guard let street = entryStreet else { return }
    var g = group(for: street); g.reset(); setGroup(street, g)
    focusIndex = 0
}
private func closeEntry() { entryStreet = nil }       // no mutation; blanks render as x via notation
```

---

## Step 3 — Two-tier dimming in the picker

Add computed gating for the open group and apply it to the buttons. In `cardPickerPanel` (or the
helpers it calls):

```swift
private var entryGroup: CardGroup? { entryStreet.map { group(for: $0) } }
private var suitsEnabled: Bool { entryGroup?.hasAnyRank ?? false }
private var shortcutsEnabled: Bool { entryGroup?.isFull ?? false }
```

- `suitSquare` / `unknownSuitSquare`: add `.disabled(!suitsEnabled)` and dim
  (`.opacity(suitsEnabled ? 1 : 0.35)`).
- `shortcutSquare`: add `.disabled(!shortcutsEnabled)` and dim likewise.
- Rank buttons stay always-enabled.

Match the existing disabled-chip treatment in `ControlBar` (opacity ~0.35 + `.disabled`).

---

## Step 4 — Add the `tt` (two-tone) flop shortcut

In `shortcutSquares(for:)`:

```swift
case .flop:
    shortcutSquare("r")  { shortcutTapped("r") }
    shortcutSquare("m")  { shortcutTapped("m") }
    shortcutSquare("tt") { shortcutTapped("tt") }
```

Hole stays `s`/`o` (wired to `shortcutTapped("s")` / `("o")`). Turn/river: no shortcuts (unchanged).
Confirm the centered cluster (`♠ ♥ ♦ ♣ x | r m tt`) still fits on a narrow phone; if tight, reduce the
inter-square spacing in `suitCluster` from 6 to 5 and/or the divider horizontal padding.

---

## Step 5 — Rewrite `groupNotation`

`groupNotation(_ street:)` must emit the compact token per the INDEX notation table. Drive it off the
`CardGroup` (not the old `CardSlot`). Keep `suitLetter(_:)`.

```swift
private func groupNotation(_ street: CardStreet) -> String {
    let g = group(for: street)
    let ranks = g.frames.compactMap { $0.rank }
    guard !ranks.isEmpty else { return "" }
    let rankStr = ranks.joined()

    switch g.mode {
    case .none:
        return rankStr                                   // AJ / Q53 / J

    case .relationship:
        return rankStr + (g.relationship ?? "")          // AJs / Q53r / Q53tt

    case .footnote:
        // Letters padded to capacity with "x": AJ + [d] -> "AJdx"; Q53 + [h,h] -> "Q53hhx".
        var letters = g.footnote
        while letters.count < g.capacity { letters.append("x") }
        return rankStr + letters.joined()

    case .bound:
        // Per-frame token. A frame with a suit -> rank+letter; suitless frame -> rank+"x" only when
        // some other frame has a real suit (markUnknown); otherwise bare rank. Single-frame groups
        // (turn/river) never mark unknown -> bare rank when unsuited.
        let anySuit = g.frames.contains { $0.suit != nil }
        let markUnknown = anySuit && g.capacity > 1
        return g.frames.compactMap { f -> String? in
            guard let r = f.rank else { return nil }
            if let s = f.suit { return r + suitLetter(s) }
            return markUnknown ? r + "x" : r
        }.joined()
    }
}
```

> `boardToken(for:)` and `actorSegment` (hero hole declaration) already call `groupNotation`/
> `groupNotation(.hole)` — they keep working unchanged. Verify `buildHeroCards()` still compiles: it
> previously read `heroCards`; point it at `holeGroup.frames` (rank + bound suit only — lossy for
> footnote/relationship, which is the accepted deferred behavior).

---

## Step 6 — Interim strip rendering (compile-only; final design is Phase 2)

The strip currently renders `CardSlot`s via `CardSlotView`. After the model change it must compile and
roughly show the group. Do the **minimum**: render each frame's rank (+ bound suit when present), and
show the `groupNotation(street)` string as a small caption under each group so behavior is legible.
Do **not** invest in the final card-face/caption design here — Phase 2 owns that. A terse adapter is
fine, e.g. map `group.frames` to the existing `CardSlotView` by synthesizing a `CardSlot` per frame
(rank + suit), and append a `Text(groupNotation(street))` caption.

Keep `entryStreet`-based active-frame highlighting working (the focused frame shows the gold ring).

---

## Step 7 — Update `ShorthandReference.md` §2 (Card notation)

This file is the authoritative notation spec. Add definitions for the new forms so it matches the
implementation. Edit **§2** to include:

- **Hole — relationship**: `AJs` (suited), `AJo` (offsuit) — unchanged, keep.
- **Hole — bound (interleaved)**: per-card suits, suitless card shown with `x` when its partner is
  suited: `AdJx`, `AsKd`, `AsKx`. (Restates existing "one suit known" rule.)
- **Hole — footnote (NEW)**: ranks first, then the suit letters as an unassigned trailing note, padded
  to two characters with `x`: `AJdx` (one diamond, one unspecified), `AJd` is rendered `AJdx`. Define
  it as "the suits are not assigned to a specific card."
- **Flop — relationship**: `Q53r` (rainbow), `Q53m` (mono), **`Q53tt` (two-tone, NEW)**.
- **Flop — bound**: per-card suits `Qh5h3x` (unchanged).
- **Flop — footnote (NEW)**: `Q53hhx` — ranks then suit letters padded to three with `x`.
- Add a one-line note that bound vs footnote is a *recording-time* distinction (which card carries a
  suit vs an unassigned note) and both are legal house style.

Keep the prose consistent with the existing §2 voice. Do not change §5–§11 (action shorthand).

---

## Acceptance checklist (Phase 1)

- [ ] Project compiles (user builds). No references remain to `heroCards`/`flopCards`/`turnCard`/
      `riverCard`, `relationshipTapped`, `textureTapped`, or `CardSlot.qualifier`.
- [ ] Suit buttons are dimmed/disabled with 0 ranks; enabled at ≥1 rank.
- [ ] Shortcut buttons are dimmed/disabled until all ranks in the group are filled.
- [ ] Flop shows three shortcut squares `r m tt`; the control row still fits centered.
- [ ] The on-screen transcript matches every Worked Example below.
- [ ] `ShorthandReference.md` §2 documents footnote and two-tone.

---

## Worked examples (behavioral source of truth)

Each line: the tap sequence → the expected `groupNotation` (what shows in the transcript token). Hole
group unless noted.

| # | Taps | Result | Why |
|---|---|---|---|
| 1 | `A` | `A` | partial, ranks only |
| 2 | `A` `J` | `AJ` | none mode |
| 3 | `A` `♦` `J` `♠` | `AdJs` | bound (first suit pressed while J empty); suits bind to the just-ranked card |
| 4 | `A` `♦` `J` `Done` | `AdJx` | bound; J left blank → `x` |
| 5 | `A` `J` `♦` | `AJdx` | footnote (first suit pressed when both ranks in); padded to 2 with `x` |
| 6 | `A` `J` `♦` `♥` | `AJdh` | footnote, two letters |
| 7 | `A` `J` `s` | `AJs` | relationship; shortcut enabled because both ranks in |
| 8 | `A` `J` `s` then `♦` | `AJdx` | suit press wipes relationship → footnote (ranks full) |
| 9 | `A` `♦` `J` `x` makes `AdJx`, then type `K` | `KJ` | rank-replace into a full group wipes all suits → clean ranks-only; cursor was at 0 |
| 10 | continue #9 with `T` | `KT` | next replace fills the right frame |
| 11 | `A` `s` | `A` (no suit applied) | `s` is a no-op until both ranks in (and is dimmed) |
| 12 | `♠` on an empty group | no change | suit no-op with 0 ranks (and is dimmed) |
| 13 (flop) | `Q` `5` `3` `tt` | `Q53tt` | two-tone relationship |
| 14 (flop) | `Q` `5` `3` `♥` `♥` | `Q53hhx` | footnote, padded to 3 |
| 15 (flop) | `Q` `h` `5` `h` `3` `Done` | `Qh5h3x` | bound interleaved; third blank → `x` |
| 16 (turn) | `J` `h` | `Jh` | bound single card |
| 17 (turn) | `J` `Done` | `J` | lone unsuited card → bare rank (no `x`) |

After Phase 1, hand off for the user to verify these via the transcript before starting Phase 2.
