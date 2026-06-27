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

### `SessionStore: ObservableObject` (single source of truth)
```
@Published private(set) var sessions: [Session]
// CRUD used by the app
func upsertSession(_:)                       // create / update a session
func saveHand(_ hand: Hand, in sessionId:)   // append or replace-by-id within a session
func allHands() -> [Hand]                     // flattened, newest-first (History)
func hand(id:) -> Hand?  /  session(id:) -> Session?
```
- Loads via the injected `HandStore` on init; persists on every mutation (debounced).
- Holds the store type behind the protocol — testable with an in-memory fake.

### Wiring
- **`AechesApp`**: `@StateObject private var store = SessionStore(backing: FileHandStore())`;
  inject with `.environmentObject(store)` on `ContentView`.
- **`RecordTab`**: `activeSession` becomes a reference into the store (create via `upsertSession`,
  resume the open one) instead of throwaway local `@State`.
- **`HandEntryView`**: gains `@EnvironmentObject var store`. At hand close (`saveCurrentHand`),
  call `store.saveHand(builtHand, in: session.id)` (replace-by-id so re-closing/editing updates,
  not duplicates). The private `savedHands` array is removed, or kept only as a thin live mirror —
  the store is authoritative.

## Changes — file by file

- **New `Persistence/HandStore.swift`** — protocol + `FileHandStore` (+ `InMemoryHandStore` for tests).
- **New `Persistence/SessionStore.swift`** — the `ObservableObject` + CRUD.
- **`AechesApp.swift`** — own the `SessionStore`, inject it.
- **`ContentView.swift`** — `RecordTab` resolves `activeSession` through the store.
- **`HandEntryView.swift`** — write closed hands to the store (replace-by-id); drop `savedHands` as
  the source of truth. Undo-at-close that re-saves must update the same hand id.

## Verification (action-tested)

1. Record 3 hands in a session → force-quit the app → relaunch → the session + 3 hands are still there
   (inspect `aeches-store.json`, or a temporary History debug print).
2. Re-close a hand after an Undo → the stored hand is **updated, not duplicated** (count stays 3).
3. Create a second session → both persist; `allHands()` returns 4 newest-first.

**Done when:** hands persist across relaunch, saving is debounced + atomic, and re-saving a hand
replaces by id. No `@State`-local hand storage remains as the source of truth.

## Risks / notes

- Keep recording behavior identical — this phase changes *where* the hand goes at close, not how it's
  built (Phase 1) or recorded.
- Debounce must still flush on background/terminate (`scenePhase`) so the last hand isn't lost.
