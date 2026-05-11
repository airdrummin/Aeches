# DEV — Poker Table Flow Engine (INDEX)

## Overview

This project implements the full poker hand recording engine inside `HandEntryView.swift`. The current view has the visual skeleton (table, card strip, card picker, phase enum) but is missing all game logic: street tracking, auto-highlight, auto-fold, the Action Controller bar, raise/bet level tracking, post-flop state branching, hand close detection (fold-out and showdown), and the correct New Hand reset flow.

The goal is to produce a fully functional, spec-compliant hand recording experience — both input paths (direct seat tap and Action Controller) must stay in sync, operate on the same state, and produce correctly structured `Action`, `Street`, `Hand`, and `Session` model data. Villain profiles are explicitly out of scope for this project.

---

## Global Assumptions and Constraints

- **Platform:** iOS only, SwiftUI, Swift. No UIKit.
- **Architecture:** All state stays local inside `HandEntryView` and its child components. No new `@EnvironmentObject`, `@ObservableObject`, or Context layer is introduced.
- **Data models:** `Models.swift` is complete and must not be modified. All new logic maps onto existing structs/enums.
- **Design system:** Colors, typography, and component patterns established in `ContentView.swift` and `SeatSelectionView.swift` apply throughout. No new design tokens.
- **`SeatSelectionView.swift`** is the canonical home of `TableOvalView`, `SeatButtonView`, `SeatState`, and `seatPosition()`. These are shared components — changes to them affect both seat selection and hand recording.
- **`SeatSelectionView` view itself** (the standalone screen) is unused by the active flow. Do not delete it until the Cleanup Phase; it may be preserved as a preview host.
- **Villain profiles:** Out of scope. Do not implement. Do not wire placeholder hooks for them.
- **No typing required:** Spec requires zero typing for a standard hand. All input is tap/swipe/controller.
- **Offline-first:** No networking, no persistence layer, no backend calls. In-memory only.
- **Dark mode only.** No light mode adaptations.

---

## Execution Rules

1. Phases are **strictly sequential**. Do not begin a phase until all prior phases are marked Complete.
2. Each phase executes in a single AI chat session. Do not carry work across sessions within a phase.
3. **No cleanup, deletion, comment removal, or dead-code removal is permitted in Phases 01–05.** All hygiene work is reserved for Phase 06 (Cleanup).
4. This INDEX file is **read-only during phase execution**. Status column may be updated between phases only.
5. If a phase discovers a conflict with the spec or architecture, stop and report — do not unilaterally redesign.
6. The Cleanup Phase (Phase 06) is mandatory and must execute last.

---

## Phase Index

| # | Phase Name | File | Status |
|---|-----------|------|--------|
| 01 | Street State Engine | `DEV-PHASE-table-flow-01.md` | Complete |
| 02 | Action Controller Bar | `DEV-PHASE-table-flow-02.md` | Complete |
| 03 | Auto-Highlight & Auto-Fold | `DEV-PHASE-table-flow-03.md` | Complete |
| 04 | Bet Level & Raise Arrows | `DEV-PHASE-table-flow-04.md` | Not Started |
| 05 | Hand Close — Fold-Out & Showdown | `DEV-PHASE-table-flow-05.md` | Not Started |
| 06 | Cleanup | `DEV-PHASE-table-flow-06.md` | Not Started |

---

## Known Risks and Sensitive Areas

- **`SeatSelectionView.swift` is a shared file.** `TableOvalView`, `SeatButtonView`, and `SeatState` live there. Changes to `SeatState.Action` or `SeatButtonView` visuals impact both the seat selection screen and the hand recording screen simultaneously. Review both contexts before touching these.
- **Phase ordering matters for the `SeatState` enum.** Phase 01 introduces `check` as a distinguishable action state. Phase 04 introduces dynamic arrow count rendering. Both touch `SeatButtonView`. Do not skip Phase 01 before Phase 04.
- **Auto-fold correctness is position-order dependent.** Seat indices are 0-based around the table; clockwise order derives from `activeSeatIndices` and `buttonSeatIndex`. Use the existing `calculatePositions()` logic in `Models.swift` as the source of truth for ordering — do not implement a separate ordering algorithm.
- **The `HandEntryView` `phase` enum** currently drives card strip visibility and save bar visibility. Phases 01–05 will extend this enum. Each phase must audit all existing `switch phase` sites before adding new cases.
- **Post-flop check-then-bet re-highlight** is the most complex single interaction. A player who checked must re-enter the active sequence when a later player bets. The action sequence on the current street must be a mutable, ordered list — not just a `[Int: SeatState]` dictionary.

---

## Notes for Future AI Sessions

- Read `README.md` (project root) and `docs/Aeches_PokerTableFlow.md` before executing any phase.
- Read this INDEX and the target DEV-PHASE file in full before writing any code.
- Read every file listed in the phase's **Code Familiarity Checklist** using the Read tool. Do not assume structure.
- The spec document (`Aeches_PokerTableFlow.md`) is the authoritative source for interaction behavior. If this INDEX conflicts with the spec, the spec wins — report the conflict before proceeding.
- Villain profiles are explicitly excluded from all phases. Do not implement or stub.
- `RaiseSizing` is `nil` on all `Action` records in this project. Sizing entry is a future enhancement.
