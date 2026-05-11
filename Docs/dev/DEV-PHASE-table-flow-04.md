# DEV — Phase 04: Bet Level & Raise Arrows

## Purpose

Implement the raise arrow visual system. Seat buttons showing a raise action must display the correct number of up-arrows reflecting the bet level at the time that seat raised. This is a display enhancement on top of the `betLevelThisStreet` tracking established in Phase 01 and the `SeatState` system in `SeatSelectionView.swift`.

---

## Entry Criteria

- Phase 03 is marked Complete in DEV-INDEX-table-flow.md.
- `betLevelThisStreet` is accurately tracking bet count in `HandEntryView`.
- `actionsThisStreet` records `.open` and `.raise` actions for all aggressive seats.
- All files in the Code Familiarity Checklist below have been read using the Read tool.

---

## Scope

### Included

- Extend `SeatState` to carry a `betLevel: Int` field — the bet level at the moment this seat raised (1 = open/2-bet, 2 = 3-bet, 3 = 4-bet, 4+ = 5-bet)
- Update `applyAction()` in `HandEntryView` to snapshot `betLevelThisStreet` into the new `SeatState.betLevel` when the action type is `.open` or `.raise`
- Update `SeatButtonView` label logic to render the correct arrow string from `betLevel`:
  - `betLevel == 1` → `↑↑` (two arrows — first raise / open / 2-bet)
  - `betLevel == 2` → `↑↑↑` (three arrows — 3-bet)
  - `betLevel == 3` → `↑↑↑↑` (four arrows — 4-bet)
  - `betLevel >= 4` → bold single `↑` (5-bet or higher — simplified for space per spec)
- Arrow color for raise/open states: gold (`Color.gold`)
- Update `syncSeatActions()` in `HandEntryView` to preserve `betLevel` when rebuilding the `seatActions` display cache — the last raise action for a seat includes its bet level at record time
- Ensure `undoLastAction()` correctly recomputes the `betLevel` in the remaining `seatActions` after popping a raise — if the last raiser is undone, the seat before it becomes the new aggressor with the correct prior bet level

### Excluded

- Sizing entry (e.g. "14BB", "2.5x") — `RaiseSizing` remains `nil` on all actions
- Changes to the card strip or card picker
- Villain profiles (out of scope)
- Any changes to `NewSessionView.swift`, `ContentView.swift`, or `Models.swift`

---

## Code Familiarity Checklist

Before writing any code, confirm you have read and understood:

- [ ] `/Aeches/SeatSelectionView.swift` — `SeatState` struct (current fields: `action: Action?`, `sizeLabel: String?`); `SeatButtonView` label computation (`private var label: String`); `SeatButtonView` body
- [ ] `/Aeches/HandEntryView.swift` — full file post-Phase 03; `applyAction()`, `syncSeatActions()`, `undoLastAction()`, `betLevelThisStreet`
- [ ] `docs/Aeches_PokerTableFlow.md` — Section 4 (Raise Arrow Visual System) in full

---

## Implementation Steps

1. **Read all checklist files** using the Read tool.

2. **Extend `SeatState`** in `SeatSelectionView.swift`:
   ```swift
   struct SeatState {
       enum Action { case fold, call, check, open, raise }
       var action: Action?
       var betLevel: Int = 0   // only meaningful when action is .open or .raise
   }
   ```
   - Remove `sizeLabel: String?` — it is superseded by `betLevel`. Audit all sites that reference `sizeLabel` (there should be one: `SeatButtonView.label`) and replace.

3. **Update `SeatButtonView.label`** computed property:
   ```swift
   private var label: String {
       switch state?.action {
       case .fold:   return "✕"
       case .call:   return "✓"
       case .check:  return "—"
       case .open, .raise:
           let level = state?.betLevel ?? 1
           switch level {
           case 1:  return "↑↑"
           case 2:  return "↑↑↑"
           case 3:  return "↑↑↑↑"
           default: return "↑"   // 5-bet+ simplified
           }
       case nil:     return "\(index + 1)"
       }
   }
   ```

