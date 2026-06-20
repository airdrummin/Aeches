# Hand Shorthand — Notation Reference

This file is the authoritative source of truth for the **shorthand text** Aeches generates as a hand is
recorded — the running transcript shown in the Record screen and copied to paste into a poker chat.

It defines two things that share one notation system:
1. **Card notation** — what the per-street card picker produces (hole pair, flop, turn, river).
2. **Action shorthand** — how each recorded action renders as text.

The shorthand is a **pure render of the action log** (`streets` + `actionsThisStreet` + the card slots +
`heroSeat`). It introduces no new state. It must stay in sync with the log automatically, including after
Rewind/edits, because it is derived, not stored.

> Style decisions are **locked** (see §10). Examples throughout reflect the final style.

---

## 1. Design goals

- **Human-readable first.** The output is pasted into a chat with another poker player — it must read the
  way players actually talk. Grounded in common forum/live-notation conventions (there is no formal
  universal standard; this is our house style, built on those conventions).
- **Compact.** Short verbs, elision where unambiguous, one line per street.
- **Lossless for what matters.** Every recorded action, size, and board card appears. Things the app never
  captured (exact stacks, pot totals) are simply absent — the notation is relative, never invented.
- **Stable.** Same log → same string, every time.

---

## 2. Card notation

### Ranks
`A K Q J T 9 8 7 6 5 4 3 2` — always `T` for ten (never `10`).

### Suits
Lowercase, appended to the rank: `s` spades, `h` hearts, `d` diamonds, `c` clubs.
**Unknown / unrecorded suit = `x`** (e.g. `Kx`). Suit is always optional, so `x` is legal anywhere a suit
can go. Examples: `Ah` `Ks` `5x` `Td`.

### Hole cards (always a pair)
Two cards, higher rank first:
- **Both suits known:** `AhKh`, `AsKd`.
- **Relationship only (suited/offsuit):** `AKs`, `AKo`, `T9s`.
- **One suit known:** write it, `x` the other — `AsKx`.
- **Neither suit:** bare ranks — `AK`, `T9`.
- **Pocket pair:** `99`, `AA` (no `s`/`o`).

### Flop (three cards)
Three rank+suit tokens, in entry order:
- **Per-card suits known:** concatenate — `Qh5h3c`.
- **Rainbow (suits distinct, unspecified-which):** bare ranks + `r` — `Q53r`.
- **Monotone (all same, unspecified-which):** bare ranks + `m` — `Q53m`. If the suit is known, write it:
  `QhJh4h`.
- **Two-tone:** explicit per-card suits, no shortcut letter — `Qh5h3x` (two hearts, third unknown).

### Turn / River (one card each)
A single rank+suit token: `Jh`, `5x`, `2c`.

---

## 3. Positions
Frozen on each `Action` at record time (via `calculatePositions`):
`UTG, UTG+1, UTG+2, UTG+3, LJ, HJ, CO, BTN, SB, BB`. (6-max: `UTG HJ CO BTN SB BB`.)

---

## 4. Who is who (Decision A)

- **Hero** is declared once, at Hero's **first action**, as `Hero - <POS>`, with **hole cards** attached at
  that first mention. After that, just `Hero`.
  - `Hero - UTG raise AJo` (hero opens first) … later `Hero chk`.
  - If hero acts later in the line, the declaration appears there: `UTG raise. CO call. Hero - BB call AJo.`
- **Villains** are written by **position** throughout: `BTN call`, `CO 3-bet`. (Positions are unique per
  hand, so no disambiguation is needed even multiway.)

Hole cards sit **after** the opening verb/size on the declaration (`raise AJo`, or `2.5x AJo` when the open
was sized).

---

## 5. Action verbs (Decision A — elision)

Base verbs by `ActionType` and street:

| Log `ActionType` | Preflop | Post-flop |
|---|---|---|
| `.fold`  | `fold` | `fold` |
| `.check` | `chk`  | `chk`  |
| `.call`  | `call` — **but** an unraised first-in call renders `limp` (Decision C) | `call` |
| `.open`  | `raise` (the open) | `bet` |
| `.raise` | `3-bet` / `4-bet` / `5-bet` by `betLevelThisStreet` | `raise` |

**Verb elision (applies to everyone — Hero and villains — and to both bet and raise):**
- When a wager carries a **size**, drop the verb and show **just the size**: `Hero 30%`, `BTN 2.2x`,
  `CO 9bb`. Both bet and raise elide; context (is there already a bet this street?) tells which.
- An **unsized** wager keeps its verb: `Hero bet`, `BTN 3-bet`, `Hero raise`.
- Non-wager actions **always** keep their word: `chk`, `call`, `limp`, `fold`.
- All-in arrives as the sizing label `All-in` → render the **verb** `jam`, no trailing size.

---

