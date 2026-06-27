# Phase 3 — Pure renderers (the DRY core)

**Status:** ⬜ Not started · **Depends on:** Phase 1 · **Unblocks:** History (4), Replay (5)

## Goal

Make the table visuals and the transcript **pure functions of a `Hand`**, not of live `@State`. This
is the DRY payoff: recording, History rows, and Replay all render through *one* implementation.

## Why

Both are currently welded to live recording state:
- **Seat visuals** — `HandEntryView.seatActions` (:994) derives each seat's `SeatState` from
  `actionsThisStreet` / `foldedSeats` / `highlightedSeat` / `phase`. Pure logic, trapped as an
  instance property over a dozen `@State` vars.
- **Transcript** — the builder (~:2600) reads `streets` **and live `CardGroup`s** for board notation,
  so it can't render a saved hand's board.

A saved `Hand` (post-Phase 1) now carries everything these need — so extract the logic to operate on it.

## Design

### Seat-state deriver (pure, free/static function)
```
func seatStates(
    streetActions: [Action],     // the street being rendered
    foldedBefore:  Set<Int>,     // seats folded on earlier streets
    allIn:         Set<Int>,     // all-in seats — drives the amber ALL IN badge across streets
    allActions:    [Action],     // every action (all streets) — to recover HOW each seat got all-in
    highlighted:   Int?,         // nil for replay/closed; the cue seat while recording
    owes:          (Int) -> Bool // re-aggression test; constant-false for replay
) -> [Int: SeatState]
```
- Lift the body of `seatActions` verbatim into this function (prior-action histories, bet-level pips,
  fold ghosts, owes-fresh-response demotion). The live computed `seatActions` becomes a thin caller
  that passes its `@State` in. Replay passes the hand's per-street slice with `highlighted: nil`.
- **Include the all-in badge logic** (`seatActions` :1062–1080). It needs the `allIn` set plus the full
  `allActions` list to surface the amber badge — with the correct jam symbol (`→`/`↑↑`/`✓`) — on streets
  where the all-in seat took no action of its own. Live recording passes its `allInSeats` + all actions;
  Replay derives the all-in set from the hand (sized `All-in` markers) and passes `hand`'s actions.

### Transcript builder (pure, function of a `Hand`)
```
func transcript(for hand: Hand) -> [TranscriptLine]   // or the existing String form
```
- Reads `hand.streets[].actions` for the action grammar and **`hand`'s canonical card groups** for
  hole/board/villain notation (via `groupNotation`, which also moves to operate on a passed group).
- Live recording renders `transcript(for: liveHandSnapshot)` (build the in-progress hand cheaply, or
  pass the same pieces) — so the live transcript and the saved transcript share one code path.

### Per-street replay slicing (helper)
```
func foldedBefore(street: StreetName, in hand: Hand) -> Set<Int>
func actions(on street: StreetName, in hand: Hand) -> [Action]
```
Used by Replay (Phase 5) to drive the deriver street-by-street.

## Changes — file by file

- **New `Rendering/HandRendering.swift`** (or extend `Models`/a `Hand+Render` extension) — the pure
  `seatStates(...)`, `transcript(for:)`, `groupNotation(_:)`, and the slicing helpers.
- **`HandEntryView.swift`** — `seatActions` and the transcript builder become thin wrappers that call
  the extracted functions with live state. Behavior unchanged.
- **`SeatSelectionView.swift`** — no change expected; `TableOvalView`/`SeatButtonView` already take
  `SeatState` and stay the dumb render layer.

## Verification (action-tested)

1. **No-regression on recording:** the live table + transcript look and behave exactly as before
   (the wrappers feed the same inputs).
2. **Parity:** for a just-closed hand, `transcript(for: storedHand)` equals the live transcript string
   captured at close; `seatStates(...)` for each street matches what the live table showed per street.
3. Re-run the Phase 1 round-trip assert using `transcript(for:)` as the comparator.

**Done when:** the table and transcript can be rendered from a `Hand` alone, recording uses the same
functions, and outputs are identical to today.

## Risks / notes

- The `owesAction` demotion and the run-out "display street fallback" logic (:1005) are subtle — port
  them faithfully; they're why a closed all-in hand shows the right street. Replay passes the explicit
  street, so the fallback is recording-only.
- Keep `SeatState` and the seat render components unchanged — this phase only moves *derivation*.