4. **Update `applyAction()` in `HandEntryView`** — when building the `SeatState` for a raise or open action, include the current `betLevelThisStreet` value at the time of the action:
   - The bet level increments after the action is recorded, so snapshot `betLevelThisStreet + 1` (the level this raise creates, not the prior level) as the seat's `betLevel`.
   - Concretely: `betLevelThisStreet += 1` first, then `SeatState(action: .raise, betLevel: betLevelThisStreet)`.

5. **Update `syncSeatActions()`** to preserve `betLevel` when rebuilding from `actionsThisStreet`:
   ```swift
   private func syncSeatActions() {
       var result: [Int: SeatState] = [:]
       for action in actionsThisStreet {
           let seatAction: SeatState.Action
           switch action.actionType {
           case .fold:            seatAction = .fold
           case .call:            seatAction = .call
           case .check:           seatAction = .check
           case .open:            seatAction = .open
           case .raise:           seatAction = .raise
           }
           // Compute bet level: count .open + .raise actions up to and including this one
           let levelAtThisPoint = actionsThisStreet
               .prefix(while: { $0.id != action.id })
               .filter { $0.actionType == .open || $0.actionType == .raise }
               .count + (action.actionType == .open || action.actionType == .raise ? 1 : 0)
           result[action.seatIndex] = SeatState(action: seatAction, betLevel: levelAtThisPoint)
       }
       seatActions = result
   }
   ```
   Note: the above logic uses `prefix(while:)` which requires `actionsThisStreet` actions to have stable, unique IDs. Since `Action` uses `UUID`, this is safe.

6. **Verify `undoLastAction()`** still correctly recomputes `betLevelThisStreet` after popping. The existing implementation in Phase 02 already recomputes it from scratch:
   ```swift
   betLevelThisStreet = actionsThisStreet.filter { $0.actionType == .open || $0.actionType == .raise }.count
   ```
   After the pop, call `syncSeatActions()` to rebuild the display cache with correct `betLevel` values per seat.

7. **Verify the `SeatState` change does not break `SeatSelectionView`** — the `SeatSelectionView` preview passes `seatStates: [:]`, so it is unaffected. The `TableOvalView` used in `HandEntryView` also passes `seatStates: seatActions` which now contains `SeatState` values with `betLevel`. Confirm no crash.

---

## UI Verification Checklist

- [ ] A seat that opens the betting (first raise) shows `↑↑` in gold
- [ ] A seat that 3-bets shows `↑↑↑`
- [ ] A seat that 4-bets shows `↑↑↑↑`
- [ ] Undoing a raise removes the arrows and restores the previous aggressor's arrow count correctly
- [ ] A seat with only a call shows `✓` in green
- [ ] A seat that checked shows `—`
- [ ] Arrow display is consistent across preflop and post-flop streets

---

## Stop / Go Criteria

**Stop and report if:**
- Removing `sizeLabel` breaks any external reference outside `SeatSelectionView.swift` and `HandEntryView.swift`
- `syncSeatActions()` with `prefix(while:)` produces incorrect bet levels for a sequence of raise/re-raise/re-raise

**Proceed if:**
- A simulated sequence of open → 3-bet → 4-bet produces `↑↑`, `↑↑↑`, `↑↑↑↑` on the correct seats
- Undo of the 4-bet reverts the seat to neutral and the 3-bet seat retains `↑↑↑`

---

## Rollback Plan

The only behavioral change is adding `betLevel: Int` to `SeatState` and updating the `label` computed property. Removing `betLevel` and reverting `SeatButtonView.label` to its prior implementation restores Phase 03 behavior. `sizeLabel` removal is safe since no other code referenced it for real output.

---

## Exit Criteria

- `SeatState` has `betLevel: Int` field
- `sizeLabel` is removed from `SeatState`
- `SeatButtonView.label` uses `betLevel` to render correct arrow strings
- `applyAction()` snapshots the correct `betLevel` at raise time
- `syncSeatActions()` rebuilds per-seat `betLevel` correctly
- `undoLastAction()` recomputes `betLevelThisStreet` and calls `syncSeatActions()`
- No compiler errors or warnings
- All prior phase flows (card picker, controller bar, auto-fold) remain unaffected
