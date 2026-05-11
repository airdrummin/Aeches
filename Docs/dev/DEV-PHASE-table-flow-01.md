# DEV — Phase 01: Street State Engine

## Purpose

Establish the internal state machine that tracks the current street, active seat sequence, open-bet detection, and per-street action recording. This is the data backbone every other phase depends on. No UI is added in this phase beyond what is required to wire and verify the state — the Action Controller and auto-highlight visuals are Phase 02 and 03 respectively.

---

## Entry Criteria

- DEV-INDEX-table-flow.md has been read.
- `docs/Aeches_PokerTableFlow.md` has been read in full.
- All files in the Code Familiarity Checklist below have been read using the Read tool.
- No prior phase work is in progress.

---

## Scope

### Included

- Add `currentStreet: StreetName` `@State` to `HandEntryView`
- Add `streets: [Street]` `@State` to accumulate completed streets on the current hand
- Add `actionsThisStreet: [Action]` `@State` — ordered action list for the street in progress
- Add `betLevelThisStreet: Int` `@State` — count of raises/bets on the current street (0 = no open bet)
- Add `activeSeatSequence: [Int]` `@State` — ordered clockwise list of seats still active (not folded) this hand
- Add `foldedSeats: Set<Int>` `@State` — seats that have folded this hand (used for skip logic and display)
- Add `highlightedSeat: Int?` `@State` — the seat currently awaiting action (drives `activeSeat` on `TableOvalView`)
- Replace the existing `seatActions: [Int: SeatState]` dictionary with a computed property or keep it as the display cache derived from `actionsThisStreet` — the source of truth must be `actionsThisStreet`, not the dictionary
- Add `streetIsClosed: Bool` computed property — preflop and post-flop close conditions per spec Section 5.4 and 6
- Add `openBetExists: Bool` computed property — true when `betLevelThisStreet > 0` on the current street
- Wire `highlightedSeat` into the existing `activeSeat` parameter of `TableOvalView`
- Update `handleSeatTap()` in the `.recordingHand` phase to record an `Action` into `actionsThisStreet` (instead of mutating `seatActions` directly), then derive `seatActions` from `actionsThisStreet` for display
- Implement `closeStreet()` — appends a completed `Street` to `streets`, resets `actionsThisStreet`, resets `betLevelThisStreet`, resets `seatActions` display cache, advances `currentStreet`
- Implement `positionFor(seat:) -> String` helper that calls `calculatePositions()` from `Models.swift` using the current hand's `buttonSeat` and `activeSeatSequence`

### Excluded

- Auto-fold logic (Phase 03)
- Auto-highlight movement between seats (Phase 03)
- Action Controller bar UI (Phase 02)
- Raise arrow count rendering changes (Phase 04)
- Showdown and fold-out detection (Phase 05)
- Villain profiles (out of scope entirely)
- Any changes to `NewSessionView.swift`, `ContentView.swift`, `LoginView.swift`, or `Models.swift`

---

## Code Familiarity Checklist

Before writing any code, confirm you have read and understood:

- [ ] `/Aeches/HandEntryView.swift` — full file, all state vars, `handleSeatTap()`, `resetHand()`, `saveHand()`, `Phase` enum, card strip, save bar
- [ ] `/Aeches/SeatSelectionView.swift` — `TableOvalView` signature and parameters, `SeatState` struct, `SeatButtonView`, `seatPosition()` function
- [ ] `/Aeches/Models.swift` — `ActionType`, `StreetName`, `Action`, `Street`, `Hand`, `Session`, `calculatePositions()`, `positionLabels()`
- [ ] `/Aeches/ContentView.swift` — `RecordTab` and how `HandEntryView` is instantiated; confirm `session` is passed by value

---

## Implementation Steps

1. **Read all checklist files** using the Read tool. Do not proceed until complete.

2. **Extend the `Phase` enum** in `HandEntryView` with a `.showdown` case and a `.handClosed` case. Do not remove existing cases. Audit every `switch phase` in the file and add `case .showdown, .handClosed:` stubs where needed to maintain exhaustive coverage.

3. **Add new `@State` properties** to `HandEntryView`:
   ```swift
   @State private var currentStreet: StreetName = .preflop
   @State private var streets: [Street] = []
   @State private var actionsThisStreet: [Action] = []
   @State private var betLevelThisStreet: Int = 0
   @State private var activeSeatSequence: [Int] = []
   @State private var foldedSeats: Set<Int> = []
   @State private var highlightedSeat: Int? = nil
   ```

4. **Add computed properties**:
   - `openBetExists: Bool` — returns `betLevelThisStreet > 0`
   - `seatActionsFromStreet: [Int: SeatState]` — derived from `actionsThisStreet`, mapping each `seatIndex` to its most recent `SeatState`. This replaces `seatActions` as the display source. Keep the `seatActions` `@State` var for now (it still drives `TableOvalView`) but populate it from this derivation whenever `actionsThisStreet` changes.
   - `positionFor(seat: Int) -> String` — calls `calculatePositions(buttonSeatIndex:activeSeatIndices:)` with the current `buttonSeat` (unwrap safely, return `"?"` if nil) and `activeSeatSequence`; returns the label for the given seat index, or `"?"` if not found.

