# DEV — Phase 02: Action Controller Bar

## Purpose

Replace the static "Save Hand / Clear Hand" save bar with the spec-compliant **Action Controller** — a persistent bottom bar containing a Back arrow, context-aware action buttons, and a Forward arrow (preflop only). Both input paths (direct seat tap and Action Controller) must operate on the same state and stay visually in sync at all times.

---

## Entry Criteria

- Phase 01 is marked Complete in DEV-INDEX-table-flow.md.
- All Phase 01 state vars (`currentStreet`, `actionsThisStreet`, `betLevelThisStreet`, `highlightedSeat`, `openBetExists`, `foldedSeats`, `activeSeatSequence`) are present and functioning.
- All files in the Code Familiarity Checklist below have been read using the Read tool.

---

## Scope

### Included

- Extract a new `ActionControllerBar` `View` struct (private, defined at the bottom of `HandEntryView.swift`) that renders the bar and fires callbacks
- `ActionControllerBar` accepts:
  - `currentStreet: StreetName`
  - `openBetExists: Bool`
  - `highlightedSeat: Int?`
  - `canUndo: Bool` — true when `actionsThisStreet` is non-empty
  - `onAction: (ActionType) -> Void`
  - `onForward: () -> Void` (preflop only)
  - `onBack: () -> Void`
- Action button sets per spec Section 5.6 and 6.5:
  - **Preflop:** `[ Fold ] [ Call ] [ Raise ]` + Forward `→` arrow
  - **Post-flop, no open bet:** `[ Check ] [ Bet ]` — no Forward arrow
  - **Post-flop, bet open:** `[ Fold ] [ Call ] [ Raise ]` — no Forward arrow
  - **`.showdown` or `.handClosed` phase:** replace buttons with `[ New Hand → ]` CTA
- Back `←` arrow is always present when `canUndo` is true; dimmed (non-interactive) when false
- Replace the `saveBar` in `HandEntryView.body` with `ActionControllerBar` when phase is `.recordingHand`, `.showdown`, or `.handClosed`; show the original "Save / Clear" bar only during `.selectSeat` and `.placingButton` (or remove it entirely — see spec, the save bar is not spec-compliant; prefer replacing it fully)
- Implement `applyAction(_ type: ActionType)` in `HandEntryView` — the single handler for both direct seat tap and Action Controller button tap. Both call this function. It:
  - Applies the action to `highlightedSeat` (requires a seat to be highlighted)
  - Builds and appends an `Action` to `actionsThisStreet`
  - Updates `betLevelThisStreet`, `foldedSeats`, `activeSeatSequence` as established in Phase 01
  - Updates `seatActions` display cache
  - Calls `advanceHighlight()` (Phase 03 stub — leave as a no-op `private func advanceHighlight() {}` placeholder)
  - Calls `checkStreetClose()` — detect if the street is now closed and call `closeStreet()` if so
- Implement `undoLastAction()`:
  - Pops the last item from `actionsThisStreet`
  - Recomputes `betLevelThisStreet` from scratch (count `.open` and `.raise` actions remaining)
  - Recomputes `foldedSeats` and `activeSeatSequence` from scratch based on remaining actions
  - Resyncs `seatActions` display cache
  - Restores `highlightedSeat` to the seat of the popped action
- Implement `checkStreetClose()` — a pure logic function with no side effects other than calling `closeStreet()`:
  - Preflop close: the last aggressor's seat has had all other active players respond (call or fold) after the raise; or if no raise, action has returned to BB
  - Post-flop close: all active (not-folded) seats have acted on the current street and no outstanding bet faces any of them
  - If river is complete and `activeSeatSequence.count >= 2`: set `phase = .showdown` instead of closing to next street
  - If river is complete and `activeSeatSequence.count == 1`: that case is handled by fold-out detection in Phase 05 — leave a `// TODO: Phase 05 fold-out` comment

### Excluded

- Auto-highlight movement (Phase 03 — `advanceHighlight()` is a stub here)
- Auto-fold logic (Phase 03)
- Raise arrow count changes (Phase 04)
- Showdown UI beyond setting `phase = .showdown` (Phase 05)
- Forward arrow auto-fold behavior (Phase 03)
- Villain profiles (out of scope)

---

