# DEV — Phase 03: Auto-Highlight & Auto-Fold

## Purpose

Implement the automatic seat highlighting system and the auto-fold logic that makes fast hand recording possible. After this phase, the table automatically highlights the correct next seat after each action, and skipped seats are automatically folded. Both the Forward arrow and direct seat tap trigger auto-fold for skipped seats.

---

## Entry Criteria

- Phase 02 is marked Complete in DEV-INDEX-table-flow.md.
- `advanceHighlight()` and `advanceToNextSeat()` are present as stubs in `HandEntryView`.
- All files in the Code Familiarity Checklist below have been read using the Read tool.

---

## Scope

### Included

- Implement `advanceHighlight()` — called after every `applyAction()`. Moves `highlightedSeat` to the next active (not-folded) seat in clockwise position order
- Implement `advanceToNextSeat()` — called by the Forward arrow. Advances to the next seat and **auto-folds all seats between the current `highlightedSeat` and the new target** in position order
- Implement `autoFoldSeats(between start: Int, and end: Int)` — takes two seat indices and folds all active seats clockwise between them (exclusive of start and end). Calls `applyAction(.fold)` for each, using the correct seat index
- Implement dealer button auto-advance on New Hand: when `startNewHand()` is called, suggest the next clockwise seat from the previous `buttonSeat` as the new dealer. Set `buttonSeat` to `nil` and `highlightedSeat` to the suggested next seat so the user taps to confirm
- Implement `activeSeatSequence` initialization on dealer button confirmation — set it to all seat indices 0..<tableSize in clockwise order derived from `buttonSeat`
- Post-flop first-to-act: when `closeStreet()` transitions to a new street, set `highlightedSeat` to the first active seat clockwise from `buttonSeat` (the small blind position if active, otherwise next)
- UTG auto-highlight after dealer button confirmed: find the seat labeled `"UTG"` from `calculatePositions()` and set `highlightedSeat`
- Add pulsing animation to the highlighted seat in `SeatButtonView` — a repeating scale or glow animation when `isActive == true`. Use `withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true))` on a glow shadow or ring opacity. Keep it subtle.
- Direct seat tap auto-fold: when the user directly taps a seat in `.recordingHand` that is not the `highlightedSeat`, all active seats between `highlightedSeat` and the tapped seat (clockwise, exclusive) are auto-folded before the tapped seat's action is applied

### Excluded

- Raise arrow count rendering (Phase 04)
- Showdown seat re-highlighting (Phase 05)
- Villain profiles (out of scope)
- Check-then-bet re-highlight is partially addressed here (the seat that checked will re-enter `advanceHighlight()` when a bet is opened) — ensure the logic handles it but do not build separate showdown UI

---

## Code Familiarity Checklist

Before writing any code, confirm you have read and understood:

- [ ] `/Aeches/HandEntryView.swift` — full file post-Phase 02; `applyAction()`, `advanceHighlight()` stub, `advanceToNextSeat()` stub, `activeSeatSequence`, `foldedSeats`, `highlightedSeat`, `closeStreet()`, `startNewHand()`
- [ ] `/Aeches/SeatSelectionView.swift` — `SeatButtonView` `isActive` parameter and its current visual (shadow glow); `seatPosition()` math
- [ ] `/Aeches/Models.swift` — `calculatePositions()`, `positionLabels()`, `StreetName`
- [ ] `docs/Aeches_PokerTableFlow.md` — Section 5.2 (auto-fold rule), 5.3 (step-by-step example), 6.1 (post-flop first to act), 6.4 (auto-highlight logic post-flop), 7.3 (new hand flow)

---

## Implementation Steps

1. **Read all checklist files** using the Read tool.

2. **Define clockwise ordering helper**:
   ```swift
   private func clockwiseOrder(from startSeat: Int, seats: [Int]) -> [Int] {
       let sorted = seats.sorted()
       guard let offset = sorted.firstIndex(of: startSeat) else { return sorted }
       return Array(sorted[offset...]) + Array(sorted[..<offset])
   }
   ```
   This returns `seats` sorted clockwise starting from `startSeat` (inclusive). Use this everywhere seat ordering is needed.

3. **Implement `advanceHighlight()`** — replaces the stub:
   ```swift
   private func advanceHighlight() {
       guard let current = highlightedSeat else {
           highlightedSeat = activeSeatSequence.first
           return
       }
       let ordered = clockwiseOrder(from: current, seats: activeSeatSequence)
       // ordered[0] is current; ordered[1] is next
       if ordered.count > 1 {
           highlightedSeat = ordered[1]
       } else {
           highlightedSeat = nil
       }
   }
   ```
   Edge case: if the current `highlightedSeat` is no longer in `activeSeatSequence` (just folded), pick the next seat from the sequence using position order from `buttonSeat`.

4. **Implement `autoFoldSeats(skipping seats: [Int])`**:
   ```swift
   private func autoFoldSeats(_ seats: [Int]) {
       for seat in seats where !foldedSeats.contains(seat) {
           // Apply fold without calling advanceHighlight (bulk operation)
           let action = Action(seatIndex: seat, position: positionFor(seat: seat), actionType: .fold, sizing: nil)
           actionsThisStreet.append(action)
           foldedSeats.insert(seat)
           activeSeatSequence.removeAll { $0 == seat }
       }
       syncSeatActions()
       betLevelThisStreet = actionsThisStreet.filter { $0.actionType == .open || $0.actionType == .raise }.count
   }
   ```

5. **Implement `advanceToNextSeat()`** — replaces the stub. This is the Forward arrow handler:
   ```swift
   private func advanceToNextSeat() {
       guard let current = highlightedSeat else { return }
       let allActive = clockwiseOrder(from: current, seats: activeSeatSequence)
       guard allActive.count > 1 else { return }
       let next = allActive[1]
       // Auto-fold all seats between current and next (exclusive of both)
       let between = seatsStrictlyBetween(from: current, to: next, in: activeSeatSequence)
       autoFoldSeats(between)
       highlightedSeat = next
       checkStreetClose()
   }
   ```

