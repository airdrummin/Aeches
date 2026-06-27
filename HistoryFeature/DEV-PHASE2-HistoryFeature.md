# Phase 2 — Store + persistence

**Status:** ⬜ Not started · **Depends on:** Phase 1 · **Unblocks:** History (4), Edit (6)

## Goal

One shared, persisted source of truth for sessions and hands. Record writes through it; everything
else reads from it. Survives app relaunch. Cloud-ready via a protocol seam.

## Why

Today hands live in `HandEntryView`'s private `@State savedHands` (:47) and die on `onBack`
(`activeSession = nil`, `ContentView` :74). Nothing is persisted; History has nothing to read.

## Design

### `HandStore` protocol (the cloud seam)
```
protocol HandStore {
    func load() -> [Session]
    func save(_ sessions: [Session])
}
```
- **`FileHandStore`** (now): Codable JSON in `Application Support/aeches-store.json`, **atomic** write,
  writes **debounced** (coalesce rapid saves). Carries a `storeVersion`; on mismatch during dev,
  discard + start empty (no migration code while iterating).
- **`CloudHandStore`** (later): same protocol, different backend. Nothing above changes.

> **Server-friendly seam (locked).** Consumers always write through the per-hand
> `SessionStore.saveHand(_:in:)` — never a bulk "save everything" call from a feature. For v1,
> `FileHandStore` still persists by rewriting the single debounced + atomic JSON (fine at ~8–12
> hands/session); a future `CloudHandStore` maps that same per-hand intent to one document write with no
> consumer change. If whole-blob rewrites ever bite, split to one file per session behind the same
> protocol — still invisible above `HandStore`.

### `SessionStore: ObservableObject` (single source of truth)
```
@Published private(set) var sessions: [Session]
// CRUD used by the app
func upsertSession(_:)                       // create / update a session
func saveHand(_ hand: Hand, in sessionId:)   // UPSERT by hand.id within a session
func allHands() -> [Hand]                     // flattened, newest-first (History)
func hand(id:) -> Hand?  /  session(id:) -> Session?
```
- Loads via the injected `HandStore` on init; persists on every mutation (debounced).
- Holds the store type behind the protocol — testable with an in-memory fake.
- **`saveHand` is a single idempotent upsert** keyed on `hand.id`: find that id within the session,
  replace in place if present, else append. There is no separate add/update/delete — close,
  re-close, post-close card edit, and (Phase 6) edit-write-back are all the same call. This is what
  makes re-close-after-Undo update in place instead of duplicating (see Identity below).

### Identity & the single write path (locked decision)

`Hand.id` is the **one durable identity** for a hand — used by the store, History, Replay, and Edit.
We do **not** key on `(sessionId, handNumber)`: `handNumber` is a display ordinal (repeats across
sessions, reused across re-closes), whereas `Hand.id` is the natural one-document-per-id key the
future `CloudHandStore` and Edit both want.

To make that work, the in-progress hand carries a stable id instead of minting a fresh `UUID` per
build:
- **`@State private var currentHandID = UUID()`** — the live hand's identity. `buildHand` constructs
  the `Hand` with `id: currentHandID` (today `Hand(...)` mints a new `UUID` every call).
- Regenerated **only when a new hand begins** — inside `resetHandState()`, whose only callers are the
  two new-hand boundaries (`startNewHand`, `moveSeat`). **Undo-at-close does not regenerate it** — the
  hand is being reopened, so it keeps its id; re-close upserts in place.
- **`@State private var currentOutcome: Outcome? = nil`** — set at each close, reset in
  `resetHandState`. Lets post-close edits rebuild via `buildHand(outcome: currentOutcome)` without
  reading back the (now-removed) `savedHands` array.

**`buildHand` is the single `Hand` constructor; `store.saveHand` is the single persist call.** Every
persistence event — close, post-close card/eff sync, future edit — is `buildHand → store.saveHand`.
No field-by-field patching path that can drift from `buildHand`.

### Wiring
- **`AechesApp`**: `@StateObject private var store = SessionStore(backing: FileHandStore())`;
  inject with `.environmentObject(store)` on `ContentView`.
