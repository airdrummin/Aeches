# Phase 5 — Replay (read-only, step-through)

**Status:** ⬜ Not started · **Depends on:** Phase 3 (renderers), Phase 4 (detail screen)

## Goal

A read-only "replay" of a saved hand using the **real table visuals + transcript**, advanced one
street at a time. No engine, no mutation — purely a render of the `Hand` through the Phase 3 functions.

## Why

The user wants to re-watch a hand as it played. We already have the dumb table components
(`TableOvalView`/`SeatButtonView`) and, after Phase 3, a pure way to compute seat states per street.

## Design

### `ReplayView(hand: Hand)`
- **State:** `@State private var streetIndex` over the streets the hand reached
  (Preflop → Flop → Turn → River → Showdown), clamped to what exists.
- **Table:** `TableOvalView` fed by `seatStates(streetActions: actions(on: street), foldedBefore:
  foldedBefore(street), highlighted: nil, owes: { _ in false })`. Dealer button, positions (now correct
  via `occupiedSeatIndices`), and empty seats (from `hand.tableSize` + persisted empties) all render
  from the hand.
- **Cards:** the card strip shows hole + the board **up to the current street** (flop cards appear on
  flop, etc.), plus villains at showdown — read from the hand's canonical groups, display-only (reuse
  the existing card-strip render, no picker).
- **Transcript:** the shorthand panel below, with the **current street's line(s) emphasized** as you
  step (scroll/höight as today).
- **Controls:** a Prev / Next stepper (tap to advance). Felt center can echo the street label, and the
  outcome ("You win", "Seat X wins", etc.) on the final step.

### Strictly read-only
- No `onTapGesture`/swipes on seats, no control bar, no card picker. Reuses render components but not
  the recording interactions.

## Changes — file by file

- **New `Replay/ReplayView.swift`** — the stepper screen built from Phase 3 functions + shared
  render components.
- **`HandDetailView.swift`** — wire the **Replay** button to push `ReplayView(hand:)`.
- Possibly extract the **card-strip display layer** (faces/captions, minus the picker/gestures) into a
  reusable `CardStripDisplay(hand:, throughStreet:)` so recording and replay share it (DRY) — recommended.

## Verification (action-tested)

1. Replay a multi-street hand with folds and a 3-bet → at each street the seats show the correct
   actions/pips, folded seats ghost, the board reveals progressively, positions are right.
2. Replay a fold-out (ends preflop) → stepper stops at the right street; felt shows "Seat X wins".
3. Replay an all-in run-out → board reveals; final step shows the outcome.
4. Replay a hand with footnote/relationship cards → the strip + transcript render exactly as recorded
   (Phase 1 lossless guarantee, observed end-to-end).

**Done when:** any saved hand can be stepped through and matches what recording showed, with no way to
mutate it.

## Risks / notes

- Position labels must use `occupiedSeatIndices` (Phase 1) — verify folded seats still label correctly,
  the exact bug Phase 1 fixed.
- Showdown step: reuse the villain card display; no result *overlay* (that's an input affordance) —
  show the outcome as felt text, like the frozen summary state.