## Code Familiarity Checklist

Before writing any code, confirm you have read and understood:

- [ ] `/Aeches/HandEntryView.swift` — full file post-Phase 01; all new state vars; existing `saveBar`; existing `handleSeatTap()`; the `Phase` enum with `.showdown` and `.handClosed` cases added in Phase 01
- [ ] `/Aeches/SeatSelectionView.swift` — `SeatState.Action` enum values (fold/call/check/open/raise); `SeatButtonView` label logic
- [ ] `/Aeches/Models.swift` — `ActionType` enum cases; `Action` struct fields
- [ ] `docs/Aeches_PokerTableFlow.md` — Section 3.2 (Action Controller), 5.6 (Preflop controller), 6.5 (Post-flop controller), 7.3 (New Hand CTA)

---

## Implementation Steps

1. **Read all checklist files** using the Read tool.

2. **Add `applyAction(_ type: ActionType)` to `HandEntryView`**. This function becomes the single source of truth for action recording. Guard: if `highlightedSeat == nil` and the action type requires a seat (fold/call/raise/check/bet), return early. Steps inside:
   - Map `ActionType` to `SeatState.Action` for display: `.fold→.fold`, `.call→.call`, `.check→.check`, `.open→.open`, `.raise→.raise`
   - Build `Action(seatIndex: highlightedSeat!, position: positionFor(seat: highlightedSeat!), actionType: type, sizing: nil)`
   - Append to `actionsThisStreet`
   - If `.open` or `.raise`: `betLevelThisStreet += 1`
   - If `.fold`: `foldedSeats.insert(highlightedSeat!)`, remove from `activeSeatSequence`
   - Sync `seatActions` from `actionsThisStreet`
   - Call `advanceHighlight()` (stub)
   - Call `checkStreetClose()`

3. **Update `handleSeatTap()` in `.recordingHand`** to delegate to `applyAction()` rather than mutating state directly. The cycling logic (tap 1 = call, tap 2 = raise, tap 3 = fold) still resolves the `ActionType` before calling `applyAction()`. If the tapped seat already has an action, the tap cycles it — remove the existing action from `actionsThisStreet` for that seat first, then reappend the new one. Recompute `betLevelThisStreet` from scratch after any mutation.

4. **Implement `undoLastAction()`**:
   ```swift
   private func undoLastAction() {
       guard let last = actionsThisStreet.last else { return }
       actionsThisStreet.removeLast()
       highlightedSeat = last.seatIndex
       // Recompute derived state from scratch
       betLevelThisStreet = actionsThisStreet.filter { $0.actionType == .open || $0.actionType == .raise }.count
       foldedSeats = Set(actionsThisStreet.filter { $0.actionType == .fold }.map { $0.seatIndex })
       activeSeatSequence = activeSeatSequence  // rebuild from session's full seat list minus foldedSeats
       // Resync display
       syncSeatActions()
   }
   ```
   - Extract a `syncSeatActions()` private function that rebuilds `seatActions` from `actionsThisStreet` (the last action per seat index wins).

5. **Implement `checkStreetClose()`** with the following logic:
   - Build `activePlayers` = `activeSeatSequence` (not folded)
   - **Preflop:** Find the last `.raise` or `.open` action. If none exists, street closes when BB has acted (the BB seat index is the 3rd clockwise from button in a full ring — use `calculatePositions()` to find it). If a raise exists, street closes when every other active player after that raise index has a `.call` or `.fold` action that came after the raise.
   - **Post-flop:** Street closes when every active player has exactly one action on this street and no player faces an unresolved bet (i.e., `betLevelThisStreet` is settled — all active players have acted since the last `.open`/`.raise`).
   - If closed and `currentStreet == .river` and `activePlayers.count >= 2`: `phase = .showdown`
   - If closed and `currentStreet != .river`: call `closeStreet()`
   - Add `// TODO: Phase 05 fold-out` comment for the `activePlayers.count == 1` detection path

