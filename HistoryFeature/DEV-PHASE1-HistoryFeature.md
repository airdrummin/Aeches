# Phase 1 — Lossless `Hand` (canonical card model)

**Status:** ✅ Done (code landed; round-trip verified) · **Depends on:** nothing · **Unblocks:** all phases

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
- **Tighten `CardFrame.rank` from `String?` to `Rank?`** as part of the move (locked decision).
  Convert at the one spot the picker records a rank tap (`rankRow`, `HandEntryView` :2290/:1876 use
  `"T"` for ten — already `Rank.ten.rawValue`, so no drift); `groupNotation` (:2577) reads
  `Rank.rawValue`. A rank is never fuzzy, so nothing is lost and `T`-vs-`"10"` drift in the saved
  format becomes impossible.
- **Tighten `FrameSuit.known` from a glyph `String` to the `Suit` enum** (Option B, locked decision).
  Only the *known* (bound) suit is concrete, so it becomes typed; the rest of `FrameSuit`
  (`.unspecified`, `.unknown` = explicit `x`) and the group suit-mode system (footnote letters,
  relationship texture) stay loose — that's what carries footnote/relationship fuzziness, so those
  modes are untouched. **No `"s"` collision:** spades (a bound suit in the frame's `suit` field) and
  "suited" (a texture in the group's `relationship` field, still a plain `String`) live in separate
  fields under mutually-exclusive modes, and we persist the structured group rather than a parsed
  notation string — so `Suit.spades.rawValue == "s"` is unambiguous. Touch points where `known` is
  read/written (glyph → `Suit`, render via `Suit.symbol`):
  - **picker suit buttons** (`suitTapped`, :2489) — set `.known(Suit)` instead of a glyph string;
  - **on-card render** (`groupNotation` `.bound` case :2598, `CardFrameView`) — draw `s.symbol`,
    repeated by `suitRun`;
  - **duplicate-card block** — compare `Suit` directly instead of glyph strings;
  - the `suitKey`/`suitLetter`/`knownSymbol` glyph↔letter helpers mostly fold away once the payload
    is a `Suit` (`buildHeroCards`/`buildVillainCards` become trivial — the suit is already a `Suit`).

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
tableSize:           Int
occupiedSeatIndices: [Int]     // seats with a player — drives positions (was conflated)

// derived, computed (not stored) — keeps the old [Card] API for simple consumers
var holeCards: [Card] { holeGroup.asCards }
var villainCards: [Int: [Card]] { villainGroups.mapValues { $0.asCards } }
var board: [Card] { (flopGroup + turnGroup + riverGroup).flatMap { $0.asCards } }

// still-in at the end (hero excluded → villains) — DERIVED from the fold log, not stored
// (honors "don't keep two copies"; Phase 3's slicing helpers compute folds the same way)
var showdownSeatIndices: [Int] {
    let folded = Set(streets.flatMap { $0.actions }
        .filter { $0.actionType == .fold }.map { $0.seatIndex })
    return occupiedSeatIndices.filter { $0 != heroSeatIndex && !folded.contains($0) }
}
```

- **Retire** the old stored `holeCards`/`villainCards` and the `activeSeatIndices` field (replaced by
  the explicit `occupiedSeatIndices` set above, plus the derived `showdownSeatIndices`).
- **`Street.boardCards`**: board now lives in the groups, the single source of truth. Make
  `Street.boardCards` either removed from persistence or a derived convenience that reads the matching
  group — do **not** keep two writable copies. (Recommend: drop it from the stored `Street`; if a
  consumer wants `[Card]` per street, derive from the hand's groups.)
- Add `var asCards: [Card]` to `CardGroup` (the existing `build*Cards` collapse logic, centralized).

## Changes — file by file

- **`Models.swift`**
  - Add `CardGroup` / `CardFrame` / suit-mode + `FrameSuit` enums (moved from `HandEntryView`),
    `Codable` + `Equatable`, with `asCards`. `FrameSuit.known` now carries a `Suit` (Option B); the
    `Suit` enum is unchanged (short raw values `s/h/d/c` stay).
  - Update `Hand`: new fields above; computed `holeCards`/`villainCards`/`board`; remove the old
    stored card arrays and `activeSeatIndices`.
  - Confirm `calculatePositions` now reads `occupiedSeatIndices` semantics (callers pass occupied).
- **`HandEntryView.swift`**
  - Remove the local `CardGroup`/`CardFrame`/`FrameSuit` definitions (now in `Models`).
  - Retype `FrameSuit.known` usage glyph→`Suit` at every touch point listed under *Design* above
    (picker buttons, on-card render, duplicate block, helper fold-away).
  - Rewrite `buildHand` to populate the canonical groups (`holeGroup`, `flop/turn/riverGroup`,
    `villainGroups`), `tableSize`, and `occupiedSeatIndices = occupiedSeats`. Street records keep
    **actions only** (`showdownSeatIndices` is now derived, not written).
  - `buildHeroCards`/`buildVillainCards` collapse away (the flat `[Card]` is now derived on `Hand`).
  - **Rewrite `syncClosedHandCards` (:1508) to write the groups, not the flat arrays** — *required*,
    because `Hand.holeCards`/`villainCards` become computed (get-only) and the old assignments stop
    compiling. It must copy `holeGroup`, `villainGroups`, **and the board groups
    (`flopGroup`/`turnGroup`/`riverGroup`)** onto the saved hand, so a card edited on the frozen
    closed table — hero, villain, *or board* — persists (closing the post-close board-edit gap that
    exists today, where only hero/villain re-synced and the board wasn't stored at all).

## Verification (action-tested)

A round-trip is the acceptance bar. **Verification is manual** (locked decision — no permanent test
target); the hand below is the standard "every card mode" check, reused at every later phase. A
throwaway `#if DEBUG` harness is fine for the one-time Phase-1 check, then delete it:
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