## 6. Bet sizing
Append the size after the verb, or use it alone under elision (§5). Read `sizing.label` straight through
when present; omit when nil (never invent a size):
- Pot fraction → `30%`, `90%`
- Multiple → `2.2x`, `3x`
- Big blinds → `2.5bb`, `9bb`
- Cash / chips → `$120`, `4000`
- `Pot` → `Pot`; `All-in` → verb becomes `jam`.

---

## 7. Line structure (Decisions B, E)

**One line per street. Bare board, no street word.** Each post-preflop line leads with the board token(s),
then actions in log order, period-separated. The **preflop line has no board** and leads with the first
action (where Hero's declaration falls if Hero acts there). Streets never reached are absent.

**Check-arounds collapse:** a street where **every action is a check** drops the names — `chk chk` (one per
checker, in action order). The moment a street contains any wager, **every** action on it keeps its actor.

```
Hero - UTG raise AJo. BTN call.
Q53r. Hero chk. BTN 30%. Hero 2.2x. BTN call.
Jh. chk chk.
5x. Hero 90%. BTN fold.
```

---

## 8. Hand close (Decision D)

- **Fold-out:** ends on the final `fold` — **no winner tag**. The last player standing is implied.
- **Showdown:** the outcome isn't derivable from the action, so append a **minimal result line** from the
  recorded `Outcome`: `Hero wins.` / `Hero loses.` / `Chop.` If villain hole cards were entered (future),
  precede it: `BTN shows KK. Hero wins.`

---

## 9. Worked examples (final style)

**A — single-raised, heads-up to showdown:**
```
Hero - UTG raise AJo. BTN call.
Q53r. Hero chk. BTN 30%. Hero 2.2x. BTN call.
Jh. chk chk.
5x. Hero 90%. BTN fold.
```

**B — 3-bet pot, multiway preflop, two-tone flop, hero not first to act post-flop:**
```
Hero - CO raise AhKh. BTN call. SB 3-bet. Hero call. BTN fold.
Qh5h3x. SB 33%. Hero call.
2c. SB chk. Hero 60%. SB fold.
```

**C — limped pot, monotone flop, jam, runout checks, showdown:**
```
Hero - BB chk 88. UTG limp. CO limp.
9c4c2c. Hero 50%. CO jam. BTN fold. Hero call.
Kx. River Tx.    (no wagers after the jam-call; cards only)
Hero wins.
```
> Note: once two players are all-in, later streets are just board cards with no actions — render the bare
> board tokens (`Kx`, `Tx`) on their lines, then the showdown result.

**D — preflop fold-out (no flop, no tag):**
```
Hero - HJ raise KQs. CO 3-bet. BTN cold-4-bet. Hero fold. CO fold.
```

**E — sized open (elided), hero in the blinds:**
```
UTG raise. CO call. Hero - BB 4bb AQs. UTG fold. CO call.
Js7s2h. Hero 33%. CO call.
...
```

---

## 10. Style decisions (locked)

- **A. Hero label:** `Hero - <POS>` declared once at Hero's first action + hole cards there; `Hero` after.
  Villains by position.
- **A. Verb elision:** sized wager → bare size for **everyone**, bet **and** raise; unsized wager keeps the
  verb; `chk`/`call`/`limp`/`fold` always keep their word.
- **B. Check-arounds:** a pure all-check street collapses to bare `chk chk`; any street with a wager keeps
  every actor's name.
- **C. Limp:** an unraised first-in preflop call renders `limp`; a call facing a raise is `call`.
- **D. Fold-out:** no winner tag — the final `fold` ends it. Showdowns get a minimal result line.
- **E. Board labels:** bare board tokens lead each street line; no `Flop`/`Turn`/`River` word.

---

## 11. Implementation notes

- **Pure function over the log.** Input: `streets`, `actionsThisStreet`, the four card-slot groups,
  `heroSeat`, each `Action`'s frozen `position` + `sizing.label`. Output: the multi-line string. No new
  `@State` — render it like `seatActions` (a computed property) so it tracks Rewind/edits for free.
- **Verb dispatch** keys on `actionType` + street (preflop vs post-flop) + `betLevelThisStreet` for
  3-bet/4-bet naming — the same signals the seat-symbol layer uses, so the two stay consistent.
- **Elision** checks `sizing != nil`: present → emit the label alone; absent → emit the base verb.
- **Check-around collapse** is per-street: if every action on a street is `.check`, emit `chk` per action
  with no actor prefix; otherwise prefix every action.
- **Hero declaration** is emitted at the first action whose `seatIndex == heroSeat`; hole cards come from
  the hero card slots, formatted per §2.
- **Card tokens** are the same notation the picker writes — one formatter serves both the slots' display and
  the transcript.
- **The transcript panel** renders this in Courier New, auto-scrolls to the last line, and exposes Copy
  (copies the full multi-line string).
- **No silent invention:** missing size → omit; missing suit → `x`.
