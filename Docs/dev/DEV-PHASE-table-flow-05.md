# DEV — Phase 05: Hand Close — Fold-Out & Showdown

## Purpose

Implement the two hand close conditions: fold-out (one player remains after a fold) and showdown (river action closes with 2+ players). This phase completes the full hand lifecycle — including the showdown winner selection UI, villain hole card entry unlock, and the correct transition to the `New Hand →` CTA state.

---

## Entry Criteria

- Phase 04 is marked Complete in DEV-INDEX-table-flow.md.
- `phase` enum includes `.showdown` and `.handClosed` cases (added in Phase 01).
- `checkStreetClose()` already sets `phase = .showdown` when river closes with 2+ active players.
- The `// TODO: Phase 05 fold-out` comment is present in `checkStreetClose()`.
- `ActionControllerBar` renders a `New Hand →` button when phase is `.showdown` or `.handClosed`.
- All files in the Code Familiarity Checklist below have been read using the Read tool.

---

## Scope

### Included

**Fold-Out Detection:**
- In `applyAction()`, after applying a fold, check if `activeSeatSequence.count == 1`. If so, call `triggerFoldOut()`
- `triggerFoldOut()`:
  - Saves the current hand to `savedHands` (same logic as prior `saveHand()`)
  - Sets `phase = .handClosed`
  - Sets `highlightedSeat = nil`
  - Does NOT unlock villain hole card entry — villain cards are locked when folded out (spec Section 7.1)

**Showdown UI:**
- When `phase == .showdown`, display a `ShowdownOverlay` view centered on the felt inside `TableOvalView`'s parent. This is a simple overlay — not a sheet.
- `ShowdownOverlay` contains:
  - Text `"SHOWDOWN"` in Georgia, gold, large
  - Three buttons: `Win` (green), `Lose` (red), `Chop` (muted gold)
  - Tapping any button calls `resolveShowdown(outcome: Outcome)`
- `resolveShowdown(outcome:)`:
  - Sets `Hand.outcome` on the in-progress hand
  - Sets `phase = .handClosed`
  - Unlocks villain hole card entry: sets a new `@State private var villainCardEntryEnabled: Bool = true`
  - Saves the hand (same save logic)

**Villain Hole Cards at Showdown (entry unlock only — no full villain profile UI):**
- When `villainCardEntryEnabled == true` and `phase == .handClosed`: tapping a non-hero seat that was active at showdown opens the card picker for that seat's hole cards
- Store villain showdown cards in `@State private var villainShowdownCards: [Int: [CardSlot]] = [:]` keyed by seat index
- Use the existing `cardPickerPanel` — pass a `activeVillainSlot: VillainSlotID?` similar to `activeSlot`; when a villain seat is tapped in `.handClosed` phase with `villainCardEntryEnabled`, open the picker for that seat
- Add `VillainSlotID: Equatable` enum: `case villain(seatIndex: Int, cardIndex: Int)`
- The card picker reuse: either generalize `activeSlot` to handle villain slots, or add a parallel `activeVillainSlot` state and a parallel `villainCardPickerPanel` view that uses the same visual structure. **Prefer reuse if it can be done without major restructuring; otherwise use a parallel panel.**

**Hand Save:**
- Consolidate all save paths into a single `saveCurrentHand(outcome: Outcome?)` function used by both `triggerFoldOut()` and `resolveShowdown()`.
- Maps `heroCards`, `flopCards`, `turnCard`, `riverCard` slots to `[Card]` using the `CardSlot → Card` helper.
- Appends the resulting `Hand` to `savedHands`.

**Status Line Update:**
- `.handClosed` phase: status text = `"Hand saved · Tap New Hand to continue"`
- `.showdown` phase: status text = `"Showdown — select a winner"`

### Excluded

- Full villain profile sheet (long-press behavior, tags, notes) — out of scope for this entire project
- Pot size entry, effective stack entry — not in scope for this phase
- Commentary field — not in scope for this phase
- Tournament placement recording — not in scope for this phase
- Any changes to `NewSessionView.swift`, `ContentView.swift`, or `Models.swift`

---

## Code Familiarity Checklist

