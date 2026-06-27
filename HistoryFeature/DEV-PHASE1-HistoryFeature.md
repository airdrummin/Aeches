# Phase 1 — Lossless `Hand` (canonical card model)

**Status:** ⬜ Not started · **Depends on:** nothing · **Unblocks:** all phases

## Goal

Make a saved `Hand` a *complete, faithful* record of everything entered — so it can drive History,
Replay, and Edit with zero loss. This is the foundation; nothing visual is correct until it's done.

## Why (what's broken today)

Verified in code:
- Every `Street` is built with `boardCards: []` — **board cards (flop/turn/river) are never persisted**
  (`HandEntryView.buildHand` :2796, street close :1366).
- `buildHeroCards`/`buildVillainCards` (:1483) map each frame to `Card(rank, suit)` using only the
  *bound* per-frame suit. **Footnote** suits live on the group (unassigned) and **relationship**
  textures have no per-card suit at all → both are **dropped on save**.
- `Hand.activeSeatIndices` is set to `activeSeatSequence` (non-folded seats), but `calculatePositions`
  expects **occupied** seats → position labels computed from a saved hand are wrong once seats fold
  (README known-limitation #2).
- `tableSize` and `emptySeats` are not on `Hand` at all (live `@State` only) → a replayed hand can't
  reconstruct the table shape.

## Design — canonical card storage

Promote the card-entry types into the model layer and make them `Codable`, then store them directly
on `Hand`. The `CardGroup` *is* the faithful artifact (it's what the live transcript already renders);
the flat `[Card]` arrays become *derived* for simple consumers.

### Move into `Models.swift` and make `Codable`
- `CardGroup`, `CardFrame`, and their enums (suit mode, frame-suit state) currently live in
  `HandEntryView.swift`. Move them to `Models.swift`, conform to `Codable` (+ `Equatable` for the
  round-trip test). Keep the live UI referencing the same types — no behavior change, just relocation.

### `Hand` changes
Add the canonical groups; keep flat arrays as **computed** derivations (so existing readers/marketplace
keep working):

```
// new canonical card storage (lossless)
holeGroup:     CardGroup
flopGroup:     CardGroup?      // nil until the street was reached/entered
turnGroup:     CardGroup?
riverGroup:    CardGroup?
villainGroups: [Int: CardGroup]

// table composition (new)
tableSize:        Int
occupiedSeatIndices: [Int]     // seats with a player — drives positions (was conflated)
showdownSeatIndices: [Int]     // still-in at the end (hero excluded → villains)

// derived, computed (not stored) — keeps the old [Card] API for simple consumers
var holeCards: [Card] { holeGroup.asCards }
var villainCards: [Int: [Card]] { villainGroups.mapValues { $0.asCards } }
var board: [Card] { (flopGroup + turnGroup + riverGroup).flatMap { $0.asCards } }
```

- **Retire** the old stored `holeCards`/`villainCards` and the `activeSeatIndices` field (replaced by
  the two explicit seat sets above).
- **`Street.boardCards`**: board now lives in the groups, the single source of truth. Make
  `Street.boardCards` either removed from persistence or a derived convenience that reads the matching
  group — do **not** keep two writable copies. (Recommend: drop it from the stored `Street`; if a
  consumer wants `[Card]` per street, derive from the hand's groups.)
- Add `var asCards: [Card]` to `CardGroup` (the existing `build*Cards` collapse logic, centralized).

## Changes — file by file

- **`Models.swift`**
  - Add `CardGroup` / `CardFrame` / suit-mode + frame-suit enums (moved from `HandEntryView`),
    `Codable` + `Equatable`, with `asCards`.
  - Update `Hand`: new fields above; computed `holeCards`/`villainCards`/`board`; remove the old
    stored card arrays and `activeSeatIndices`.
  - Confirm `calculatePositions` now reads `occupiedSeatIndices` semantics (callers pass occupied).
- **`HandEntryView.swift`**
  - Remove the local `CardGroup`/`CardFrame` definitions (now in `Models`).
  - Rewrite `buildHand` to populate the canonical groups (`holeGroup`, `flop/turn/riverGroup`,
    `villainGroups`), `tableSize`, `occupiedSeatIndices = occupiedSeats`,
    `showdownSeatIndices = activeSeatSequence`. Street records keep **actions only**.
  - `buildHeroCards`/`buildVillainCards`/`syncClosedHandCards` either deleted or reduced to writing
    the groups (no flat-card collapse).

## Verification (action-tested)

A round-trip is the acceptance bar. Suggested temporary `#if DEBUG` harness (removed after):
1. Record a hand exercising **every** card mode: a **footnote** hole (`AJdx`), a **relationship**
   flop (`Q53tt`), a bound turn (`Jh`), a board-suit-count river (`5ss`), and a villain (`AKs`).
2. `let data = try JSONEncoder().encode(hand); let back = try JSONDecoder().decode(Hand.self, from: data)`.
3. Assert `transcript(for: hand) == transcript(for: back)` (Phase 3 builder, or compare the existing
   live transcript string captured at save).
4. Assert `hand == back` (Equatable) for the card groups + seat sets.

**Done when:** a fully-entered hand encodes → decodes → re-renders an identical transcript and board;
positions are correct with folded seats present; `tableSize`/empty seats survive. No flat-card loss.

## Risks / notes

- This is a **breaking model change** — old dev JSON (if any from earlier experiments) is discarded
  (bump `storeVersion` in Phase 2). Fine: test data.
- Touch surface in `HandEntryView` is mechanical (relocating types, rewriting one builder). Keep the
  live recording behavior byte-identical — this phase persists more, it does not change recording.
