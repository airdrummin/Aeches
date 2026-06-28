# Phase 7 — Session-grouped History (accordion; delete, rename, resume)

**Status:** ⬜ Not started · **Depends on:** Phase 4 (History list), Phase 6 (edit/resume nav + write-back)

## Goal

Turn History from a flat all-hands list into a **session-grouped accordion**: each **session** is an
expandable header; its **hands** sit underneath in session order. Sessions and hands are manageable in
place — a hand can be **deleted / edited / resumed**; a session can be **deleted** or have its
**details renamed/edited**. Hand numbers become meaningful *within* a session.

A throwaway **day-based dev session** scaffold provides real headers to build/test against now; it's
removed when the real session creation/selection (auth) flow lands.

## Why

Hand numbers are per-session ordinals — "Hand #3" only means something inside a session. Players think
in sessions ("Borgata," "Wynn 5/10"). The Phase 4 flat list was right for one dev session; grouping is
needed once there are several. Edit/Resume (Phase 6) already exist per hand; this phase adds the
organization plus the missing management verbs (delete a hand, delete/rename a session).

## Locked decisions (from review)

| Decision | Choice |
|---|---|
| Grouping UI | **Accordion** — `DisclosureGroup` per session on one History screen (tap a header to expand/collapse its hands in place); not a drill-down screen. |
| Per-hand actions | **Delete** (new) + Edit / Resume (Phase 6). |
| Per-session actions | **Delete** the whole session, and **Rename / edit details** (reuse the New Session screen as an edit form). |
| Delete behavior | **Confirmation dialog**; **no renumber** — deleting Hand #3 leaves #1, #2, #4 (the number is the recorded ordinal; gaps are fine). Deleting a session removes all its hands. |
| Dev organization | **Day-based session** — header = today's date; a new calendar day starts a new session. Today's session is auto-resumed on launch; hands continue **per-session numbering** (next = max in session + 1, not a reset to 1). DEBUG-only scaffold, removed with the real session flow. |
| Deferred to the auth/session flow | Real session **creation/selection** UI, and resuming an *arbitrary past* session to add hands. |

## Design

### Grouped accordion list
- History top level = **sessions, newest-first** (`Session.date`/`startedAt`). The store already holds
  `[Session]` each owning `[Hand]` — the data is already grouped, no model change.
- Each session is a `DisclosureGroup`:
  - **Header:** name, type (Cash/Tournament), date, hand count (later: net result/duration).
  - **Body:** that session's hands in **session order (by `handNumber`)**, each the Phase 4 `HistoryRow`,
    tapping into `HandDetailView` (which already resolves live by id).
- Empty state unchanged (invite to record).

### Delete (hand + session)
- **Hand:** swipe-to-delete on a `HistoryRow` (and/or a Delete in `HandDetailView`) → confirm → remove
  by id. No renumber.
- **Session:** swipe / context menu on the header → confirm ("Delete session and its N hands?") → remove
  the session and all its hands.
- Store gains `deleteHand(_ id:in:)` and `deleteSession(_ id:)`.
- Guard the active/today's session: deleting the session you're recording into resets the recorder to a
  fresh session (recreate today's, or land on New Session).

### Rename / edit session details
- An **Edit session** affordance on the header (menu) → opens the **New Session screen in edit mode**
  (pre-filled with the session's fields) → saves via `upsertSession` (same id), so the header updates and
  hands stay attached.
- `NewSessionView` gains an optional "existing session to edit" input (pre-fill + Save vs. Create).

### Per-session hand numbering (+ dev day-session)
- `handNumber` seeds from the session on entry/resume: `nextHandNumber(in:) = (max handNumber in the
  session) + 1` (brand-new session → 1). New Hand uses the same, so numbering is per-session and
  continues across relaunch.
- **Dev scaffold (`RecordTab`, DEBUG):** resolve the active session as **today's** session — find a
  session whose `date` is today (calendar day), else create one named with today's date — and seed
  `handNumber` from it. Replaces the current fixed-UUID "Dev Session." Manual **Back → New Session** still
  creates extra sessions (extra groups) for testing.

## Changes — file by file (anticipated)

- **`History/HistoryListView.swift`** — flat list → `DisclosureGroup`-per-session accordion; swipe-delete
  on rows; session header with delete + edit-session menu. Reuse `HistoryRow`/`ResultChip`.
- **`NewSessionView.swift`** — optional edit mode (pre-fill an existing `Session`, Save by id).
- **`SessionStore.swift`** — `deleteHand(_:in:)`, `deleteSession(_:)`, `nextHandNumber(in:)`; (rename is
  the existing `upsertSession`).
- **`ContentView.swift` / `RecordTab`** — DEBUG day-based session resolution; seed `handNumber` from the
  resolved session; route an edit-session request (reuse the Phase 6 store-signal pattern).
- **`HandEntryView.swift`** — seed `handNumber` per-session (next = max+1) instead of the fixed `1`; New
  Hand uses it; `confirmationDialog`s for deletes if surfaced here.

## Verification (action-tested)

1. Hands recorded today group under today's date header; a second session (Back → New Session) is its own
   header; expanding/collapsing works; hand numbers are per-session.
2. Delete a hand → confirm → it's gone, others keep their numbers (gap, no renumber), History count drops.
3. Delete a session → confirm → the session and all its hands are gone.
4. Edit session details → the header updates; its hands stay attached (same session id).
5. Reopen the app same day → today's session resumes; the next hand continues its number (no reset to 1).

**Done when:** History is a session-grouped accordion with per-session numbering, hands can be
deleted/edited/resumed, and sessions can be deleted and renamed.

## Risks / notes

- **Dev scaffold is throwaway.** The day-based session is a stand-in; the real session creation/selection
  (auth) flow replaces it. Keep it DEBUG-gated.
- **Deleting the active session** mid-record needs a graceful reset (recreate today's / go to New Session).
- **No renumber on delete** keeps `Hand.id` the durable key (Phase 2) — numbers are display ordinals and
  may have gaps.
- **`NewSessionView` edit mode** must save by the existing session id (upsert), never create a duplicate.
- Reuse the Phase 4–6 row/chip/detail components — this phase changes *organization + management*, not
  per-hand rendering.