Before writing any code, confirm you have read and understood:

- [ ] `/Aeches/HandEntryView.swift` — full file post-Phase 04; `Phase` enum; `applyAction()`; `checkStreetClose()` (find the `// TODO: Phase 05` comment); `triggerFoldOut()` (does not exist yet — will be created); `savedHands`; card picker infrastructure (`activeSlot`, `SlotID`, `cardPickerPanel`, `commitCard()`, `setSlot()`)
- [ ] `/Aeches/SeatSelectionView.swift` — `SeatButtonView` to understand tappability in `.handClosed` phase
- [ ] `/Aeches/Models.swift` — `Outcome` enum; `Hand` struct fields; `Card` struct
- [ ] `docs/Aeches_PokerTableFlow.md` — Section 7 (Hand Close Logic) in full: 7.1 (fold-out), 7.2 (showdown), 7.3 (new hand flow), 8.3 (villain hole cards at showdown only)

---

## Implementation Steps

1. **Read all checklist files** using the Read tool.

2. **Add new `@State` properties** to `HandEntryView`:
   ```swift
   @State private var villainCardEntryEnabled: Bool = false
   @State private var villainShowdownCards: [Int: [CardSlot]] = [:]
   @State private var activeVillainSeat: Int? = nil          // seat picker open for
   @State private var activeVillainCardIndex: Int = 0        // 0 or 1 (two hole cards)
   @State private var villainPickingRank: String? = nil
   ```

3. **Implement `saveCurrentHand(outcome: Outcome?)`**:
   - Build `holeCards: [Card]` from `heroCards` — filter non-empty slots, map `CardSlot → Card`.
   - Build `streets: [Street]` — append `actionsThisStreet` as a final incomplete street if non-empty.
   - Construct and append a `Hand` to `savedHands`.

4. **Implement `triggerFoldOut()`**:
   ```swift
   private func triggerFoldOut() {
       saveCurrentHand(outcome: nil)
       villainCardEntryEnabled = false
       phase = .handClosed
       highlightedSeat = nil
   }
   ```
   - Add a call to `triggerFoldOut()` inside `applyAction()` immediately after a fold is applied and `activeSeatSequence.count == 1`. Place this before `checkStreetClose()`.

5. **Remove the `// TODO: Phase 05 fold-out` comment** from `checkStreetClose()` and replace with the actual fold-out guard: if `activeSeatSequence.count <= 1`, return early (fold-out has already been or will be handled by `applyAction()`).

6. **Implement `resolveShowdown(outcome: Outcome)`**:
   ```swift
   private func resolveShowdown(outcome: Outcome) {
       saveCurrentHand(outcome: outcome)
       villainCardEntryEnabled = true
       phase = .handClosed
       highlightedSeat = nil
   }
   ```

7. **Build `ShowdownOverlay`** as a private struct at the bottom of `HandEntryView.swift`:
   - Floating centered over the table area. Use `.overlay` on the `TableOvalView` container.
   - Semi-transparent dark background (not full-screen modal) — `Color.black.opacity(0.65)` fill over the felt area only.
   - `"SHOWDOWN"` in `Font.custom("Georgia", size: 22)`, gold, tracked.
   - Three buttons in an `HStack`: `Win` (winGreen fill), `Lose` (foldRed fill), `Chop` (surface2 fill, gold border). Each fires `resolveShowdown(outcome:)`.
   - Animate in with `.transition(.opacity.combined(with: .scale(scale: 0.92)))`.
   - Only visible when `phase == .showdown`.

8. **Wire showdown overlay** into `HandEntryView.body` — add it as an `.overlay` on the `TableOvalView`:
   ```swift
   TableOvalView(...)
       .overlay {
           if phase == .showdown {
               ShowdownOverlay(onResolve: resolveShowdown)
                   .transition(...)
           }
       }
       .animation(.easeInOut(duration: 0.25), value: phase == .showdown)
   ```

