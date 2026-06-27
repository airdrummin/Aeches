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

### Rehydration entry on `HandEntryView` (single-screen reuse — locked)
Edit reuses the **one** Record-tab recording screen — **no modal, no second `HandEntryView`**. Entering
Edit first **auto-saves the current live hand Skip-style** (saved incomplete, all state preserved so
Undo reopens it — the existing `skipHand` path), then calls `rehydrate(from: hand)` on that same screen.

```
private func rehydrate(from hand: Hand)   // the inverse of buildHand / resetHandState
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
- `HandDetailView` **Edit** routes to the shared **Record-tab recording screen** (it does *not* push a
  fresh recorder): hand the edit hand's id to the screen (e.g. an `editingHandID` on `SessionStore` or a
  binding) and switch to the Record tab. The screen auto-saves its current live hand Skip-style, then
  `rehydrate(from:)`s the edit hand. On close it saves back by id; the auto-skipped live hand remains in
  History, resumable via Undo. (Land post-edit on the edited hand's frozen summary.)

## Changes — file by file

- **`HandEntryView.swift`** — add a private `rehydrate(from: Hand)` that fills every `@State` (the
  inverse of `buildHand`), invoked after an auto-save (Skip path) of the current live hand. Ensure the
  close/save path targets the **edited hand's id** (replace-by-id), not a new append.
- **`HandDetailView.swift`** — wire the **Edit** button to set the edit target + switch to Record.
- **`ContentView.swift` / nav** — Edit routes to the **Record tab** (switch tabs + hand off the edit
  hand's id via the store/binding); no modal, no second recorder. After close the user is on the Record
  tab with the edited hand saved; History reflects it.

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
- **Nav (locked): reuse the single recording screen — no modal.** Entering Edit auto-saves any
  in-progress live hand exactly like **Skip** (saved incomplete, all state preserved so Undo reopens it),
  then loads the edit hand into the same screen. This leans on the existing Skip→Undo machinery rather
  than a second `HandEntryView` instance, so an interrupted live hand is preserved, not lost. Trade-off
  accepted: if you were mid-hand when you hit Edit, that live hand freezes (resumable later) rather than
  staying live underneath a modal.
