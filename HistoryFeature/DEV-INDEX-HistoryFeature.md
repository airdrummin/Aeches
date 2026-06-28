# History, Persistence & Replay — Build Index

The authoritative progress tracker for the History tab and the data layer it depends on.
Each phase has its own spec file and is independently shippable and testable. Update the
**Status** column as work lands. Keep this file current — it's the single source of truth for
where we are.

> Read [README.md](../README.md) first. This feature retires two of its "Known Limitations":
> *card entry is lossy on save* and *two position-label paths diverge*.

---

## Locked decisions (from review)

> Second review pass (2026-06-27) added/clarified the **store write path**, **card field typing**,
> **edit navigation**, and **verification** rows.
> Third pass (2026-06-27) tightened the **bound suit** to the `Suit` enum (Option B) and made
> **post-close re-sync** of board + hero + villain cards explicit (see Phase 1).

| Decision | Choice | Why |
|---|---|---|
| Local store tech | **Codable → JSON behind a `HandStore` protocol** | Keeps the pure-struct models; JSON is inspectable/resettable while testing; cloud sync later is a new protocol conformer, not a rewrite. |
| Store write path | **Per-hand granular write** (`SessionStore.saveHand`) is the primary path; whole-store save is the debounced cold flush only | Keeps the seam server-friendly — a future cloud conformer maps "save this one hand" to one document write, no consumer change. (v1 file impl still rewrites the single JSON; fine at ~8–12 hands/session.) |
| Hand identity | **`Hand.id` is the one durable key** (not `(sessionId, handNumber)`). The live hand carries a stable `currentHandID`; `saveHand` is an idempotent **upsert** by id | `handNumber` is a display ordinal (repeats across sessions, reused across re-closes); `Hand.id` is the natural one-doc-per-id key for the cloud store and Edit. One identity → close/re-close/post-close-edit/edit-write-back all collapse to one call. Undo-at-close stops `popLast`-ing — it reads the saved snapshot and leaves it persisted (undo+quit now retains the last-closed hand). See Phase 2. |
| Card fidelity | **Fully lossless** — the `CardGroup` becomes the canonical, `Codable` card model | "All details entered must be retrievable." Footnote/relationship/board data is *dropped* today; that ends. |
| Card field typing | **`rank` is the `Rank` enum; a bound suit is the `Suit` enum** (Option B). The `FrameSuit`/group suit-mode system stays for fuzziness — `.unspecified`/`.unknown`(`x`), footnote, and relationship are untouched | Neither a rank nor a *known* suit is ever fuzzy, so typing both loses nothing and kills `T`-vs-`"10"` and `"♦"`-vs-`"d"` drift in the permanent, synced format. Only `FrameSuit.known`'s payload changes (glyph `String` → `Suit`); footnote/relationship fuzziness is carried as before. No `"s"`(spades)-vs-`"s"`(suited) collision: the bound suit lives in the frame's `suit` field, the texture in the group's `relationship` field, and modes are mutually exclusive — and we persist the structured group, never a parsed notation string. |
| Replay style | **Step through *actions* (tap to advance)** — one decision at a time, board revealed per street; **preflop pure open-folds are elided** (a seat whose only preflop action is a fold gets no step), mirroring the transcript. Outcome on the felt at the final/showdown beat | Deterministic, reuses the seat deriver by feeding it an action *prefix*; minimal motion work. (Revised from the original street-granular plan during Phase 5 — street-only read like screenshots; per-action plays the hand as it happened.) |
| Edit model | **Rehydrate the saved `Hand` back into `HandEntryView`** | One recording engine, reused for new + edited hands (DRY). Requires lossless persistence (above). |
| Edit navigation | **Reuse the single recording screen — no modal.** Entering Edit auto-saves the in-progress live hand Skip-style (resumable via Undo), then loads the hand being edited | One screen; leans on the existing Skip→Undo machinery so an interrupted live hand is preserved, not lost or duplicated. |
| Hand completion | **Store `isComplete: Bool` on `Hand`** (default `true`; Skip sets `false`, every real close sets `true`). Reopening branches on it: **incomplete → resume LIVE** at the table to finish; **complete → frozen summary** to edit | `outcome == nil` is ambiguous (a finished fold-out vs a skipped hand — and a hero-fold-then-skip is indistinguishable from a real villain showdown). A stored flag is authoritative: lets skipped hands be resumed/finished (Phase 6), and makes the History "Incomplete" chip exact instead of inferred. Bool now; promote to a status enum only if a third state appears. See Phase 6. |
| Losslessness check | **Manual verification** with an "every card mode" hand — no permanent test target | Solo project, verified by hand each phase. Standard check: one hand exercising footnote + relationship + bound + board-suit-count + a villain. |