6. **Implement `seatsStrictlyBetween(from:to:in:) -> [Int]`**:
   Returns all seats in clockwise order strictly between `from` and `to`, exclusive of both endpoints.
   ```swift
   private func seatsStrictlyBetween(from: Int, to: Int, in seats: [Int]) -> [Int] {
       let ordered = clockwiseOrder(from: from, seats: seats)
       guard let toIdx = ordered.firstIndex(of: to) else { return [] }
       return Array(ordered[1..<toIdx])
   }
   ```

7. **Update direct seat tap auto-fold** in `handleSeatTap()`:
   - When the user taps a seat that is not `highlightedSeat` and is an active seat, first call:
     ```swift
     let between = seatsStrictlyBetween(from: highlightedSeat ?? tappedSeat, to: tappedSeat, in: activeSeatSequence)
     autoFoldSeats(between)
     ```
   - Then set `highlightedSeat = tappedSeat` and call `applyAction()` for the tapped seat's resolved action.
   - If the tapped seat is `highlightedSeat`, proceed directly to the tap-cycle logic without auto-folding.

8. **Update dealer button confirmation** in `handleSeatTap()` (`.placingButton` phase):
   - After setting `buttonSeat = seat` and `phase = .recordingHand`:
     ```swift
     activeSeatSequence = (0..<tableSize).map { $0 }  // all seats active at hand start
     let positions = calculatePositions(buttonSeatIndex: seat, activeSeatIndices: activeSeatSequence)
     highlightedSeat = positions.first(where: { $0.value == "UTG" })?.key
                    ?? positions.first(where: { $0.value == "BB" })?.key  // fallback for short-handed
     ```

9. **Update `closeStreet()`** to set the correct post-flop `highlightedSeat` after transitioning:
   - After calling `currentStreet = next`:
     ```swift
     let positions = calculatePositions(buttonSeatIndex: buttonSeat ?? 0, activeSeatIndices: activeSeatSequence)
     let sbSeat = positions.first(where: { $0.value == "SB" })?.key
     let ordered = clockwiseOrder(from: buttonSeat ?? 0, seats: activeSeatSequence)
     // First active seat after button is SB; if folded, next one
     highlightedSeat = ordered.dropFirst().first  // first seat after BTN in active sequence
     ```

10. **Update `startNewHand()`** to advance the dealer button suggestion:
    ```swift
    private func startNewHand() {
        let prevButton = buttonSeat ?? 0
        handNumber += 1
        resetHand()
        // Suggest next clockwise seat as new dealer
        let allSeats = (0..<tableSize).map { $0 }
        let ordered = clockwiseOrder(from: prevButton, seats: allSeats)
        let suggested = ordered.count > 1 ? ordered[1] : ordered[0]
        highlightedSeat = suggested  // highlighted for dealer confirmation
        phase = .placingButton
    }
    ```

11. **Add pulsing animation to `SeatButtonView`** for `isActive` state. Inside `SeatButtonView.body`, add an `@State private var pulseScale: CGFloat = 1.0` and drive it with a `withAnimation` in `onAppear` when `isActive`:
    ```swift
    .scaleEffect(isActive ? pulseScale : 1.0)
    .onAppear {
        guard isActive else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulseScale = 1.08
        }
    }
    .onChange(of: isActive) { active in
        if active {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
            }
        } else {
            pulseScale = 1.0
        }
    }
    ```

---

## UI Verification Checklist

- [ ] After dealer button is set, UTG seat pulses on the table
- [ ] Tapping the highlighted UTG seat applies an action and the next seat auto-highlights
- [ ] Tapping a non-highlighted seat auto-folds all seats between the highlighted seat and the tapped seat
- [ ] Forward arrow taps advance to next seat and show red X folds on skipped seats
- [ ] Post-flop: first active seat left of button auto-highlights when flop begins
- [ ] After a fold action the folded seat shows red X and the next active seat highlights
- [ ] On New Hand, the next clockwise seat from the previous button is highlighted for confirmation
- [ ] Pulsing animation is visible but subtle on the highlighted seat

---

## Stop / Go Criteria

**Stop and report if:**
- `clockwiseOrder()` produces incorrect ordering for any `tableSize` and `buttonSeat` combination
- Auto-fold applies to the hero seat (hero should always remain active unless the user explicitly folds hero)
- The `activeSeatSequence` desynchronizes from `foldedSeats` after an undo operation

**Proceed if:**
- Step-by-step example from spec Section 5.3 (9-handed, Button Seat 4, UTG Seat 7) produces correct auto-folds when simulated

---

## Rollback Plan

`advanceHighlight()`, `advanceToNextSeat()`, and `autoFoldSeats()` are new private functions. Remove them and restore the stubs to roll back. The pulsing animation in `SeatButtonView` can be reverted independently by removing the `pulseScale` state and animation modifiers.

---

## Exit Criteria

- `advanceHighlight()` correctly moves `highlightedSeat` after each action
- `advanceToNextSeat()` auto-folds skipped seats when Forward arrow is tapped
- Direct seat tap auto-folds intermediate seats per spec Section 5.2
- Dealer button confirmation initializes `activeSeatSequence` and sets UTG as `highlightedSeat`
- Post-flop `closeStreet()` sets the correct first-to-act seat
- `startNewHand()` highlights the suggested next dealer seat
- Pulsing animation renders on the highlighted seat
- No compiler errors or warnings
- Card picker, seat selection, and Action Controller flows from prior phases are unaffected