5. **Update `handleSeatTap()` in the `.recordingHand` case**:
   - When a seat is tapped, determine the appropriate `ActionType` for that seat given current context:
     - If `openBetExists`: cycle through `.call → .raise → .fold → (clear)`
     - If `!openBetExists` and it's post-flop: cycle through `.check → .open → (clear)`
     - Preflop with no open bet is a special case: UTG always faces a forced BB bet, so preflop always uses `fold/call/raise` cycling — `openBetExists` is treated as `true` for preflop only
   - Build an `Action` struct: `Action(seatIndex: seat, position: positionFor(seat:seat), actionType: resolvedType, sizing: nil)`
   - Append to `actionsThisStreet`
   - Update `betLevelThisStreet` if the action is `.open` or `.raise`: `betLevelThisStreet += 1`
   - If action is `.fold`: insert `seat` into `foldedSeats`; remove from `activeSeatSequence`
   - Sync `seatActions` dictionary from `actionsThisStreet` using `seatActionsFromStreet`

6. **Implement `closeStreet()`**:
   ```swift
   private func closeStreet() {
       let completed = Street(name: currentStreet, boardCards: [], actions: actionsThisStreet)
       streets.append(completed)
       actionsThisStreet = []
       betLevelThisStreet = 0
       seatActions = [:]  // display cache reset
       if let next = currentStreet.next() {
           currentStreet = next
       }
   }
   ```
   - Add a `next() -> StreetName?` extension on `StreetName`:
     ```swift
     extension StreetName {
         func next() -> StreetName? {
             switch self {
             case .preflop: return .flop
             case .flop:    return .turn
             case .turn:    return .river
             case .river:   return nil
             }
         }
     }
   ```

7. **Update `resetHand()`** to clear all new state vars:
   ```swift
   currentStreet = .preflop
   streets = []
   actionsThisStreet = []
   betLevelThisStreet = 0
   activeSeatSequence = []
   foldedSeats = []
   highlightedSeat = nil
   ```

8. **Update `saveHand()`** to build and store the `Hand` model before resetting. For now, append it to a local `@State private var savedHands: [Hand] = []` array (backend sync is future scope). Construct:
   ```swift
   Hand(
       sessionId: session.id,
       handNumber: handNumber,
       heroSeatIndex: heroSeat ?? 0,
       buttonSeatIndex: buttonSeat ?? 0,
       activeSeatIndices: activeSeatSequence,
       holeCards: /* map heroCards CardSlots to Card models */,
       streets: streets,
       outcome: nil,
       potSize: nil,
       potUnit: session.potUnit,
       effectiveStack: nil,
       commentary: nil
   )
   ```
   - The `CardSlot → Card` mapping: if `slot.rank != nil`, create `Card(rank: Rank(rawValue: slot.rank!)!, suit: slot.suit.flatMap { Suit(rawValue: suitKey($0)) })`. Add a private `suitKey(_ symbol: String) -> String` helper that maps `"♠" → "s"`, `"♥" → "h"`, `"♦" → "d"`, `"♣" → "c"`.

9. **Wire `highlightedSeat` to `TableOvalView`** — replace the hardcoded `activeSeat: nil` in `HandEntryView.body` with `activeSeat: highlightedSeat`.

10. **Initialize `activeSeatSequence`** when dealer button is confirmed (in the `.placingButton → .recordingHand` transition in `handleSeatTap()`). Set it to all seat indices 0..<tableSize in clockwise order starting from the button, then assign `highlightedSeat` to the UTG seat (3rd seat clockwise from button in a full ring; use `calculatePositions()` to find the seat labeled `"UTG"`).

---

## UI Verification Checklist

After implementation, manually verify in the Xcode simulator:

- [ ] Tapping a seat in `.recordingHand` phase records an `Action` and updates the seat visual
- [ ] The `seatActions` display dictionary correctly reflects `actionsThisStreet`
- [ ] `openBetExists` is `false` at street start and `true` after a `.open` or `.raise` action
- [ ] `foldedSeats` contains the correct seat index after a fold tap
- [ ] `activeSeatSequence` loses the folded seat after folding
- [ ] `closeStreet()` appends to `streets` and resets the working state
- [ ] `resetHand()` zeroes all new state — re-entering recording is clean
- [ ] `highlightedSeat` is wired and the correct seat shows the pulsing ring visual on the table

---

## Stop / Go Criteria

**Stop and report if:**
- `calculatePositions()` returns unexpected labels for the configured `tableSize` and `buttonSeat`
- The `StreetName.next()` extension conflicts with any existing extension on `StreetName` in the codebase
- Any `switch phase` site produces a compiler warning about non-exhaustive cases after enum expansion

**Proceed if:**
- All state vars compile cleanly
- `seatActions` display dictionary stays in sync after tap interactions in simulator

---

## Rollback Plan

All changes are additive. New `@State` vars and computed properties do not break existing functionality. If the phase produces a regression in the card picker or seat selection flow, remove the new state properties and revert `handleSeatTap()` to its prior implementation. The `StreetName` extension can be removed without side effects.

---

## Exit Criteria

- All new `@State` vars are declared and initialize correctly
- `handleSeatTap()` in `.recordingHand` builds an `Action` and updates `actionsThisStreet`
- `closeStreet()` is implemented and callable
- `resetHand()` clears all new state
- `highlightedSeat` drives `activeSeat` on `TableOvalView`
- No compiler errors or warnings introduced
- Existing card picker and seat selection flows are unaffected