---

## Architecture at a glance

```
AechesApp
  └─ SessionStore (ObservableObject, single source of truth)   ◀── Phase 2
       └─ HandStore (protocol)  ──► FileHandStore (JSON today, Cloud later)
            persists [Session] → [Hand]                          ◀── Phase 1 (lossless Hand)

Pure renderers (functions of a Hand, no live @State)            ◀── Phase 3
  ├─ seatStates(streetActions, foldedBefore, highlighted?)  → table visuals
  └─ transcript(for: Hand)                                  → shorthand text

Consumers
  ├─ HandEntryView   (record new + EDIT existing + RESUME skipped)  ◀── Phase 6
  ├─ HistoryTab list (every hand, newest first)              ◀── Phase 4
  │     └─ session-grouped (headers → hands; resume a session) ◀── Phase 7
  └─ ReplayView      (read-only, step-through)               ◀── Phase 5
```

The DRY core is Phase 3: the table and transcript stop being welded to live `@State` and become
pure functions of a `Hand`, so recording, History rows, and Replay all render through the same code.

---

## Phases

| # | Phase | Status | Depends on | Spec |
|---|---|---|---|---|
| 1 | Lossless `Hand` (canonical card model) | ✅ Done | — | [DEV-PHASE1-HistoryFeature.md](DEV-PHASE1-HistoryFeature.md) |
| 2 | Store + persistence (`SessionStore` / `HandStore`) | ✅ Done | 1 | [DEV-PHASE2-HistoryFeature.md](DEV-PHASE2-HistoryFeature.md) |
| 3 | Pure renderers (seat deriver + transcript builder) | ✅ Done | 1 | [DEV-PHASE3-HistoryFeature.md](DEV-PHASE3-HistoryFeature.md) |
| 4 | History list UI | ✅ Done | 2, 3 | [DEV-PHASE4-HistoryFeature.md](DEV-PHASE4-HistoryFeature.md) |
| 5 | Replay (read-only, step-through) | ✅ Done | 3, 4 | [DEV-PHASE5-HistoryFeature.md](DEV-PHASE5-HistoryFeature.md) |
| 6 | Edit (rehydrate + write-back) + resume skipped hands | ⬜ Not started | 2, 5 | [DEV-PHASE6-HistoryFeature.md](DEV-PHASE6-HistoryFeature.md) |
| 7 | Session-grouped History (+ resume a session) | ⬜ Not started | 4, 6, session/auth flow | [DEV-PHASE7-HistoryFeature.md](DEV-PHASE7-HistoryFeature.md) |

**Status legend:** ⬜ Not started · 🟡 In progress · 🔵 In review/testing · ✅ Done

### Suggested order
1 → 2 → 3 → 4 → 5 → 6 → 7. Phases 2 and 3 both depend only on 1 and can be done in either order
(or in parallel). Everything visual (4–6) waits on the renderers (3) and the store (2). Phase 7 is
deferred to pair with the real session/auth flow (History grouping only pays off with multiple
sessions; today the app boots into one dev session).

---

## Cross-cutting principles

- **One source of truth.** A `Hand` fully describes itself — no consumer reads live `@State` to
  render a saved hand. The store holds the hands; views observe the store.
- **DRY.** The same `Hand` is recorded, listed, replayed, and edited. The same renderers draw the
  live table and the replay table. No second implementation of seat visuals or transcript grammar.
- **Lossless round-trip.** `decode(encode(hand))` re-renders byte-for-byte identical transcript +
  visuals. This is the acceptance bar for Phase 1 and is re-checked by every later phase. **Verified
  manually** (no test target) using the "every card mode" hand above.
- **Protocol seam for cloud.** Nothing above `HandStore` knows it's a file. The cloud swap is one
  new type, reached through the per-hand write path (see the Store-write-path locked decision).
- **README invariant updated (intentional).** Phase 2 introduces an app-wide `SessionStore`
  (`ObservableObject` + `@EnvironmentObject`), reversing the README's Technical-Constraints rule
  ("no observable context layer"). That rule predates persistence and can't hold once History reads
  the same hands — update the README when Phase 2 lands.
- **Throwaway dev data.** Local JSON carries a `storeVersion`; on a model change during the build,
  bump it and discard the old file (no migration code while iterating).

---

## Deferred (explicitly out of scope here)

- Cloud sync (separate `HandStore` conformer, later).
- Marketplace consumption of hands, watermarking, pro commentary.
- Search/filter/sort in History beyond newest-first and session grouping. (Session **grouping** itself is now **Phase 7**, not deferred.)
- Auto-animated replay (we chose step-through).
- Villain profiles (tracked separately in README).