6. **Define `ActionControllerBar`** as a private struct at the bottom of `HandEntryView.swift`:
   - Use an `HStack` with the Back arrow on the left, action buttons centered, and the Forward arrow on the right (preflop only).
   - Back arrow: `Image(systemName: "arrow.uturn.backward")`, gold when `canUndo`, muted gray and disabled when not.
   - Forward arrow: `Image(systemName: "arrow.right.circle.fill")`, gold. Only shown when `currentStreet == .preflop`.
   - Action buttons: use the design system (gold for Raise/Bet, white label for Fold/Call/Check, `Color.surface2` backgrounds, rounded rectangle shape, `Color.gold` border on Raise).
   - When `phase == .showdown` or `.handClosed`: show a single full-width `New Hand →` button in gold. Tapping it calls `onForward`.
   - Height: ~80pt including safe area bottom padding.
   - Background: `Color.surface` with a top divider `Color.borderDark`.

7. **Replace `saveBar` in `HandEntryView.body`**:
   - Remove the `if phase == .recordingHand { saveBar }` block.
   - Add `ActionControllerBar(...)` as a pinned bottom view. It should always sit just above the tab bar. Use `.safeAreaInset(edge: .bottom)` or a `VStack` with `Spacer()` to position it.
   - Wire `onAction` to `applyAction(_:)`
   - Wire `onBack` to `undoLastAction()`
   - Wire `onForward` to a `advanceToNextSeat()` stub (returns early — Phase 03 implements it)
   - Wire `canUndo` to `!actionsThisStreet.isEmpty`

8. **Add `advanceToNextSeat()` stub**:
   ```swift
   private func advanceToNextSeat() {
       // Phase 03: advance highlight clockwise, auto-folding skipped seats
   }
   ```

9. **Update `saveHand()`** — the "Save Hand" concept now lives inside the New Hand CTA flow. For now, keep `saveHand()` callable but have `ActionControllerBar`'s New Hand button call `startNewHand()` instead. Implement `startNewHand()`:
   ```swift
   private func startNewHand() {
       handNumber += 1
       resetHand()
       // Dealer button suggestion: advance buttonSeat one clockwise (Phase 03 will refine this)
   }
   ```

---

## UI Verification Checklist

- [ ] Action Controller bar is visible in `.recordingHand` phase and sits just above the tab bar
- [ ] Preflop shows `[ Fold ] [ Call ] [ Raise ]` with a `→` forward arrow
- [ ] Tapping `[ Call ]` when a seat is highlighted applies a call action to that seat
- [ ] Tapping `[ Raise ]` applies a raise to the highlighted seat and increments `betLevelThisStreet`
- [ ] Back arrow is gold when actions exist; tapping it removes the last action and re-highlights that seat
- [ ] Back arrow is dimmed and non-interactive with no actions recorded
- [ ] Post-flop (manually advance `currentStreet` to `.flop` in a preview) shows `[ Check ] [ Bet ]` with no forward arrow
- [ ] Post-flop with `betLevelThisStreet > 0` shows `[ Fold ] [ Call ] [ Raise ]`
- [ ] `checkStreetClose()` fires after each action; street does not close prematurely
- [ ] `New Hand →` button appears when phase is `.showdown`

---

## Stop / Go Criteria

**Stop and report if:**
- `checkStreetClose()` logic triggers street close incorrectly in a test scenario (e.g., closes preflop after UTG raises before others act)
- The `ActionControllerBar` layout conflicts with the tab bar safe area on any iPhone size
- Removing `saveBar` causes any layout shift in the card strip or table zones

**Proceed if:**
- Tapping action buttons applies actions and updates seat visuals correctly
- Undo correctly rolls back state and re-highlights the undone seat

---

## Rollback Plan

`ActionControllerBar` is an additive new struct. If it causes layout issues, remove it from `HandEntryView.body` and restore the `saveBar` reference. The `applyAction()`, `undoLastAction()`, and `checkStreetClose()` functions are additive to `HandEntryView` and can be removed independently without breaking the Phase 01 state vars.

---

## Exit Criteria

- `ActionControllerBar` renders correctly in `.recordingHand` phase
- Action buttons and Back arrow fire the correct callbacks
- `applyAction()` is the single recording path for both direct tap and controller input
- `undoLastAction()` correctly restores state
- `checkStreetClose()` correctly detects preflop and post-flop street end conditions
- `advanceHighlight()` and `advanceToNextSeat()` stubs are in place
- No compiler errors or warnings
- Card picker and seat selection flows are unaffected
