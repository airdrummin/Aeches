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

### Action cycling via direct seat tap
When a player taps their own seat to cycle actions (call → raise → fold → clear),
the street-close check must NOT fire mid-cycle. The player is still deciding.
Street-close fires only when the player commits — via the action bar or by tapping the next player.
