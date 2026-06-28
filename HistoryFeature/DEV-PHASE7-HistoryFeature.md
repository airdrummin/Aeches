# Phase 7 — Session-grouped History (+ resume a session)

**Status:** ⬜ Not started · **Depends on:** Phase 4 (History list), Phase 6 (edit/resume nav), and the
real session/selection flow (today the app boots straight into one dev session).

## Goal

Restructure History from a flat, all-hands list into a **two-level, session-grouped** view: each
**session** is a header (e.g. "Borgata"), with its **hands nested underneath** in session order (Hand
#1, #2, …). Tapping a session opens it; the user can also **reopen a past session and add hands to it**,
so hand numbers carry real per-session meaning.

## Why

Hand numbers are *per-session* ordinals — "Hand #3" only means something inside a session. The Phase 4
list is deliberately a flat, newest-first stream across all sessions (right for a single dev session,
wrong once a user runs multiple sessions named "Borgata," "Wynn 5/10," etc.). Players think in
sessions; History should mirror that. This phase also closes the loop on resuming a session to keep
recording into it.

> **Why it waits for the real session flow:** today `RecordTab` auto-loads one fixed dev session and
> drops straight into recording (DEBUG). Grouping only pays off once the app supports creating/selecting
> multiple sessions — which arrives with auth/session management. So Phase 7 pairs with that work.

## Design (sketch — firm up at build time)

### Grouped list
- History top level = **sessions, newest-first** (by `Session.startedAt`/`date`). The store already
  holds `[Session]` each owning its `[Hand]`, so the data is already grouped — no model change.
- **Session header row:** name, type (Cash/Tournament), date, hand count (later: net result, duration,
  stakes/buy-in). Tap → the session's hands.
- **Session detail:** the session's hands in **session order (by `handNumber`)**, each row the same
  `HistoryRow` from Phase 4 (reused), tapping into the Phase 4/5/6 `HandDetailView` hub.
- The flat `allHands()` stays for any "recent across everything" use, but the primary History UI becomes
  grouped.

### Resume a session (add hands to a past session)
- From a session header (or its detail), a **"Resume session"** action makes that session the active
  recording session and returns to the Record tab — new hands **append** to it, continuing its
  `handNumber` sequence (next = max existing + 1).
- Leans on the Phase 6 Edit nav (set the active session via the store + switch to Record), and on the
  per-hand `saveHand(_, in: sessionId)` write path (Phase 2) so appended hands land in the right session.
- Hand numbering on resume: the recorder seeds `handNumber` from the session's existing hands rather
  than from 1.

### Session creation / selection
- The flat-to-grouped shift assumes a **session list + "New Session"** entry point (the New Session
  screen already exists). The full create/select/resume surface is part of the session/auth flow this
  phase pairs with.

## Changes — file by file (anticipated)

- **`History/HistoryListView.swift`** — becomes session-grouped (sections or a sessions list → session
  detail). Reuse `HistoryRow`/`ResultChip`.
- **New `History/SessionDetailView.swift`** (likely) — one session's hands + "Resume session".
- **`ContentView.swift` / `RecordTab`** — resolve the active session from a selected/resumed session
  (not just the dev default); seed `handNumber` from the session on resume.
- **`SessionStore.swift`** — helpers for grouped access / resume target if needed (`hands(in:)`,
  `nextHandNumber(in:)`); sessions are already the grouping key.

## Verification (action-tested)

1. Two sessions with hands → History shows two session headers; each opens to its own hands in
   session order; hand numbers are per-session.
2. Resume a past session → record a hand → it appends to that session with the next sequential
   `handNumber`; History reflects it under that session.
3. A new session's hands group separately; nothing leaks across sessions.

**Done when:** History is grouped by session with per-session hand numbering, and a past session can be
reopened to add hands.

## Risks / notes

- **Pairs with auth/session management.** Grouping is cosmetic until multiple real sessions exist;
  sequence with that work rather than ahead of it.
- **Hand-number continuity on resume** is the subtle bit — seed from the session, not a reset to 1, and
  keep `Hand.id` the durable key (Phase 2) so resumed/edited hands never collide.
- Keep the row/chip/detail components from Phases 4–6 — this phase changes *organization*, not the
  per-hand rendering.
- Search/filter/sort beyond session grouping stays out of scope (see Index "Deferred").
