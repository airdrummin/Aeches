# Phase 6 — Edit (rehydrate + write-back)

**Status:** ⬜ Not started · **Depends on:** Phase 2 (store), Phase 5 (renderers proven end-to-end)

## Goal

Open a saved hand back in the **real recording screen**, fully editable — undo/redo table actions,
revise cards, change the outcome — then write the changes back to the store. One engine for new and
edited hands (DRY).

## Why

The user wants Edit to "return to the screen of the event" and revise. Because a `Hand` is now lossless
(Phase 1), we can reconstruct the exact live `@State` the recorder needs — the reverse of `buildHand`.

## Design

### Rehydration initializer on `HandEntryView`
```
init(session: Session, editing hand: Hand, onBack: ...)
```
Reconstruct live `@State` from the hand (mirror image of `buildHand` / `resetHandState`):
- `handNumber`, `heroSeat`, `buttonSeat`, `tableSize`, `emptySeats` ← from the hand.
- `streets` ← the hand's streets (actions); `currentStreet`, `actionsThisStreet`, `betLevelThisStreet`
  ← re-derived from the last street.
- `foldedSeats`, `activeSeatSequence` ← re-derived from the action log.
- Card groups (`holeGroup`, `flop/turn/riverGroup`, `villainGroups`) ← copied from the hand's groups.
- `effectiveStack` ← from the hand.
- **Phase** ← `.handClosed` (land on the frozen summary, exactly where recording leaves a finished
  hand) so the user can Undo into it, or re-open the showdown overlay, using the *existing* machinery.

### Edit identity + write-back
- Carry the hand's `id` so the close path calls `store.saveHand(_, in:)` as a **replace-by-id**, not an
  append (the replace-by-id from Phase 2 already does this).
- All existing recording interactions (Undo batches, Next Street, sizing, card picker, Skip/Move) work
  unchanged because the live state is genuinely reconstructed — no special "edit mode" branching beyond
  the entry point and the save target.

### Entry point
- `HandDetailView` **Edit** button pushes `HandEntryView(session:editing:hand:)`.

## Changes — file by file

- **`HandEntryView.swift`** — add the `editing:` initializer + a private `rehydrate(from: Hand)` that
  fills every `@State` (the inverse of `buildHand`). Ensure the close/save path targets the hand's id.
- **`HandDetailView.swift`** — wire the **Edit** button.
- **`ContentView.swift` / nav** — present the recorder from History (modal or pushed), returning to the
  detail/list on close.

## Verification (action-tested)

1. Edit a saved hand: Undo the last action, change a hole card from footnote to bound, re-close →
   reopen from History → changes are present and the transcript reflects them.
2. Edit a hand's outcome (Undo to reopen the Win/Lose/Chop overlay, re-pick) → stored outcome updates.
3. Editing does **not** create a duplicate — the same hand id is replaced; History count is unchanged.
4. Round-trip after edit still lossless (Phase 1 assert holds on the edited hand).

**Done when:** any saved hand can be reopened in the recorder, revised with the normal controls, and
saved back over itself with full fidelity.

## Risks / notes

- Rehydration is the inverse of `buildHand` — keep them adjacent and reviewed together so they never
  drift. A round-trip test (`buildHand(rehydrate(h)) == h`) guards this.
- Re-deriving `foldedSeats`/`activeSeatSequence` from the log must match what live recording would have
  produced; lean on the Phase 3 derivation helpers so there's one definition.
- Decide nav: editing from History likely presents the recorder **modally** (its own back), distinct
  from the Record tab's live session — confirm before building.