- **`RecordTab`**: `activeSession` becomes a reference into the store (create via `upsertSession`,
  resume the open one) instead of throwaway local `@State`.
- **`HandEntryView`**: gains `@EnvironmentObject var store`, plus `currentHandID` / `currentOutcome`.
  - **At close** (`saveCurrentHand`): set `currentOutcome`, then `store.saveHand(buildHand(outcome:), in: session.id)`.
  - **Post-close card/eff edits** (`syncClosedHandCards`): re-route to `store.saveHand(buildHand(outcome: currentOutcome), in: session.id)` instead of mutating a local array.
  - **Undo-at-close**: stop calling `savedHands.popLast()`. Read the closed snapshot with
    `store.hand(id: currentHandID)` and branch on its `outcome` / `showdownSeatIndices` exactly as
    before. **Leave the persisted copy in place** — it's overwritten on re-close, never deleted.
  - The private `savedHands` array is removed as the source of truth — the store is authoritative.

## Changes — file by file

- **New `Persistence/HandStore.swift`** — protocol + `FileHandStore` (+ `InMemoryHandStore` for tests).
- **New `Persistence/SessionStore.swift`** — the `ObservableObject` + CRUD.
- **`AechesApp.swift`** — own the `SessionStore`, inject it.
- **`ContentView.swift`** — `RecordTab` resolves `activeSession` through the store.
- **`HandEntryView.swift`** — add `currentHandID` + `currentOutcome` state; `buildHand` uses
  `id: currentHandID`; route close and post-close `syncClosedHandCards` through
  `store.saveHand` (upsert); undo-at-close reads `store.hand(id:)` instead of `popLast` and leaves the
  saved copy in place; drop `savedHands` as the source of truth. Regenerate `currentHandID` /
  reset `currentOutcome` in `resetHandState`.
- **`README.md`** — update the **Technical Constraints** section as part of this phase (see Risks): the
  "no `@EnvironmentObject` / observable context layer" rule is replaced by the `SessionStore` model.
  Note the protocol seam (`HandStore`) and that recording UI *interaction* state still lives in
  `HandEntryView` — only the persisted hand data moves to the store.

## Verification (action-tested)

1. Record 3 hands in a session → force-quit the app → relaunch → the session + 3 hands are still there
   (inspect `aeches-store.json`, or a temporary History debug print).
2. Re-close a hand after an Undo → the stored hand is **updated, not duplicated** (count stays 3).
3. Enter villain/board cards **after** close → the persisted hand reflects them (post-close sync
   re-saves the same id, not a duplicate; count stays 3).
4. **Undo-at-close, then force-quit** (do not re-close) → relaunch shows the hand at its **last-closed**
   state (it is not lost, and it is not duplicated).
5. Create a second session → both persist; `allHands()` returns 4 newest-first.
6. `README.md` Technical Constraints reflects the new store architecture (no stale "no observable
   layer" rule).

**Done when:** hands persist across relaunch, saving is debounced + atomic, and every persist
(close / re-close / post-close edit) upserts by `hand.id` — never duplicates. No `@State`-local hand
storage remains as the source of truth. The README's Technical Constraints section matches the
shipped architecture.

## Risks / notes

- Keep recording behavior identical — this phase changes *where* the hand goes at close, not how it's
  built (Phase 1) or recorded.
- **Undo-at-close behavior change (intentional, agreed).** Undo no longer removes the hand from
  storage — it reopens the live state and leaves the last-closed snapshot persisted (overwritten on
  re-close). Consequence: undo-then-quit-without-re-closing now **retains** the last-closed hand
  instead of losing it (today's `popLast` discards it). Strictly more durable, and it removes any need
  for a delete-from-store path.
- Debounce must still flush on background/terminate (`scenePhase`) so the last hand isn't lost.
- **README invariant reversed (intentional).** Adding the app-wide `SessionStore`
  (`ObservableObject` + `@EnvironmentObject`) contradicts the README's Technical Constraints
  ("All hand recording state is local to `HandEntryView`… No `@EnvironmentObject` or observable context
  layer"). That rule predates persistence and can't hold once History reads the same hands. **Update
  the README's Technical Constraints when this phase lands.**
