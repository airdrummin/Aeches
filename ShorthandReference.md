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
Frozen on each `Action` at record time (via `calculatePositions`), always using the **full table ring**
so labels are stable throughout the hand even as players fold:
`UTG, UTG+1, UTG+2, UTG+3, MP, MP+1, MP+2, HJ, CO, BTN, SB, BB`.

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
- **Villains** are written by **position** throughout: `BTN call`, `CO raise`. Positions are unique
  per hand, so no disambiguation is needed even multiway.

---

## 6. Action verbs

Base verbs by `ActionType` and street:

| Log `ActionType` | Preflop | Post-flop |
|---|---|---|
| `.fold`  | `fold` | `fold` |
| `.check` | `chk`  | `chk`  |
| `.call`  | `call` — **but** an unraised first-in call renders `limp` (Decision C) | `call` |
| `.open`  | `raise` (the open) | `bet` |
| `.raise` | `3b` / `4b` / `5b` … by running aggression count | `raise` |

**Re-raise level notation (preflop `.raise` only):**
The running aggressive-action count (`aggIndex`) determines the label. The first `.open` is always
`raise`; subsequent `.raise` actions increment the count: first re-raise → `3b`, second → `4b`,
third → `5b`, etc. There is no `2b` label — an open raise is always `raise`.

**Verb elision (applies to everyone — Hero and villains — and to both bet and raise):**
- When a wager carries a **size**, drop the verb and show **just the size**: `Hero 30%`, `BTN 2.2x`,
  `CO 9bb`. Both bet and raise elide; context (is there already a bet this street?) tells which.
- An **unsized** wager keeps its verb: `Hero bet`, `BTN 3b`, `Hero raise`.
- Non-wager actions **always** keep their word: `chk`, `call`, `limp`, `fold`.
- All-in arrives as the sizing label `All-in` → render the **verb** `jam`, no trailing size.

---

## 7. Bet sizing
Append the size after the verb, or use it alone under elision (§6). Read `sizing.label` straight through
when present; omit when nil (never invent a size):
- Pot fraction → `30%`, `90%`
- Multiple → `2.2x`, `3x`
- Big blinds → `2.5bb`, `9bb`
- Cash / chips → `$120`, `4000`
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
HJ raise. Hero call. BB 3b. HJ & Hero call.
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
UTG raise. BTN call.
Q53r. Hero bet. BTN 2.2x. Hero call.
Jh. Hero chk. BTN 30%. Hero fold.
```

**B — 3b pot, multiway preflop, two-tone flop:**
```
Hand #2 - AhKh - CO
Hero raise. BTN call. SB 3b. Hero & BTN call.
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

**D — preflop fold-out (villain folds on the river):**
```
Hand #4 - KQs - HJ
Hero raise. CO 3b. Hero call.
Js7s2h. Hero chk. CO 33%. Hero call.
4s. Hero chk. CO bet. Hero raise. CO fold.
```

**E — sized open (elided), preflop fold-out:**
```
Hand #5 - AQs - BB
UTG raise. CO call. Hero 4bb. UTG fold. CO call.
Js7s2h. Hero 33%. CO call.
...
```

---

## 11. Style decisions (locked)

- **A. Header:** `Hand #N - [cards] - [position] - [Nbb eff]` always leads. Hero position, hole
  cards, and effective stack declared there only — never inline in the action text. Cards slot in
  once entered; position slots in once button is placed; the stack trails as `Nbb eff` once entered
  (independent of the rest).
- **B. Hero label:** `Hero` always, in all action lines. No "Hero - CO" inline declaration.
- **C. Villain label:** position throughout (`BTN`, `HJ`, etc.). Position is stable for the full
  hand — frozen using the full table ring at record time, not recalculated as players fold.
- **D. Verb elision:** sized wager → bare size for **everyone**, bet **and** raise; unsized wager
  keeps the verb; `chk`/`call`/`limp`/`fold` always keep their word.
- **E. Re-raise notation:** `3b` / `4b` / `5b` for preflop re-raises. No `2b` — an open is always
  `raise`. No long-form `3-bet`/`4-bet`.
- **F. Preflop fold suppression:** omit any player whose only preflop action is a fold.
- **G. Named actors always:** every action on every street includes the actor's name.
- **H. Same-action collapse:** consecutive actors with the same rendered token collapse into a
  single entry joined by `&` (and `,` for three or more).
- **I. Check-around:** no special case — follows the named-actors and collapse rules like any other
  street. A two-player check-around reads `A & B chk.`
- **J. Limp:** an unraised first-in preflop call renders `limp`; a call facing a raise is `call`.
- **K. Fold-out:** no winner tag — the final `fold` ends it. Showdowns get a minimal result line.
- **L. Board labels:** bare board tokens lead each street line; no `Flop`/`Turn`/`River` word.

---

## 12. Implementation notes

- **Pure function over the log.** Input: `streets`, `actionsThisStreet`, the four card-slot groups,
  `heroSeat`, `handNumber`, `buttonSeat`, each `Action`'s frozen `position` + `sizing.label`.
  Output: the multi-line string. No new `@State` — computed like `seatActions` so it tracks
  Rewind/edits for free.
- **Header** is built first: `Hand #N`, then append ` - [pos]` once `buttonSeat` is set, then
  insert cards once `groupNotation(.hole)` is non-empty, then append ` - [N]bb eff` once
  `effectiveStack` is non-nil (this last segment is independent — it appends regardless of whether
  the button/cards are set).
- **Position stability.** `positionFor(seat:)` always calls `calculatePositions` with
  `Array(0..<tableSize)` — never `activeSeatSequence`. This prevents the folded-BTN bug where
  `calculatePositions` returns `[:]` and every post-flop position resolves to `"?"`.
- **Preflop fold filter.** Before building pairs for the preflop street, skip any action where
  `actionType == .fold` AND that seat has exactly one action on the preflop street.
- **Verb dispatch** keys on `actionType` + street (preflop vs post-flop) + running `aggCount` for
  re-raise level — the same signals the seat-symbol layer uses, so the two stay consistent.
- **Elision** checks `sizing != nil`: present → emit the label alone; absent → emit the base verb.
- **Same-action collapse** (`collapsedSegments`): iterate pairs; accumulate a run while the next
  pair's token matches; emit the joined actor string + token; advance.
- **Hero** in all action lines is just `"Hero"` — no position or card suffix. The header carries
  those once.
- **Card tokens** are the same notation the picker writes — one formatter serves both the slots'
  display and the transcript.
- **The transcript panel** renders this in Courier New, auto-scrolls to the last line, and exposes
  Copy (copies the full multi-line string).
- **No silent invention:** missing size → omit; missing suit → `x`.