9. **Villain hole card tap in `.handClosed` phase**:
   - Update `handleSeatTap()`: add a new case for `phase == .handClosed`:
     ```swift
     case .handClosed:
         guard villainCardEntryEnabled else { return }
         guard seat != heroSeat else { return }
         // Only allow seats that were active at showdown
         guard activeSeatSequence.contains(seat) || foldedSeats.contains(seat) == false else { return }
         activeVillainSeat = seat
         activeVillainCardIndex = 0
         villainPickingRank = nil
     ```
   - Show the card picker (reuse `cardPickerPanel` by extending `activeSlot` or add a parallel panel). The simpler path: add `@State private var activeVillainSlot: SlotID? = nil` where `SlotID` gets two new cases — but `SlotID` already handles hero cards at indices 0–1. Instead, add two `CardSlot` entries per villain in `villainShowdownCards[seat]` and map them to `.hero(0)` and `.hero(1)` equivalent using a wrapper. **Cleanest approach:** extract the card picker panel into a standalone function `cardPickerPanel(for slot: SlotID, rank: Binding<String?>, onCommit: (String, String?) -> Void, onClear: () -> Void, onDone: () -> Void)` and call it with both hero and villain slots.

10. **Update status line** for new phases:
    ```swift
    case .showdown:    return "Showdown — select a winner"
    case .handClosed:  return "Hand saved · Tap New Hand to continue"
    ```

11. **Confirm `ActionControllerBar` `New Hand →` button** calls `startNewHand()`, which already exists from Phase 02/03. Verify that `startNewHand()` resets `villainCardEntryEnabled = false` and `villainShowdownCards = [:]` inside `resetHand()`.

12. **Update `resetHand()`** to clear villain showdown state:
    ```swift
    villainCardEntryEnabled = false
    villainShowdownCards = [:]
    activeVillainSeat = nil
    villainPickingRank = nil
    ```

---

## UI Verification Checklist

- [ ] With only 1 active player remaining after a fold, phase transitions to `.handClosed` automatically
- [ ] In `.handClosed` fold-out state: seat visuals remain, card strip remains, `New Hand →` button shows
- [ ] River closes with 2 active players → `SHOWDOWN` overlay appears on felt with Win/Lose/Chop buttons
- [ ] Tapping `Win` saves the hand with `outcome: .win` and transitions to `.handClosed`
- [ ] Tapping `Lose` saves with `outcome: .lose`; `Chop` saves with `outcome: .chop`
- [ ] After showdown resolution, tapping a villain seat opens the card picker for that seat
- [ ] Hero seat tap in `.handClosed` does nothing
- [ ] Card picker for villain seat entries saves to `villainShowdownCards`
- [ ] `New Hand →` clears villain showdown cards and resets to dealer placement
- [ ] Fold-out: villain seat card picker is NOT accessible (locked)
- [ ] `savedHands` array grows by 1 after each completed hand (fold-out or showdown)

---

## Stop / Go Criteria

**Stop and report if:**
- `checkStreetClose()` triggers `.showdown` before the river street is actually closed
- The showdown overlay appears on top of the card picker overlay, causing a z-order conflict
- `villainCardEntryEnabled` is somehow true after a fold-out

**Proceed if:**
- Fold-out and showdown transitions fire correctly in simulator
- Card picker opens correctly for villain seats after showdown

---

## Rollback Plan

`ShowdownOverlay` is an additive struct. Remove the `.overlay` from `TableOvalView` to hide it. `triggerFoldOut()` and `resolveShowdown()` are additive functions; removing them restores Phase 04 behavior (phase never reaches `.handClosed`). Villain card state vars are additive and can be removed cleanly.

---

## Exit Criteria

- Fold-out detection fires when `activeSeatSequence.count == 1` after a fold
- `triggerFoldOut()` saves the hand and sets `phase = .handClosed`
- `ShowdownOverlay` renders correctly when `phase == .showdown`
- `resolveShowdown()` sets outcome, saves hand, enables villain card entry, transitions to `.handClosed`
- Villain seat tap in `.handClosed` + `villainCardEntryEnabled` opens card picker
- `resetHand()` clears all villain showdown state
- `savedHands` is correctly populated after each hand
- Status line shows correct text for `.showdown` and `.handClosed` phases
- No compiler errors or warnings
- All prior phase flows remain unaffected
