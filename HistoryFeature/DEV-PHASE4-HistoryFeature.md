# Phase 4 — History list UI

**Status:** ⬜ Not started · **Depends on:** Phase 2 (store), Phase 3 (transcript builder)

## Goal

Replace the placeholder `HistoryTab` with a real list of **every hand recorded**, newest first, each
row readable at a glance and tappable into a detail screen.

## Why

`HistoryTab` is a stub — `Text("History")` on the background (`ContentView` :83). The store (Phase 2)
now has the data; the transcript builder (Phase 3) makes a snippet cheap.

## Design

### Data
- `@EnvironmentObject var store: SessionStore`.
- `store.allHands()` → flattened across sessions, newest-first (sort by `timestamp`, then handNumber).
- Empty state when there are none (invite to record, not an apology).

### Row (reuse the design tokens + transcript builder)
Each row shows:
- **Hand #** and **session name** (e.g. "Hand #3 · Dev Session").
- **Hero position + hole** (e.g. "UTG · A♣J♦") — from the hand's `holeGroup` notation.
- **Outcome chip** — win (green) / lose (red) / chop (gold) / incomplete (muted "—"), from `outcome`.
- **One-line transcript snippet** — first line of `transcript(for: hand)` in Courier (the existing
  shorthand look).
- Optional: `effectiveStack` as `Nbb` and a relative date.

Dense bordered rows (per CDS restraint), not heavy cards. Tap → `HandDetailView(hand:)`.

### Detail screen (`HandDetailView`)
The hub the two actions launch from:
- Header: hand #, session, position, hole, outcome, eff stack.
- Full **transcript** (reuse the existing transcript panel / `transcript(for:)`).
- Two buttons: **Replay** → `ReplayView(hand:)` (Phase 5) · **Edit** → recorder in edit mode (Phase 6).
  Until those land, the buttons can be present-but-stubbed so the nav is in place.

## Changes — file by file

- **`ContentView.swift`** — `HistoryTab` becomes a real `NavigationStack` + list bound to the store.
- **New `History/HistoryListView.swift`** — the list + row view.
- **New `History/HandDetailView.swift`** — the per-hand hub (Replay/Edit entry points).
- Reuse `Color` tokens and the transcript renderer; no new design language.

## Verification (action-tested)

1. Record several hands across two sessions → all appear in History, newest first, with correct
   position/hole/outcome/snippet.
2. Incomplete (skipped) hands show the muted "—" outcome.
3. Empty state shows when the store is empty.
4. Tap a row → detail screen with the full transcript; Replay/Edit buttons present.

**Done when:** every recorded hand is listed and readable, and tapping opens a detail hub. No live
`@State` is read — the list is purely store-driven.

## Risks / notes

- Keep the row cheap — render the snippet from the first transcript line, don't build the whole panel
  per row.
- "Every hand" = flat list (per your ask). Session grouping/filtering is deferred (see INDEX).
