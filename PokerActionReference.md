# Texas No-Limit Hold'em — Action Flow Reference

This file is the authoritative source of truth for poker action logic in Aeches.
All street-close detection, highlight sequencing, and phase transitions must follow these rules.

---

## Positions by Table Size

Positions are assigned clockwise from the button. Active seats only — empty seats are skipped.

| Position | Role |
|----------|------|
| BTN | Dealer button. Last to act post-flop. |
| SB | Posts small blind (forced). Acts second-to-last preflop, first post-flop if active. |
| BB | Posts big blind (forced). Acts **last** preflop. Acts second post-flop if SB folded. |
| UTG | First to act preflop. |
| UTG+1 | Second to act preflop (8+ handed). |
| UTG+2 | Third to act preflop (9+ handed). |
| HJ | Hijack — two seats right of BTN. |
| CO | Cutoff — one seat right of BTN. Acts just before BTN. |

**6-max:** UTG, HJ, CO, BTN, SB, BB
**8-max:** UTG, UTG+1, HJ, CO, BTN, SB, BB (7 positions, 8th seat is unnamed between CO and BTN)
**9-max:** UTG, UTG+1, UTG+2, HJ, CO, BTN, SB, BB
**10-max:** UTG, UTG+1, UTG+2, UTG+3, HJ, CO, BTN, SB, BB

---

## Blinds Are Not Actions

SB and BB post forced bets before any action begins. **Posting a blind is not an action.**
- Blinds are not recorded in the action sequence.
- Action begins with UTG, who is the first player to voluntarily act.
- BB has a live blind — they have already put in money, but have not "acted" in the voluntary sense.

---

## Preflop Action Order

**Clockwise starting from UTG, ending at BB.**

```
UTG → UTG+1 → UTG+2 → HJ → CO → BTN → SB → BB
```

BB is always **last to act preflop**, regardless of table size.

### Unraised pot (limped pot)
- If no one raises and action reaches BB, BB has "the option" — they can check (see the flop free) or raise.
- Street closes when BB checks or after BB's raise is responded to.

### Raised pot
- If any player raises, the BB's free check is gone.
- When action returns to BB, they must fold, call, or re-raise — just like any other player.
- Street closes when **all active players** have either folded or called the highest raise, with **BB acting last**.

### Critical rule — BB must act even when BTN calls
If the action is: UTG raises → Hero calls → BTN calls → (SB folds or calls) → **BB still needs to act.**
The street is NOT closed until BB has folded, called, or raised. BTN calling does not close preflop.

---

## Post-Flop Action Order (Flop, Turn, River)

**Clockwise starting from the first active player LEFT of the button.**

This is the OPPOSITE of preflop. On every post-flop street:

```
SB (if active) → BB (if active) → UTG (if active) → ... → CO → BTN
```

BTN always acts **last** on every post-flop street.

If SB has folded, the first active player left of BTN goes first (usually BB).
If both SB and BB have folded, the first remaining player left of BTN opens the street.

---

## Street Close Rules

### No aggression (check-around)
Street closes when every active player has checked. No one put in a bet.

### Bet or raise on the street
Street closes when every active player has either:
- Folded, OR
- Called the highest outstanding bet/raise

The last aggressor does NOT need to act again (they set the price, others respond).

### Re-raise
When Player B raises Player A's bet, Player A must act again. The street does not close until every player who hasn't folded has matched the highest raise — including players who already acted earlier on that street.

### Preflop close with a raise — the correct check
```
Street is closed when:
  ALL active players EXCEPT the last raiser
  have either folded or called the raise amount.
  AND the BB has acted (BB is the last player in the preflop sequence).
```

BB calling after BTN calls = street closed (assuming SB folded or called).
BB raising after BTN calls = street NOT closed. Action cycles back to everyone who called before BB raised.

---

## Fold-Out (Early Hand End)

If at any point only one active player remains (all others folded), the hand ends immediately.
- No further streets are dealt.
- The remaining player wins without showing cards.
- This can happen on any street, including preflop.

---

## Showdown

Triggered when the river action closes and **two or more players remain active**.
Players reveal hole cards; best 5-card hand wins.

---

## Implications for the App

### Preflop highlight sequence
```
Start: UTG
End:   BB (always — BB is the last voluntary actor preflop)
```
BB must always be reached and allowed to act. No street-close detection should fire before BB has acted in a raised pot.

### Post-flop highlight sequence
```
Start: first active player clockwise from BTN (usually SB or BB)
End:   BTN (always — BTN acts last on every post-flop street)
```

### Street close detection — correct algorithm
```
Preflop with a raise:
  lastRaiser = the seat of the most recent open/raise action
  respondedAfter = all seats that called or folded AFTER the lastRaiser's action
  streetClosed = every active seat (except lastRaiser) is in respondedAfter
                 AND BB is in respondedAfter (BB acted last)

Preflop no raise (limped pot):
  streetClosed = BB has acted (checked or raised)

Post-flop no bet:
  streetClosed = every active player has checked

Post-flop with a bet/raise:
  lastRaiser = most recent bettor/raiser
  respondedAfter = all seats that called or folded AFTER lastRaiser
  streetClosed = every active seat (except lastRaiser) is in respondedAfter
```

