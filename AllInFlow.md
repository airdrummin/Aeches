# All-In Flow Reference

Authoritative spec for how all-in players are recorded and how the hand proceeds around
them. Implemented in `HandEntryView.swift` (logic) and `SeatSelectionView.swift` (badge).

---

## The model in one sentence

An **all-in** is any action carrying the `All-in` size marker; once a seat is all-in it
is skipped from all further betting, and the hand keeps having betting rounds only while
**≥2 players still have chips** — otherwise the board runs out to showdown.

There is **no chip/stack math** — the app can't know who covers whom. The user supplies
that information by marking each all-in (including a *call* that puts a player all-in),
and a simple count does the rest.

---

## What counts as all-in

A seat is all-in iff any of its actions this hand has `sizing?.label == "All-in"`:

- **Aggressive all-in** — Bet/Raise sized `All-in` (hold the Raise/Bet button → tap the
  `All-in` chip). Transcript: `jam`.
- **Passive all-in** — a **call** that committed the player's last chips (hold the **Call**
  button → tap the single `All-in` chip). Transcript: `call (all-in)`.

`allInSeats` is **derived** from the log (no stored flag) so it tracks Undo automatically
and persists across streets.

## The core sets

| Set | Definition | Used for |
|---|---|---|
| `activeSeatSequence` | not folded | fold-out (`== 1`), showdown eligibility |
| `playersWithChips` | not folded AND not all-in | `owesAction`, `streetIsClosed`, the ring |

## The governing rule (after each betting round)

```
inHand  = activeSeatSequence.count           // not folded
chips   = playersWithChips.count             // not folded, not all-in

inHand == 1                 → fold-out (existing logic)
chips  >= 2                 → next street has betting; all-in seats are skipped
chips  <= 1 (and inHand>=2) → RUN-OUT: deal the board with no betting → showdown
```

`isRunOut` is gated on the current betting being **settled** — if the lone chip-holder
still owes a response to an all-in just made (`facesUnansweredBet`), it is not yet a
run-out and they keep their action buttons until they respond.

---

## Worked scenarios

**Heads-up jam.** `UTG bet. BTN jam. UTG call.` → after the call, `chips = {UTG} = 1` →
run-out → turn/river dealt board-only → showdown UTG vs BTN. (Marking UTG's call all-in
is optional here — it changes the transcript, never the flow.)

**3-way, calls ARE all-in.** `CO bet. BTN jam. UTG call (all-in). CO call (all-in).` →
`chips = 0` → run-out → 3-way showdown.

**3-way, calls keep chips.** `BTN jam. UTG call. CO call.` → `chips = {UTG, CO} = 2` →
the turn/river are played between UTG & CO (side pot); BTN is skipped but still live for
showdown.

**All-in raise implies a cover.** `BTN jam. UTG raise (all-in).` — UTG can only *raise*
all-in by putting in more than BTN, so UTG covers BTN. The app doesn't compute this (UTG
is all-in either way); the notation just records it.

---

## UI

### Seat badge (`SeatSelectionView.swift`)
An all-in seat renders **amber** (border `#E8943C`, symbol `#F5C277`, bg `#2E1F08…`) with
a persistent amber **`ALL IN`** pill on the bottom rim. The pill replaces the generic
size pill (the size *is* "All-in"). It carries the symbol of how the seat got all-in
(`→` jam-bet, `↑↑` jam-raise, `✓` call-all-in) every street, even when the seat has no
action on the current street.

### Marking a call all-in (`ControlBar`)
Reuses the hold-to-size paradigm. When facing a wager the **Call** button is holdable:
quick-tap = normal call; **hold 0.3s** = goes solid green ("selected") and a single
`All-in` chip appears in the utility row → tap it to record `call (all-in)`. A limp
(no open bet) uses the plain Call button (a limp can't be all-in). Built on a shared
`holdableChip` (Raise/Bet/Call), each showing "selected" only when
`sizingSelectedType == its own action`.

### Run-out mode
When `isRunOut` the hand is decided — there are no more decisions, only the board to deal.
So we do **not** walk street-by-street:
- The **Fold/Call/Raise row is hidden** (nothing to decide).
- The seat ring/pulse is dropped (`activeSeat = nil`).
- The felt reads **`ALL IN`**.
- The Next Street button is relabeled **`Showdown`** and pulses. Tapping it **jumps straight
  to the Win / Lose / Chop overlay** in one move (`advanceStreetOrShowdown` fast-forwards the
  remaining streets internally so the transcript renders the full board, then sets
  `phase = .showdown`). It is the same showdown the river normally reaches.
- The **run-out board is entered in the always-live card strip** — before or after picking
  the result. `openCardEntry` is not phase-gated, so board cards can be added even after the
  hand closes; the transcript (which renders streets up to `currentStreet`, now `.river`)
  shows them whenever they're entered.

### Frozen table at a run-out close
The run-out walk closes every remaining street, which empties `actionsThisStreet` (its actions
move into `streets`). The seat visuals (`seatActions`) normally render only the live street, so
at a closed run-out a **non-all-in caller** (a seat that called but kept chips) would render
actionless — its action is now buried in `streets`. To keep the frozen table reading the
finished hand correctly, `seatActions` falls back to the **last street that had action** when
`actionsThisStreet` is empty *and the hand is closed* (`phase == .showdown || .handClosed`).
This mirrors the transcript, which already reads `streets`, so the two renderers always agree.
The fallback is gated on the terminal phase on purpose: an empty live street is also the normal
state right after a street advances, and there it must stay empty (a fresh street). All-in seats
are unaffected — their amber badge is derived from the whole-hand log regardless of street.

---

## Code touch-points

| Concern | Where |
|---|---|
| `allInSeats`, `playersWithChips`, `isRunOut`, `facesUnansweredBet` | derived vars after `recomputeDerivedState` |
| Acting set | `owesAction`, `streetIsClosed`, `nextActiveSeat`, `nextOwingSeat`, `firstActorAfterClose` use `playersWithChips` |
| All-in can't be acted on | `handlePreflopTap`, `handlePostflopTap`, `routeDecisive`, `autoResolveSkipped` guard `allInSeats` |
| Run-out highlight | `closeStreet` sets `highlightedSeat = isRunOut ? nil : firstActorAfterClose()` |
| Frozen-table actions at close | `seatActions` `displayStreetActions` — falls back to the last non-empty street when `actionsThisStreet` is empty and the hand is closed (so a non-all-in caller still shows) |
| Badge | `seatActions` sets `SeatState.isAllIn` + a persistent badge for seats with no action this street |
| Call-all-in input | `handleCallHold`, `sizingChips` (`["All-in"]` for `.call`), `sizingSelectedType`, `callChip` |
| Transcript | `actionToken` → `call (all-in)` |
| No `Models.swift` change | all-in reuses the existing `Action.sizing` field |

---

## Out of scope (future)

- **Side-pot amounts / who-wins-what** — we record the line, not the chips.
- **Multiple distinct all-in tiers** shown as separate pots.
- **Auto-suggesting** all-in (e.g. inferring a call is all-in from a prior shove).
