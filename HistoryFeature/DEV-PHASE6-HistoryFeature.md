# Phase 6 — Edit (rehydrate + write-back) + resume skipped hands

**Status:** ✅ Done · **Depends on:** Phase 2 (store), Phase 5 (renderers proven end-to-end)

## Goal

Open a saved hand back in the **real recording screen** and write changes back over the same hand. Two
flavors, one engine:
- **Edit a completed hand** — reopen at the frozen summary; undo/redo actions, revise cards, change the
  outcome.
- **Resume a skipped (incomplete) hand** — reopen **live at the table**, cue restored, and finish it
  normally. (Users skip hands often and must be able to come back and complete them.)

One recording engine for new, edited, and resumed hands (DRY).

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
- **Phase** ← branches on completion (see below): complete → `.handClosed` (frozen summary, edit via
  the existing Undo / showdown-overlay machinery); incomplete → `.recordingHand` (resume live).

### Completion: `isComplete` + resume-vs-edit (locked)
`outcome == nil` is ambiguous — a finished fold-out and a skipped hand both save it, and a
hero-fold-then-skip is indistinguishable from a real villain showdown. So store the fact, don't infer it:
- Add **`Hand.isComplete: Bool`** (default `true`). `skipHand` sets it `false`; every real close
  (`triggerFoldOut`, `resolveShowdown`, the hero-folded `reachShowdown`) sets it `true`. `buildHand`
  carries it. (Model change → bump `storeVersion`.)
- **`Hand.result`** reads the flag: `!isComplete → .incomplete` (authoritative — fixes the Phase 4 chip's
  hero-fold-then-skip mislabel); otherwise derive win/lose/chop/folded as today.
- **Rehydrate branches on it:**
  - **complete →** `.handClosed`, frozen summary (Edit).
  - **incomplete →** `.recordingHand`, cue restored by reusing the *existing* skipped-reopen step (the
    Undo-on-skip path, `HandEntryView.swift` ~:1108: `highlightedSeat = actionsThisStreet.last?.seatIndex
    ?? firstActor(of: currentStreet)`) — so Resume lands exactly where the live Skip→Undo flow does, no
    new cue reconstruction, no Undo tap.

### Edit identity + write-back
- Carry the hand's `id` (`rehydrate` sets `currentHandID = hand.id`) so the close path's
  `store.saveHand(_, in:)` is a **replace-by-id**, not an append (Phase 2 already does this).
- **Carry the hand's `sessionId` too.** `saveHand(_, in: sessionId)` resolves the session *first*, and
  the recorder's three save sites currently pass `session.id` (HandEntryView :2552, :1431, buildHand's
  `sessionId` :2522). Writing back with the wrong session id would duplicate into the wrong session. Add
  a `currentSessionID` (= `session.id` normally; set to `hand.sessionId` on rehydrate; reset in
  `resetHandState`) and route those sites through it. Because `tableSize`/`heroSeat`/etc. are `@State`
  that rehydrate overrides, this lets the screen edit/resume a hand from **any** session with no
  `activeSession` swap (no teardown of the live hand).
- All existing recording interactions (Undo batches, Next Street, sizing, card picker, Skip/Move) work
  unchanged — the live state is genuinely reconstructed; no "edit mode" branching beyond the entry
  point, the completion-based landing phase, and the save target.

### Entry point + nav
- `HandDetailView`'s action button reads **"Resume"** for an incomplete hand, **"Edit"** for a complete
  one (label + landing phase key off `isComplete`).
- It routes to the shared **Record-tab recording screen** (no modal, no fresh recorder): set
  **`editingHandID` on `SessionStore`**; `ContentView` observes it and switches `activeTab = .record`;
  `HandEntryView` observes it, auto-saves its current live hand Skip-style (existing `skipHand`, only if
  a live hand is in progress), `rehydrate(from: store.hand(id:))`s the target, then clears
  `editingHandID`. On close it saves back by id; the auto-skipped live hand remains in History.
- **Exit via "Done".** While editing/resuming (`isEditing`), the nav "Back" becomes **Done**: it flushes
  an open card picker, saves on the way out — an unfinished (still-live) hand persists Skip-style
  (incomplete, **resumable again**); a closed hand is already saved — resets the recorder to a fresh
  hand for the live session (next `handNumber`), and returns to the **History tab** (`store.jumpToHistory`
  → `ContentView`). So you never silently lose progress and never land on the New Session screen.