### Direct seat tap routing

Preflop and post-flop are two distinct interaction models, dispatched on the current street.
A tap on the **highlighted seat** cycles its action in place in both models, looping forever with
no blank state (bet context: Call → Raise → Fold → Call → …; no-bet context: Check → Bet →
Check → …). Street-close never fires during cycling — the player is still deciding. The only way
to undo an action is the Undo button.

**Re-aggression guard (both models).** If the highlighted seat has already acted but now owes a
response to new aggression (`hasActed && owesAction`), every tap on a non-highlighted seat is a
no-op. The seat on the clock must cycle its response before the action can move forward.

**Preflop — navigation model.** A tap moves the action *to* the seat you point at; the tapped
seat is the destination.
- **Hero seat** — fully participatory. Functionally identical to any other active seat; the "HERO"
  label is cosmetic only. There is no special-casing — tapping it routes exactly like any seat.
- **Resolved or folded seat** — no-op. Resolved = has acted this street and faces no outstanding
  aggression. You also cannot jump *past* a seat that has already acted this street — it must
  respond in sequence and cannot be auto-folded.
- **Any other active seat** — preflop jump: auto-folds the seat being left (if it never acted)
  and every active seat skipped over clockwise, then records the tapped seat's default (a
  call/limp) and leaves it on the clock. This covers both never-acted seats *and* seats that
  acted but owe again after a raise (e.g. UTG facing a 3-bet) — both are simply "act here next."
  Skipped folds are flagged `isAutoFolded` so Undo removes the whole batch in one press.

**Post-flop — two contexts, dispatched on whether a bet exists this street.** A skipped seat
checks, it never folds (there is no fold-by-skipping post-flop). Tapping a resolved or folded
seat is a no-op in both contexts.
- **No bet yet** — post-flop jump, mirroring the preflop jump: auto-*checks* the seat on the
  clock (if unacted) and every unacted seat skipped over clockwise, then lands the tapped seat at
  Check. Auto-checks reuse the `isAutoFolded` batch flag so Undo removes them in one press. Tap
  the landed seat again to cycle Check → Bet.
- **A bet exists** — strict order only: only the exact next seat that owes action
  (`nextOwingSeat`) can be tapped. It commits the seat on the clock (default Call) and lands the
  tapped seat at Call. Any other seat is a no-op.

Note on the post-flop bet symbol: the first wager on a post-flop street is a **bet** (`.open`,
shown as `→`); only a wager that re-raises an existing bet is a **raise** (`.raise`, shown as
`↑↑` / pip layout). They are distinct actions.

There is no undo via seat tap in either model; use the Undo button instead.

**Swipes** are a decisive shortcut layered over this same model: a directional swipe records a chosen
action (← Fold, ↑ Raise, → Bet, ↓ Call/Check) in one gesture — picking the action directly instead
of cycling to it — and a press-and-hold attaches a size to a bet/raise. After recording, a swipe
**advances the ring to the next player without seeding any action on it** — the next seat enters
empty/waiting. This is identical to an action-button press; both share one settle path
(`settleAfterCommit`). Crucially the swipe does **not** seed the next seat (that would commit a
decision the user never made — tapping past an empty seat later auto-folds/-checks it correctly).
Swipes follow the same routing and guards above and **never advance the street** — a closing swipe
holds on the acting seat and lights the Next Street button.

**Action buttons** (Fold/Call/Raise · Check/Bet) act on the seat on the clock, then settle exactly
like a swipe (record → advance the ring to the next player, no seed). The only control that advances
a street is the **Next Street button**; no action button, tap, or swipe ever does.

**The pulse cue.** Exactly one thing pulses at a time: the seat on the clock. When a committed input
(button/swipe) completes the betting round, the acting seat's highlight clears and the **Next Street
button pulses instead** — the cue to advance. (A round completed by tapping leaves the seat pulsing
and the button lit-but-calm, since taps are tentative.)

**Undo** (the step-back control; labeled "Undo", `↺`). Recording is two kinds of step — a *cue-advance*
(the ring/pulse moves, no log entry) and an *action* (a log entry); Undo reverses a cue-advance before it
deletes anything. The
cue sits "ahead of the log" in two equivalent forms: on an *empty waiting seat* (after an
advance-no-seed) or on the *Next Street button* (after a decisive close). In either case the first
Undo returns the cue to the last actor (showing their action) **without deleting**; a further press
then undoes that action. Beyond that it peels the last action, crossing street boundaries and
stripping system-generated auto-action batches in a single press. Undo is **reversible at hand
close**: after a fold-out it re-opens recording and peels the fold; after a resolved showdown it
re-opens the Win/Lose/Chop overlay to re-pick.

**Dealing the next hand.** There is no New Hand button. From the closed state, tapping any seat
places the dealer button there and deals the next hand (the same gesture as the first hand's button
placement). Implemented in `HandEntryView.swift` (routing) and `SeatSelectionView.swift` (gestures).
