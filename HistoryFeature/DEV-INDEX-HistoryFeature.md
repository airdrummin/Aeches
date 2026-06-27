# History, Persistence & Replay — Build Index

The authoritative progress tracker for the History tab and the data layer it depends on.
Each phase has its own spec file and is independently shippable and testable. Update the
**Status** column as work lands. Keep this file current — it's the single source of truth for
where we are.

> Read [README.md](../README.md) first. This feature retires two of its "Known Limitations":
> *card entry is lossy on save* and *two position-label paths diverge*.

---

## Locked decisions (from review)

| Decision | Choice | Why |
|---|---|---|
| Local store tech | **Codable → JSON behind a `HandStore` protocol** | Keeps the pure-struct models; JSON is inspectable/resettable while testing; cloud sync later is a new protocol conformer, not a rewrite. |
| Card fidelity | **Fully lossless** — the `CardGroup` becomes the canonical, `Codable` card model | "All details entered must be retrievable." Footnote/relationship/board data is *dropped* today; that ends. |
| Replay style | **Step through streets (tap to advance)** | Deterministic, reuses the per-street renderer, minimal motion work. |
| Edit model | **Rehydrate the saved `Hand` back into `HandEntryView`** | One recording engine, reused for new + edited hands (DRY). Requires lossless persistence (above). |

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
  ├─ HandEntryView   (record new + EDIT existing)            ◀── Phase 6
  ├─ HistoryTab list (every hand, newest first)              ◀── Phase 4
  └─ ReplayView      (read-only, step-through)               ◀── Phase 5
```

The DRY core is Phase 3: the table and transcript stop being welded to live `@State` and become
pure functions of a `Hand`, so recording, History rows, and Replay all render through the same code.

---

## Phases

| # | Phase | Status | Depends on | Spec |
|---|---|---|---|---|
| 1 | Lossless `Hand` (canonical card model) | ⬜ Not started | — | [DEV-PHASE1-HistoryFeature.md](DEV-PHASE1-HistoryFeature.md) |
| 2 | Store + persistence (`SessionStore` / `HandStore`) | ⬜ Not started | 1 | [DEV-PHASE2-HistoryFeature.md](DEV-PHASE2-HistoryFeature.md) |
| 3 | Pure renderers (seat deriver + transcript builder) | ⬜ Not started | 1 | [DEV-PHASE3-HistoryFeature.md](DEV-PHASE3-HistoryFeature.md) |
| 4 | History list UI | ⬜ Not started | 2, 3 | [DEV-PHASE4-HistoryFeature.md](DEV-PHASE4-HistoryFeature.md) |
| 5 | Replay (read-only, step-through) | ⬜ Not started | 3, 4 | [DEV-PHASE5-HistoryFeature.md](DEV-PHASE5-HistoryFeature.md) |
| 6 | Edit (rehydrate + write-back) | ⬜ Not started | 2, 5 | [DEV-PHASE6-HistoryFeature.md](DEV-PHASE6-HistoryFeature.md) |

**Status legend:** ⬜ Not started · 🟡 In progress · 🔵 In review/testing · ✅ Done

### Suggested order
1 → 2 → 3 → 4 → 5 → 6. Phases 2 and 3 both depend only on 1 and can be done in either order
(or in parallel). Everything visual (4–6) waits on the renderers (3) and the store (2).

---

## Cross-cutting principles

- **One source of truth.** A `Hand` fully describes itself — no consumer reads live `@State` to
  render a saved hand. The store holds the hands; views observe the store.
- **DRY.** The same `Hand` is recorded, listed, replayed, and edited. The same renderers draw the
  live table and the replay table. No second implementation of seat visuals or transcript grammar.
- **Lossless round-trip.** `decode(encode(hand))` re-renders byte-for-byte identical transcript +
  visuals. This is the acceptance bar for Phase 1 and is re-checked by every later phase.
- **Protocol seam for cloud.** Nothing above `HandStore` knows it's a file. The cloud swap is one
  new type.
- **Throwaway dev data.** Local JSON carries a `storeVersion`; on a model change during the build,
  bump it and discard the old file (no migration code while iterating).

---

## Deferred (explicitly out of scope here)

- Cloud sync (separate `HandStore` conformer, later).
- Marketplace consumption of hands, watermarking, pro commentary.
- Search/filter/sort in History beyond newest-first.
- Auto-animated replay (we chose step-through).
- Villain profiles (tracked separately in README).
