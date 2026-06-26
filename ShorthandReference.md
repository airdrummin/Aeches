# Hand Shorthand — Notation Reference

This file is the authoritative source of truth for the **shorthand text** Aeches generates as a hand is
recorded — the running transcript shown in the Record screen and copied to paste into a poker chat.

It defines two things that share one notation system:
1. **Card notation** — what the per-street card picker produces (hole pair, flop, turn, river).
2. **Action shorthand** — how each recorded action renders as text.

The shorthand is a **pure render of the action log** (`streets` + `actionsThisStreet` + the card slots +
`heroSeat`). It introduces no new state. It must stay in sync with the log automatically, including after
Rewind/edits, because it is derived, not stored.

> The style is **locked**. Examples throughout reflect the final style.

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

An `x` is **explicit when deliberately entered** — a card the player marked unknown on purpose always
renders its `x`, even alone (`Jx`, `Qx`). A card simply *left unsuited* renders bare (`J`) **unless** a
partner card in the group carries a real suit, in which case it is shown as `x` too (`AhKx`).

### Bound vs footnote — a recording-time distinction
Suit information attaches in one of two ways, captured at entry time:
- **Bound:** a suit is assigned to a *specific* card (entered interleaved, rank-then-suit). `AdJx`
  means "the Ace is the diamond, the Jack unknown."
- **Footnote:** suits are an *unassigned* note on the group (entered ranks-first, then suits). `AJdx`
  means "one of these two is a diamond, doesn't matter which." The footnote letters trail the ranks
  and are **padded to the group size with `x`** (so a single recorded suit shows the rest as `x`).

Both are legal house style; pick by how the hand was recorded.

### Hole cards (always a pair)
Two cards, higher rank first:
- **Both suits known (bound):** `AhKh`, `AsKd`.
- **Relationship only (suited/offsuit):** `AKs`, `AKo`, `T9s`.
- **One suit known (bound):** write it, `x` the other — `AsKx`.
- **Footnote (unassigned suits):** ranks, then suit letters padded to two with `x` — `AJdx`
  (one diamond, one unspecified). One recorded suit only still pads: `AJd` is written `AJdx`.
- **Neither suit:** bare ranks — `AK`, `T9`.
- **Pocket pair:** `99`, `AA` (no `s`/`o`).

### Flop (three cards)
Three rank+suit tokens, in entry order:
- **Per-card suits known (bound):** concatenate — `Qh5h3c`.
- **Rainbow (suits distinct, unspecified-which):** bare ranks + `r` — `Q53r`.
- **Monotone (all same, unspecified-which):** bare ranks + `m` — `Q53m`. If the suit is known, write it:
  `QhJh4h`.
- **Two-tone:** two ways. Abstract (suits unspecified) — bare ranks + `tt`, `Q53tt`. Explicit per-card —
  `Qh5h3x` (two hearts, third unknown).
- **Footnote (unassigned suits):** ranks, then suit letters padded to three with `x` — `Q53hhx`
  (two hearts, one unspecified).

### Turn / River (one card each)
A single rank+suit token: `Jh`, `5x`, `2c`. (Single cards are bound-only — no footnote or
relationship.)

**Board-suit count (turn/river only).** When a turn or river card brings a significant suit, the
suit letter may be **repeated to show how many of that suit are now on the board** — a flush draw or
made flush. The card is still that one suit; the repetition is a board annotation, user-asserted:
- `4ss` — the spade makes **two** on board (flush *draw*).
- `4sss` — **three** on board.
- `4ssss` / `4sssss` — four / five (made flush on turn / river).

Counts that can matter per street: **turn `2–4`**, **river `3–5`** (two of a suit can't make or draw a
flush on the river). A plain single suit (`4s`) is unchanged.

---

## 3. Positions
Frozen on each `Action` at record time (via `calculatePositions`), computed over the **occupied
seats** (all seats minus empties) so labels are stable throughout the hand even as players fold, and
short-handed when seats are unoccupied. The 10-handed ring, in action order:
`UTG, UTG+1, MP, MP+1, LJ, HJ, CO, BTN, SB, BB` (drop the middle/early fillers as the count shrinks —
see `PokerActionReference.md` "Positions by Table Size").

---

## 4. Header line

Every transcript opens with a header derived from what is currently known:

```
Hand #N - [hole cards] - [hero position] - [effective stack]
```