- **`HandDetailView` resolves the hand from the store by id** (not a captured snapshot), so returning
  after an edit shows the updated hand, not stale data.
- **Release cold-start deferred:** in DEBUG the dev-session `HandEntryView` is always mounted, so this
  works in place. The case where `activeSession == nil` (a shipped app opened to just History, recorder
  not mounted) is handled when the real session/auth flow lands (pairs with Phase 7).

## Changes — file by file

- **`Models.swift`** — add `Hand.isComplete: Bool = true`; `Hand.result` reads it (`!isComplete →
  .incomplete`). Bump `storeVersion` (in `HandStore.swift`).
- **`HandEntryView.swift`** — add `rehydrate(from: Hand)` (inverse of `buildHand`, kept adjacent to it),
  branching the landing phase on `isComplete`; reuse the skipped-reopen cue step for Resume. Add
  `currentSessionID` and route the three save sites + `buildHand` through it; `buildHand` carries
  `isComplete`. `skipHand` sets incomplete; the real closes set complete. Observe `store.editingHandID`
  to drive auto-skip → rehydrate → clear.
- **`HandDetailView.swift`** — the action button shows **Resume** (incomplete) / **Edit** (complete) and
  sets `store.editingHandID`.
- **`ContentView.swift`** — observe `store.editingHandID`; switch to the Record tab when set.
- **`SessionStore.swift`** — add `@Published var editingHandID: UUID?`.

## Verification (action-tested)

1. Edit a completed hand: Undo the last action, change a hole card from footnote to bound, re-close →
   reopen from History → changes are present and the transcript reflects them.
2. Edit a hand's outcome (Undo to reopen the Win/Lose/Chop overlay, re-pick) → stored outcome updates.
3. **Resume a skipped hand:** Skip a hand mid-street → from History it shows **Incomplete** with a
   **Resume** button → tap → land live at the table with the cue restored → finish it (showdown/fold-out)
   → it reopens **complete** (chip updates), same hand id, no duplicate.
4. Editing/resuming does **not** create a duplicate — the same hand id is replaced; History count is
   unchanged. A cross-session hand writes back to **its own** session (no leak/dupe).
5. **Render-parity round-trip:** `transcript(for: buildHand(rehydrate(h)))` and the per-street
   `seatStates` match the original `h` (the meaningful losslessness — see the round-trip note).

**Done when:** any saved hand can be reopened in the recorder — completed hands edited, skipped hands
resumed and finished — and saved back over itself with full fidelity.

## Risks / notes

- Rehydration is the inverse of `buildHand` — keep them adjacent and reviewed together so they never
  drift.
- **Round-trip is render-parity, not literal `==`.** `buildHand` wraps the live actions in a fresh
  `Street` (new `UUID`), so `buildHand(rehydrate(h)) == h` won't hold byte-for-byte (one Street id
  differs; actions and everything rendered are identical). Verify via `transcript(for:)` + group/seat
  equality (Option A), the Phase-1 "renders identically" bar — not raw struct equality.
- Re-deriving `foldedSeats`/`activeSeatSequence`/`betLevelThisStreet` is **free**: set `streets` /
  `currentStreet` / `actionsThisStreet` (split `hand.streets` on `hand.lastStreet`) and the card groups,
  then call the existing `recomputeDerivedState()` — one definition, no second derivation.
- **Completion flag is a model change** → bump `storeVersion`; the dev file resets (no migration while
  iterating). It also makes the Phase 4 "Incomplete" chip authoritative.
- **Nav (locked): reuse the single recording screen — no modal.** Entering Edit auto-saves any
  in-progress live hand exactly like **Skip** (saved incomplete, all state preserved so Undo reopens it),
  then loads the edit hand into the same screen. This leans on the existing Skip→Undo machinery rather
  than a second `HandEntryView` instance, so an interrupted live hand is preserved, not lost. Trade-off
  accepted: if you were mid-hand when you hit Edit, that live hand freezes (resumable later) rather than
  staying live underneath a modal.