- **Hand number** is always present.
- **Hero position** is added once the dealer button is placed (position is button-relative).
- **Hole cards** are added once entered; they appear between the hand number and the position.
- **Effective stack** is added once entered, trailing the header as `Nbb eff` (always big blinds,
  1–999). It is **independent** of cards/position — it shows the moment it's set, even before the
  button is placed (`Hand #3 - 50bb eff`).
- If nothing else is entered: `Hand #3` (or `Hand #3 - 50bb eff` with just the stack)
- If cards are not yet entered: `Hand #3 - CO`
- If cards are entered: `Hand #3 - JTss - CO`
- Fully populated: `Hand #3 - JTss - CO - 50bb eff`

Hero's position, hole cards, and effective stack are **declared once in the header only**. They do
not appear again in the action lines.

> Effective stack is a single user-entered number — the shortest stack still in the hand by the
> flop — recorded *in lieu of* tracking every player's stack. It is hand metadata (not part of the
> action log): set via the "Eff" chip beside the transcript title → a docked numeric keypad,
> untouched by Undo, blank every hand. See README "Effective Stack".

---

## 5. Who is who

- **Hero** is written as `Hero` throughout all action lines. No inline position/card declaration —
  that information lives in the header (§4).
- **Villains** are written by **position** throughout: `BTN call`, `CO R`. Positions are unique
  per hand, so no disambiguation is needed even multiway.

---

## 6. Action verbs

Base verbs by `ActionType` and street:

| Log `ActionType` | Preflop | Post-flop |
|---|---|---|
| `.fold`  | `fold` | `fold` |
| `.check` | `chk`  | `chk`  |
| `.call`  | `call` — **but** an unraised first-in call renders `limp` | `call` |
| `.open`  | `R` (the open) | `bet` (the open) |
| `.raise` | `R` / `3b` / `4b` / `5b` … by running aggression count | `R` / `3b` / `4b` / `5b` … by running aggression count |

**Re-raise level notation (both streets):**
One escalation ladder serves preflop and post-flop. Count wagers as a `level` that **includes the
implied preflop blind** — the blind sits in front as the first bet, so preflop is shifted up one:
```
level = aggIndex + (preflop ? 1 : 0)
  level 1  → "bet"    (post-flop open only)
  level 2  → "R"  (preflop open / post-flop first raise; `R` is shorthand for raise)
  level 3+ → "3b", "4b", "5b" …
```
So preflop reads `R, 3b, 4b…` and post-flop reads `bet, R, 3b, 4b…`. There is no `2b` label —
the level-2 wager is always `R`. Post-flop the open is an `.open` (`bet`), so a post-flop `.raise`
is always level 2+; each genuine re-raise is a new escalation and renders a distinct token (which is
also why consecutive re-raises never collapse together — see §8 Same-action collapse).

**Verb / size rendering (applies to everyone — Hero and villains):**
- **The opening wager of a street** — the post-flop `bet`, or the pre-flop open `R` — **elides
  when sized**: show just the size (`SB 50%`, `Hero 3x`, `BTN Pot`). Unsized, it keeps its verb
  (`SB bet`, `Hero R`).
- **A re-raise** (any wager past the open) **always keeps its escalation label** (`R` / `3b` /
  `4b` …) and **appends the size** when one was entered: `HJ R 3x`, `LJ 3b 2.3x`, `5b 3x`. Unsized,
  just the label: `HJ R`, `LJ 3b`. The label carries the escalation that a bare size would hide, so
  re-raises are uniform whether or not a size was attached. (`R` is the shorthand for raise.)
- Non-wager actions **always** keep their word: `chk`, `call`, `limp`, `fold`.
- All-in arrives as the sizing label `All-in` → render the **verb** `jam`, no trailing size (opens and
  re-raises alike).

---

## 7. Bet sizing
Append the size after the verb, or use it alone under elision (§6). Read `sizing.label` straight through
when present; omit when nil (never invent a size). The sizing chips only ever emit two relative kinds
(plus the two named presets) — there is **no flat BB or cash/chip action size** (the only `bb` anywhere
is the effective-stack header, §4):
- Multiple (Raise chips) → `2x`, `2.2x`, `4x`
- Pot fraction (Bet chips) → `30%`, `90%`
- `Pot` → `Pot`; `All-in` → verb becomes `jam`.

---

## 8. Line structure

**Header first, then one line per street.** Each post-preflop street line leads with the bare board
token, then actions in log order, period-separated. The preflop line has no board. Streets never
reached are absent.

**Preflop fold suppression.** On the preflop line, a player whose **only** recorded action is a fold
is omitted entirely. This covers:
- Players who fold before acting voluntarily (UTG folds, SB folds without limping).
- BB folding to a raise (their only recorded action is the fold — the blind post is not an action).

A fold IS shown when the player took any prior voluntary action on the street (limped then faced a
raise and folded; raised then faced a re-raise and folded).

**Every action is named.** Each action on every street includes the actor's name (`BB chk`, `Hero bet`).
There is no anonymous check-around collapse.

**Same-action collapse.** When consecutive actors in the log take the same action (same rendered
token), they are joined into one entry:
- Two players: `HJ & Hero call`
- Three or more: `UTG, HJ & Hero call`

Collapse applies on all streets including preflop, and to all action types including checks
(`BB & Hero chk`). Non-consecutive same-token entries are not collapsed.

```
Hand #3 - JTss - CO
HJ R. Hero call. BB 3b. HJ & Hero call.
QQJhhx. BB bet. HJ fold. Hero call.
5x. BB & Hero chk.
9d. BB bet. Hero call.
```

---

## 9. Hand close

- **Fold-out:** ends on the final `fold` — **no winner tag**. The last player standing is implied.
- **Showdown:** the outcome isn't derivable from the action, so append a **minimal result line** from the
  recorded `Outcome`: `Hero wins.` / `Hero loses.` / `Chop.` If villain hole cards were entered (future),
  precede it: `BTN shows KK. Hero wins.`

---

## 10. Worked examples (final style)

**A — single-raised pot, heads-up to showdown:**
```
Hand #1 - AJo - UTG
UTG R. BTN call.
Q53r. Hero bet. BTN 2.2x. Hero call.
Jh. Hero chk. BTN 30%. Hero fold.
```

**B — 3b pot, multiway preflop, two-tone flop:**
```
Hand #2 - AhKh - CO
Hero R. BTN call. SB 3b. Hero & BTN call.
Qh5h3x. SB 33%. Hero call.
2c. SB chk. Hero 60%. SB fold.
Hero wins.
```

**C — limped pot, monotone flop, jam, runout, showdown:**
```
Hand #3 - 88 - BB
UTG limp. CO limp. Hero chk.
9c4c2c. Hero 50%. CO jam. Hero call.
Kx.
Tx.
Hero wins.
```
> Once two players are all-in, later streets are just board cards — render the bare board token on
> its line, then the showdown result.

**D — re-raise war, sized (escalation label + size, no collapse):**
```
Hand #4 - AK - SB
UTG R. HJ call. SB 3b 3x. UTG & HJ call.
Q53r. SB 50%. UTG R 3x. HJ 3b. SB 4b 2.3x. UTG & HJ call.
```
> The **open** of each street elides when sized (pre-flop `UTG R` unsized; flop `SB 50%`); every
> **re-raise** keeps its escalation label and appends the size (`SB 3b 3x`, `UTG R 3x`,
> `SB 4b 2.3x`), with `HJ 3b` showing the label alone when unsized. Distinct tokens mean consecutive
> re-raises never collapse; the trailing same-token `call`s still do (`UTG & HJ call`).

---

## 11. Implementation notes

*For the code team — outside readers can stop at §10.*

- **Pure function over the log.** Built from `streets`, `actionsThisStreet`, the four card-slot
  groups, `heroSeat`, `handNumber`, `buttonSeat`, and each `Action`'s frozen `position` +
  `sizing.label`. No new `@State` — computed like `seatActions`, so it tracks Rewind/edits for free.
- **Position stability.** `positionFor(seat:)` calls `calculatePositions` with the **occupied** seats
  (all seats minus empties), never `activeSeatSequence` — occupancy doesn't change when a player
  folds, so positions stay stable across folds (and avoid the folded-BTN `"?"` bug).
- **Preflop fold filter.** Before building the preflop line, skip any `.fold` whose seat has exactly
  one action on the street (§8 fold suppression).
- **Verb dispatch** keys on `actionType` + street + running `aggCount`, and **elision** on
  `sizing != nil` — the same signals the seat-symbol layer uses, so visuals and transcript agree.
- **One card formatter** serves both the slot display and the transcript tokens.
- **The panel** renders in Courier New, auto-scrolls to the last line, and Copy puts the full string
  on the clipboard. **No silent invention:** missing size → omit; missing suit → `x`.
