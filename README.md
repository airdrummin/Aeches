# Aeches — AI Development Reference

This file is the authoritative briefing for any AI assistant working on the Aeches iOS app.
Read this before writing any code, designing any view, or making any architectural decision.

---

## What Aeches Is

Aeches is an iOS-only app built around two tightly coupled pillars:

1. **A hand history recorder** — a tap-based UI that lets poker players document hands faster than any existing solution. Zero typing required for a standard hand. Designed for one thumb, mid-session at a live table.

2. **A pro content marketplace** — poker professionals sell access to their hand histories via monthly subscriptions or à la carte session purchases, including live tournament runs.

**Recording is always free.** Aeches monetizes exclusively through a 10% platform fee on marketplace transactions (taken after Apple's 30% App Store cut).

**Founding pros:** Chance Kornuth and Alex Foxen — equity partners and early adopters.

---

## Design System

### Colors
- Background: near-black (`#0D0D0D`)
- Surface / card: dark gray (`#161616`, `#1E1E1E`, `#252525`)
- Primary accent: gold (`#C9A84C`)
- Light gold: `#E8D5A3`
- Body text: `#DDDDDD`
- Muted text: `#888888`
- Border: `#3A3A3A`
- Fold / error: `#C0392B`
- Win / success: `#27AE60`
- Felt green: `#1B3A2D`

**Dark mode is the only mode. No light mode adaptations.**

### Typography
- Headings / Display: **Georgia** (serif) — matches the HH monogram logo elegance
- Body / UI labels: **Arial** — clean, legible at small sizes in low-light
- Hand history notation: **Courier New** (monospace) — reinforces the shorthand format

### Logo & Branding
- The brand mark is the **HH monogram** — a double-H letterform with a spade integrated
- Visual language: luxury poker tool — refined, dark, discreet
- The app should not look like a poker app to other players across the table

### UX Principles
- **Speed is the primary UX metric.** Every extra tap is a failure.
- **One thumb, one hand.** UI elements are large, spaced for thumb reach, never requiring two-handed operation.
- **Discreet by design.** Looks like a note-taking app, not a poker tracker.
- **No onboarding friction.** First hand recorded within 60 seconds of download.
- **Poker-native language.** Use 3-bet, UTG, pot-sized bet, rainbow — not generic UX language.
- **Offline-first.** Recording requires zero network dependency. Sync happens silently in background.

---

## Navigation Structure

Bottom tab bar with 4 tabs:

1. **Record** — the hand entry UI (primary feature, default tab on launch)
2. **History** — the user's personal hand history log
3. **Marketplace** — browse and subscribe to pro creators
4. **Profile** — account settings, pro upgrade, creator dashboard

Pro-specific screens live inside the Profile tab — standard users and pros share the same tab bar.

History, Marketplace, and Profile are placeholder stubs. Record is fully implemented.

---

## Core Feature: Hand Entry UI

### Screen Architecture

The hand entry screen is a single persistent view split into two independently operating halves. The screen never navigates away during a hand — everything happens in place.

**Top half — Table**
A geometric oval poker table with gold leather rail, felt surface, and numbered seat buttons. Used to set the dealer button, record seat actions, and view action states. The table stays visible at all times.

**Bottom half — Cards**
A persistent strip showing all 7 card slots at once:
- Hero hole cards: 2 slots
- Flop: 3 slots
- Turn: 1 slot
- River: 1 slot

Both halves operate independently. The user can fill in cards before recording action, record action without entering cards, or interleave them freely.

### Screen Flow (within Record tab)

1. **Session creation** — select Cash Game or Tournament, fill in details. Session creates and loads the hand entry screen.

2. **Select seat** — tap any seat to lock in as hero (HERO). A table size picker (6 / 8 / 9 / 10) lets you correct the seat count. Seat stays locked for the entire session.

3. **Place dealer button** — tap any seat to set the dealer for this hand. The first highlight (UTG, or BB in short-handed games) appears automatically. Phase transitions to Recording. Before placing the button you can mark **empty seats** (see **Empty Seats** below) via the **Edit Seats** corner toggle — the button can't be placed on an empty seat.

4. **Recording** — both halves are active simultaneously. All recording controls live in a **Control Bar** pinned to the bottom (thumb zone), laid out in **two rows**: a slim **utility row** — **Undo** (left) · **Next Street / End Hand** (right) — above a **full-width primary row** of **action buttons**. When the hand closes the bar goes quiet (Undo only). Several input paths coexist:
   - **Action buttons** (the full-width primary row): act on the highlighted seat, then advance the ring to the next player. Context-aware:
     - Bet context (preflop, or any street with an open bet): **Fold / Call / Raise**
     - No-bet context (post-flop, no aggression yet): **Check / Bet**
     - An action button that *closes* the street holds on the acting seat and lights the Next Street button — it never advances the street itself (see §5).
   - **Undo button** (`↺` gold capsule, left of the utility row): steps back one action at a time. System-generated auto-action batches (preflop auto-folds, post-flop auto-checks) are removed in a single press, and when a jump empties the street the highlight returns to that street's first-to-act seat (not the seat that was tapped). When the current street has no actions left, the next press reopens the previous street with its last actor highlighted and its actions intact — a further press then undoes within that street. The cue can sit "ahead of the log" in two equivalent forms — on an *empty waiting seat* (after a button/swipe advance) or on the *Next Street button* (after a decisive street close, see below) — and in either case the first Undo returns the cue to the last actor (showing their action) without deleting; a further press then undoes that action. **Undo is reversible at hand close**: after a fold-out it re-opens recording and peels the offending fold; after a resolved showdown it re-opens the Win / Lose / Chop overlay to re-pick.
   - **Next Street / End Hand button** (right of the utility row): active in two cases:
     - The current street is fully closed (all active players acted / responded to the last raise)
     - **Preflop fast-forward**: a raise exists on the street AND 2+ players have committed AND no committed player faces unresolved aggression. Clicking the button auto-folds every remaining unacted seat (marked as system-generated so Undo removes them cleanly) and advances to the flop. Note: in a limped pot BB must act before the button goes live — BB always has the option.
   - **Direct seat tap** routing — preflop and post-flop are two separate models (dispatched on the current street). Tapping the **highlighted seat** cycles its action in place in both, looping forever with no blank state (bet context: Call → Raise → Fold → Call → …; no-bet: Check → Bet → Check → …); street-close never fires during cycling, and the only way to undo is the Undo button. A **re-aggression guard** applies to both models: if the highlighted seat has already acted but now owes a response to new aggression, every tap on another seat is a no-op until that seat cycles its response. Beyond that:
     - **Preflop (navigation model)** — a tap moves the action *to* the tapped seat. The **hero seat is fully participatory** — functionally identical to any other active seat (the "HERO" label is cosmetic only). Tapping a **resolved or folded seat** is a no-op, and you cannot jump *past* a seat that has already acted this street (it must respond in sequence). Tapping **any other active seat** does a preflop jump: auto-folds the seat being left (if it never acted) and every active seat skipped clockwise, then records the tapped seat's default (a call/limp) and leaves it on the clock — this covers both never-acted seats and seats that owe again after a raise (e.g. UTG facing a 3-bet).
     - **Post-flop (two contexts, dispatched on whether a bet exists)** — a skipped seat checks, never folds (no fold-by-skipping post-flop). Tapping a **resolved or folded seat** is a no-op in both. **No bet yet:** a tap does a post-flop jump mirroring the preflop jump — auto-*checks* the seat on the clock (if unacted) and every unacted seat skipped clockwise, then lands the tapped seat at Check (tap again to cycle Check → Bet). **A bet exists:** strict order only — only the exact next seat that owes action can be tapped; it commits the seat on the clock (default Call) and lands the tapped seat at Call.
   - **Direct seat swipe** (decisive shortcut) — swipe a seat to record a specific action in one gesture, without cycling: **← Fold, ↑ Raise, → Bet, ↓ Call/Check** (resolved by context; a direction that's illegal in the current context is a no-op). A swipe follows the same routing as a tap but lands the swiped action directly instead of cycling to it, then **advances the ring to the next player without seeding any action on it** — behaviorally identical to an action-button press. (Seeding the next seat is exactly what it must *not* do: that would commit a decision the user never made. The next seat enters empty/waiting; tapping past it later auto-folds/-checks it correctly.) A swipe that *closes* a street holds on that seat and lights the Next Street button — it never advances the street. (Implemented in `HandEntryView.swift` routing + `SeatSelectionView.swift` gestures.)
   - **Hold-to-size** (optional) — press and hold the **Raise** or **Bet** action button (0.3s) to reveal a horizontally-scrolling sizing chip strip that fills the **utility row to the right of Undo**. Undo stays pinned; the **Next Street button is hidden while sizing** (a staged raise/bet never closes the street, so it would be disabled anyway), giving the chips the full width. The Fold/Call/Raise row never moves. Raise opens multiples (`2x`, `2.2x`, `2.5x`, `2.8x`, `3x`, `3.2x`, `3.5x`, `4x`, `5x`, `All-in`); Bet opens pot fractions (`10%`, `25%`, `33%`, `50%`, `67%`, `75%`, `90%`, `Pot`, then overbets `110%`–`200%`, `All-in`). Chips are color-coded by kind: green for every `%` (sub-pot and overbet), gold for `Pot`, purple for raise multiples, light gold for `All-in`. The held action is recorded **unsized immediately** (like cycling) and the seat stays on the clock; tapping a chip re-records it sized and advances the ring, while the held Raise/Bet button shows "selected" (solid gold) until then. **Quick tap** on Raise/Bet is always decisive and unsized; **swipes** are always unsized. Undo while the strip is up dismisses it and peels the staged raise/bet in one press. Sizes are relative notation only — no chip/pot math. Shown as a pill on the seat's bottom rim.
   - **Card strip** (bottom half): tap any slot to open the **per-street card picker**, which **docks in the gap below the strip** — the strip slots stay visible and act as both the frames and the live preview (no separate notation readout). Entry is **left-to-right**: tapping any slot focuses the left-most empty frame. A whole street is entered at once (**2 hole, 3 flop, 1 turn, 1 river**) with the rank grid, suit buttons (♠ ♥ ♦ ♣ + explicit **x**), and relationship shortcuts on one screen. A **slim grab handle** (tap or swipe down) dismisses; **Next** (`›`) jumps to the next bank (hole → flop → turn → river, `✓` on the river); a trash icon clears the bank. See **Card Entry** below and `ShorthandReference.md` §2 for the notation.
   - **Skip / Move** (corner overlay buttons on the table oval, outside the rail): two small capsule buttons, deliberately placed away from the normal thumb zone to prevent accidental taps. They cleanly split two separate decisions — *end this hand* (Skip) and *where the next hand starts* (New Hand = same seat / Move = new seat).
     - **Skip** (upper-left, red tint) — the only mid-hand "end this hand" control. Freezes the in-progress hand exactly like a showdown/fold-out close: saves it incomplete (`outcome: nil`), shows **SKIPPED** on the felt, and stays on the **same hand number** (New Hand advances it, like any close). All hand state is preserved so **Undo** reopens recording at the last action (no peel). Visible only during `recordingHand` and `showdown`.
     - **Move** (upper-right, muted tint) — "next hand, **new seat**." Releases the hero seat and returns to seat selection (**"TAKE YOUR SEAT"** → **"PLACE THE BUTTON"**). Shown only at **`handClosed`** (deals the next hand, so the number advances — the finished hand was already saved at close) and **`placingButton`** (re-pick the seat for the same, not-yet-started hand — number unchanged). It is **never shown mid-hand**: to change seats during a hand, end it with Skip first, then Move from the frozen state.

5. **Street progression** — a street is closed once all active players have acted / responded to the last raise. **Only the Next Street button advances the street** — no input (action button, tap, or swipe) ever advances it. A closing action holds the ring on the acting seat and lights the Next Street button; the user taps it to advance. On advance, state resets for the next street (actions cleared, bet level reset, highlight moves to first active seat left of dealer). The Next Street button label updates: Flop → Turn → River → Showdown.

6. **Hand close** — two paths:
   - **Fold-out**: when all but one player folds at any point, the hand closes immediately. No user action required.
   - **Showdown**: when the river closes with 2+ active players, a **Win / Lose / Chop** overlay appears centered on the table. Tap the outcome to close.

7. **Summary state** — the hand stays on its number (e.g. "Hand #1"). The **table stays frozen on the finished hand** — seat actions, positions, dealer button, and the final street all remain on screen so the completed hand reads clearly (the last street with action stays visible — the river at a normal showdown, or the last contested street in an all-in run-out, where the betting ended before the board was dealt out). The outcome renders as felt text in the center:
   - "You win"
   - "You lose"
   - "Chop"
   - "Seat X wins" (fold-out where hero already folded)
   The card strip and transcript below the divider remain fully editable — and at showdown/close, **empty card slots for streets the hand reached get a gold "enter these now" border** (hole always; a board street once it was dealt — so a flop fold-out lights hole+flop, not turn/river). The Control Bar goes quiet except for **Undo** (left) and **New Hand** (right, gold, pulsing); the **Move** corner button is also live (next hand, new seat). Undo remains live to reverse the close (re-open the showdown overlay, peel a mis-folded fold-out, or reopen a skipped hand).

8. **Deal the next hand** — tap the **New Hand** button (gold capsule, right of the utility row, shown only once the hand is closed). It's a **clean break**: the hand number advances (→ "Hand #2"), all hand state clears, and you land on the fresh **"PLACE THE BUTTON"** screen — then tap a seat to place the button, exactly like hand #1. Tapping a seat on the frozen closed table does nothing; New Hand (same seat) or **Move** (new seat) are the two ways forward. Hero seat stays locked unless you Move. (Every close — showdown, fold-out, or skip — leaves the number un-advanced, so New Hand always increments exactly once.)

### Table Design

- Gold leather rail with a gap at 12 o'clock for the house dealer station
- **DEALER** label centered in the gap
- Green felt surface with radial gradient, brass pinstripe, and stitching ring
- HH monogram watermark on felt
- Supports 6, 8, 9, and 10-seat configurations — configurable per session and adjustable on the seat-select screen
- Seat buttons show action state visually:
  - Gold border + →: a bet (first wager on a post-flop street)
  - Gold border + raise arrows: a raise. Pip-layout encodes bet level: ↑↑ side-by-side = open-raise (2-bet), triangle = 3-bet, 2×2 grid = 4-bet, single arrow + badge number = 5-bet+
  - Green border + ✓: call
  - Green border + —: check
  - Red border + ✕: fold
  - Gold pulsing ring: currently highlighted seat (action on them). Exactly one seat pulses at a time; on a decisive street close the ring clears and the Next Street button pulses instead
  - Green fill + HERO label: hero seat
  - Prior-action badges: small colored pills around the seat's upper edge showing that seat's earlier actions *this street*, distinct from its current center action (e.g. a player who raised then called a 3-bet shows a gold ↑↑ pill beside a green ✓ center). Up to 3 slots (upper-left, top, upper-right); 4+ collapses the oldest into a gray "+N". Symbols match the center: → bet, ↑↑ raise, ✓ call, — check, ✕ fold
  - Empty center while owing a fresh response: when the cue arrives on a seat that **acted earlier this street but now owes a response to new aggression** (an opener facing a 3-bet, a checker facing a bet), its center goes **empty** — it reads like any seat yet to act — and its earlier action(s) move to prior-action pills immediately. Once it acts, the new decision fills the center and the earlier action stays as a pill. Only the seat *currently on the clock* does this; other seats that also owe keep their last action shown until the cue reaches them in turn
  - Size pill: when a bet/raise was sized via hold-to-size, a small pill on the seat's *bottom* rim shows the notation (`2.5x`, `40%`, `Pot`, `All-in`). Clear of the top-edge prior-action badges; absent when no size was attached
  - All-in badge: an all-in seat reads **amber** (border, action symbol, and a subtle fill) with a persistent amber `ALL IN` pill on the bottom rim (replacing the size pill). It carries across every street and shows how the seat got all-in (`→` jam-bet, `↑↑` jam-raise, `✓` call-all-in). See All-in flow / `AllInFlow.md`

### Card Entry

Card entry is **per-street group entry**, not slot-by-slot. Tapping any slot opens that street's picker, which **docks in the gap below the strip** (the strip slots are the frames and the live preview — there is no separate notation readout). The data model is a per-street **`CardGroup`** of **`CardFrame`s**; each group carries exactly one **suit mode**.

- **One group per street:** hole = 2 frames, flop = 3, turn = 1, river = 1.
- **Left-to-right entry.** Tapping any slot focuses the **left-most empty** frame — the tapped index is ignored, since order does not matter. A rank fills the cursor frame and the cursor is "the card you just typed"; a following suit binds to it. Typing a rank into an **already-full** group **clears it and starts over** (you redo a hand by re-entering, never by editing one card). Re-opening a completed group is **display-only** until you start typing.

**Three suit modes** (mutually exclusive, chosen as you enter):
- **Bound** (interleaved) — a suit is assigned to a *specific* card. Rank then its suit: `AdJx` (Ace is the diamond, Jack unknown), flop `Qh5h3x`. The suit shows **on the card face**.
- **Footnote** (ranks first, then suits) — suits are an *unassigned* note on the group ("one of these is a diamond, doesn't matter which"). Caption renders lowercase letters padded to N with `x`: `AJdx`, `Q53hhx`.
- **Relationship** — an abstract texture from a shortcut button (hole `s`/`o`; flop `r`/`m`/`tt`). Caption renders the shorthand letters: `AKs`, `Q53tt`.

**On-card display layer** (visual, *in addition to* the caption text, which is always kept):
- **Bound** → the suit pip on each face.
- **Footnote, all one suit** (e.g. `QJcc`, `Q53hhh`) → that suit colored on every face.
- **Footnote, mixed/partial** (e.g. `♦♠`, `♦♦x`) → a **group texture pill** straddling the card row's bottom edge, glyphs colored for the dark pill.
- **Relationship** → the same pill, showing the **word**: `suited` / `offsuit` / `mono` / `two-tone` / `rainbow`.
- Principle: **a glyph = a real suit we know; a word = an abstract texture** — so spade `♠` and "suited" never collide.

- **Explicit `x`** is a first-class card state distinct from a blank frame — pressing `x` shows the `x` immediately and reads `Jx` / `Qx`, even alone. A frame simply *left* unsuited renders bare unless a partner card carries a real suit, in which case it reads `x` too (`AhKx`).
- **Two-tier, mutually-exclusive gating:** the suit buttons (`♠ ♥ ♦ ♣ x`) are live once the group has ≥1 rank, **unless** it is committed to a relationship; the relationship shortcuts are live only when **all** ranks are in and no specific suit has been chosen — and never for a **hole pair** (no `88s`; `88o` is assumed, never written). So at "both ranks, nothing chosen" both sets are live; the first suit turns the shortcuts off, the first shortcut turns the suits off.
- **Turn / River are bound-only** (a single card has no "which card" ambiguity) — rank + optional suit, no footnote or relationship. They alone support a **board-suit count**: re-tapping the suit, or the suit-skinned count buttons in the (otherwise empty) shortcut slot, repeats the suit to mark how many are now on the board — `4ss` (flush draw) / `4sss` … On the **card face** the suit pip simply repeats; on the **picker buttons** the count is drawn in a dice-like **pip layout** (1 single, 2 pair, 3 triangle, 4 a 2×2, 5 a 2-1-2), echoing the seat raise-pips. Counts: turn `2–4`, river `3–5`. See `ShorthandReference.md §2`.
- The 7–2 rank row is centered to nest into the gaps of the A–8 row above.
- Accepted notation: hole `AK`, `AKo`, `AKs`, `AhKs`, `AsKx`, footnote `AJdx`; flop `Q53r` / `Q53m` / `Q53tt` / `Qh5h3x` / footnote `Q53hhx`.
- The trash icon clears the group; the slim grab handle (tap / swipe down) dismisses; **Next** (`›`) advances to the next bank (`✓` on the river).

### Empty Seats

Real tables aren't always full — a seat busts out, or hasn't been filled yet. **Empty seats** mark which seats have no player this hand, so the hand plays (and labels positions) as a shorter-handed game: a 9-seat table with 2 empties acts exactly like 7-handed.

- **When:** edited at **place-button** only (the start of a hand). A muted **Edit Seats** corner button (upper-left, where Skip sits during recording) flips the table into edit mode: the felt reads **"TAP SEATS TO EMPTY,"** the corner button turns gold **Done**, and tapping any seat toggles it **empty ↔ occupied**. Tap **Done** to return to placing the button.
- **Render:** an empty seat is a **dashed grey ring with nothing inside** — no position label, no action, dimmed. It can't be acted on during recording, and the dealer button can't be placed on it.
- **Rules:** the **hero's seat can never be emptied**, and at least **2 seats stay occupied** (heads-up minimum). Taking a seat at seat-select fills it.
- **Persistence:** empty seats are **table composition, not per-hand action** — the set **carries across hands** (untouched by New Hand / Skip / Undo) until you edit it again, so you mark a busted seat once. Changing the table size (seat-select) clears it.
- **Positions adjust automatically.** Labels are computed over the **occupied** seats, so empties are skipped and the ring renumbers (e.g. seat 1 empty → that seat has no label; the next occupied seat becomes UTG). See `PokerActionReference.md` "Positions by Table Size."

### Incognito Mode

A session-wide privacy toggle for live play, so a neighbor at the table can't read the hero's hole cards. A single **eye toggle sits by the HOLE label** (faint when off, gold `eye.slash` when on). Hero-only — flop/turn/river are public board cards and are never hidden.

When on:
- **Hole faces** show a face-down card back (gold cross-hatch lattice + diamond crest); empty slots stay as the `?` placeholder.
- **The hole caption is the single read-out** — readable while the hole bank is selected (tap your cards), blurred whenever it isn't. "Peek" is just re-selecting your cards; there is no separate peek control.
- **The hole texture pill is omitted** (redundant with the caption text, and would leak the suits).

*(Transcript masking — the header still shows the hole cards in plain text, e.g. `Hand #1 - AJo - UTG` — is not yet implemented.)*

### Hand Shorthand Transcript

A running **shorthand text** of the hand renders in the gap below the strip (the same zone the picker uses — they never show at once). It unfolds line-by-line as you record, in Courier, and a **Copy** button puts the full multi-line text on the clipboard to paste into a poker chat.

- It is a **pure render of the action log** (computed like the seat visuals), so it tracks Undo/edits automatically and is never out of sync.
- Grammar (hero label, verb elision, check-around collapse, limp, bare board, showdown result) is defined in full in **`ShorthandReference.md`** — the authoritative source for both the card notation and the action shorthand.
- Example — header then one line per street (hero's position + cards live in the header only):
  ```
  Hand #1 - AJo - UTG
  Hero R. BTN call.
  Q53r. Hero chk. BTN 30%. Hero 2.2x. BTN call.
  Jh. Hero & BTN chk.
  5x. Hero 90%. BTN fold.
  ```

### Effective Stack

A single user-entered number — the shortest stack still in the hand by the flop — recorded **in lieu of** tracking every player's stack (way simpler, no per-seat stack entry). Always in **big blinds** (1–999), it trails the transcript header as `Nbb eff`:

```
Hand #1 - QJdd - MP - 50bb eff
```

- **Where:** an **"Eff" chip** sits beside the **HAND HISTORY** title in the transcript header. Empty it reads a faint dashed **`+ Eff`** (tap to add — same plus/empty-slot language as **+ New Hand** and the empty card frames); set it reads a solid gold **`50bb`**. Tapping it either way opens the input.
- **Input:** a **docked numeric keypad** (digits, `⌫`, `✓`) that slides up over the bottom section — the same dock/grab-handle pattern as the card picker, dismissed by the handle (tap / swipe down) or `✓`. Capped at 3 digits, no leading zero. The table above stays put and tappable. **Re-opening a set value shows it as a preview, but the first digit typed clears it and starts fresh** (same as typing a rank into a full card group); backspacing instead keeps the value and edits it in place.
- **It is hand metadata, like the cards** — *not* part of the action log: **untouched by Undo** (fix a wrong number in the keypad itself), and **blank every hand** (no carry-forward). It appears in the header the moment it's set, independent of cards/position (`Hand #1 - 50bb eff` even before the button is placed).
- **Availability:** the chip is reachable in every playing phase the transcript header shows (recording, showdown, hand-closed) — addable or editable at any time, like the rest of the app.
- Persisted to `Hand.effectiveStack` (stored as the BB count). See `ShorthandReference.md §4` for the header grammar.

### Villain Profiles *(not yet implemented)*

- Quick tags: OMC, LAG, TAG, Fish, Reg, Unknown
- Custom text descriptor (e.g. "middle aged guy with headphones")
- Running notes field — add reads throughout the session
- Villain profiles persist across all hands within a session
- Swipe left on a seat to bust/clear a player — hands already recorded retain original descriptor
- Villain hole cards entered via their seat tap (showdown only)
- Villain notes are session-only — do not persist to future sessions

### Supported Game Formats (v1.0)
- No-Limit Hold'em (NLHE) — Cash and Tournament
- PLO is out of scope for v1.0

---

## Session Management

- Sessions created and closed **manually** by the user — no auto-detection
- Two session types: **Cash Session** (optional stack size) and **Tournament** (name + buy-in)
- A session is a container for the hands worth studying — not every hand
- Typical session: 8–12 logged hands across several hours of play

---

## Pro Marketplace *(not yet implemented)*

### Creator Model
- **Open marketplace** — no application, no credential review, no minimum following
- Any user can self-serve upgrade to a Pro account
- **Verified badge** awarded when a pro links their Twitter/X account (identity confirmation only, not a gatekeep)
- Unverified pros can still publish and sell — they just don't carry the badge

### Content Types
- **Monthly subscription** — minimum $9.99/month, pro sets their own price above that
- **À la carte** — individual session or tournament run purchases (minimums TBD)
- Pros can use the tap UI (live recording) or text entry (writing up sessions after the fact)
- Pros can attach written commentary to individual hands

### Pro Profile Structure
1. **Subscribe CTA** — price visible immediately, one tap to subscribe. No content preview before subscribing.
2. **Live** — active tournament hand histories posted in real-time. Push notifications to subscribers.
3. **Past** — completed tournament runs and cash sessions. Each tournament shows final placement.

### Revenue Split Example
- Subscriber pays $20/month
- Apple takes $6 (30%)
- Aeches takes $1.40 (10% of remainder)
- Pro receives $12.60
- Full fee transparency shown in every pro's creator dashboard

### Content Protection
- Hand histories displayed in-app only — no exports, no downloads
- Watermark with subscriber username on all content

---

## Onboarding & Auth

- **No walkthrough, no marketing interstitial**
- iOS launch screen shows the HH logo briefly while the app loads (system-level, unavoidable)
- First screen in-app is the **Login screen** — logo, tagline, and three auth buttons
- Sign in with Apple (required), Sign in with Google, Email + Password
- All accounts require email verification and phone number
- After authentication → lands on Record tab → New Session screen

---

## Notifications *(not yet implemented)*

- Push notifications on by default for all subscribed pros
- User can configure per-pro from the pro's profile page
- **New hand posted** — standard notification (cash session or completed tournament)
- **Live tournament update** — distinct higher-urgency style, real-time follow-along feel
- **Subscriber milestone** — pro-facing only (internal)

---

## User Roles

- **Standard User** — records hands, browses marketplace, subscribes to pros
- **Pro Creator** — all of the above + publishes hand histories, sets pricing, earns revenue
- All roles share the same tab bar — pro features unlock within Profile tab

---

## MVP v1.0 Scope

### Implemented
- Full hand recording engine — `HandEntryView.swift`
- Geometric table oval with gold rail, felt, gap at dealer station, 6/8/9/10-seat support
- Session-locked hero seat, per-hand dealer button placement
- Empty seats — an **Edit Seats** toggle at place-button marks seats with no player (dashed empty rings); the hand plays and labels positions as a shorter-handed game (occupied seats only). Persists across hands as table composition; hero's seat protected, ≥2 seats kept (see Empty Seats)
- Position labels anchored both ends — UTG always first-to-act, LJ/HJ/CO button-relative, MP/MP+1 the middle filler (6→10-handed); computed over occupied seats so empties renumber the ring
- Phase system: selectSeat → placingButton → recordingHand → showdown → handClosed
- Two-row Control Bar (bottom, thumb zone): a slim utility row (Undo · Next Street) above a full-width primary action row — Fold/Call/Raise (bet context) or Check/Bet (no bet)
- Unified committed-input model — action buttons and swipes share one settle path (`settleAfterCommit`): record the action, then advance the ring to the next player with no seeded action; a closing action holds and lights Next Street
- Direct seat tap routing — two separate models: preflop is navigation (tap = jump the action to that seat, folding seats skipped, landing the destination at its default), post-flop is two contexts (no bet = auto-check jump mirroring preflop; bet exists = commit the seat on the clock and advance to the next owing seat). Hero seat is fully participatory; resolved/folded seats no-op; a re-aggression guard forces the highlighted seat to respond before any other tap registers. Highlighted seat cycles in place in both, looping forever with no blank state.
- Prior-action badges — a seat displays its earlier actions this street as small colored pills (up to 3 slots + "+N" overflow), distinct from its current center action. The on-clock seat that owes a fresh response to new aggression (acted earlier, now faces a 3-bet/bet) shows an **empty** center with its earlier action demoted to a pill, until it acts
- Undo button (`↺`, left of the utility row): undoes one action, crosses street boundaries, strips system-generated auto-action batches in a single press; re-homes an "ahead" cue (an empty waiting seat, or a decisive close where the cue is on the Next Street button) to the last actor before deleting; reversible at hand close (re-opens a showdown overlay; peels a fold-out; after a Skip, restores recording to the exact point without peeling any action — hand state was never cleared)
- Pulse cue: exactly one seat pulses (the seat on the clock); a committed close hands the pulse to the Next Street button while the acted seat goes plain
- Street close detection: preflop BB-last rule (limped and raised pots), post-flop check-around, raise-then-respond
- Preflop fast-forward: Next Street button activates when 2+ committed players, a raise exists, and no committed player faces unresolved aggression — button auto-folds remaining seats and advances to flop
- Next Street / End Hand button (right of the Control Bar): the only control that advances a street; active on street close or preflop fast-forward; commits fold-out on pending fold
- Fold-out detection (last player standing wins, hand closes immediately)
- Showdown overlay (Win / Lose / Chop) triggered on river close with 2+ players
- **Skip** and **Move** corner overlay buttons on the table oval — Skip (mid-hand only) freezes the hand like a close: saves it incomplete, "SKIPPED" on the felt, stays on the same number, state preserved so Undo reopens recording. Move ("next hand, new seat") is shown only at `handClosed`/`placingButton` and returns to seat selection (advancing the number from a closed hand). The two split *end this hand* (Skip) from *where the next hand starts* (New Hand same-seat / Move new-seat)
- Hand outcome summary state — table stays **frozen** on the finished hand (seat actions, positions, dealer button all remain); outcome rendered as felt text in the center; card strip + transcript remain editable, with empty card slots for reached streets gold-bordered as an "enter now" cue; **New Hand** button (gold, right of Undo) is the clean break that advances the hand number and returns to the place-button screen — tapping a seat on the closed table is a no-op
- `handNumber` single source of truth — advances only when the next hand is dealt (tap a seat from the closed state)
- Per-street card picker — docks in the gap below the strip (strip slots are the frames and the live preview); per-street `CardGroup`/`CardFrame` with one suit mode each — **bound** (`AdJx`, suit on the face), **footnote** (`AJdx`, unassigned suit letters in a caption), **relationship** (`suited`/`offsuit`/`rainbow`/`mono`/`two tone`). Left-to-right entry, explicit `x` as a first-class card state, mutually-exclusive suit/shortcut gating (pairs disable `s`/`o`), type-a-rank-clears-a-full-group, slim grab handle to dismiss, and a Next (`›`) control that advances bank-to-bank
- On-card suit display — uniform-footnote faces colored; a group **texture pill** straddles the card row for partial footnote (glyph set) or relationship (word). Glyph = a real suit; word = a texture (see Card Entry)
- Duplicate-card block — a suit button disables when binding it would recreate a fully-specified card already in the hand (bound-only; spans hole/flop/turn/river)
- Turn/river **board-suit count** — repeat the suit to mark flush draws/completions (`4ss` / `4sss`), via suit re-tap or the suit-skinned pip-layout `×N` buttons (turn `2–4`, river `3–5`)
- **Incognito mode** — session toggle (eye by the HOLE label) hides the hero's hole faces behind a card back and blurs the hole read-out; board cards stay public (see Incognito Mode)
- Hand shorthand transcript — running Courier text of the hand in the same gap, a pure render of the action log with a Copy-to-clipboard button; grammar in `ShorthandReference.md`
- Effective stack — an "Eff" chip beside the transcript title (faint `+ Eff` when empty, gold `Nbb` when set) opens a docked numeric keypad; trails the header as `Nbb eff` (always big blinds, ≤999). Hand metadata like the cards: Undo-independent, blank every hand, persisted to `Hand.effectiveStack`
- Aggression symbols: → = post-flop bet; raise pip-layouts: ↑↑ side-by-side (2-bet), triangle (3-bet), 2×2 grid (4-bet), ↑ + badge number (5-bet+)
- Bet/raise sizing via Raise/Bet button hold — a 0.3s hold reveals a horizontally-scrolling, color-coded sizing chip strip in the utility row to the right of Undo (Next Street is hidden during sizing to give the chips full width; the action row never moves); tapping a chip records the sized action and advances. Quick taps and swipes stay unsized; Undo peels a staged raise in one press. Size shows as a pill on the seat's bottom rim (see `SizingOverhaul.md`)
- All-in flow — an all-in (Bet/Raise sized `All-in`, or a **call** marked all-in via a Call-button hold) marks the seat with a persistent amber `ALL IN` badge and skips it from all further betting. The hand keeps playing only while ≥2 players have chips; when ≤1 does, it enters **run-out** (action row hidden, felt reads `ALL IN`) and the pulsing **Showdown** button jumps straight to the Win/Lose/Chop overlay — no street-by-street walk, since the hand is decided. The run-out board is entered in the always-live card strip, before or after picking the result. No chip/pot math — the user marks each all-in and a count drives continue-vs-run-out (see `AllInFlow.md`)
- New Session screen (Cash / Tournament)
- Login screen (auth buttons wired to state, full auth not yet implemented)

### Remaining for v1.0
- Villain profiles with session persistence and swipe-to-bust
- Villain hole cards entered via seat tap (showdown)
- Full auth: Sign in with Apple, Google, Email + Password
- Personal hand history screen (History tab)
- Pro profiles with Live and Past sections
- Open self-serve Pro marketplace
- Twitter/X verification + verified badge
- Marketplace browse and search
- Monthly subscription via App Store IAP ($9.99 minimum)
- À la carte session/tournament purchase
- Subscriber reading feed with expand-to-detail
- Pro commentary on individual hands
- Watermark content protection
- Push notifications with per-pro controls
- Full fee transparency in creator dashboard
- Cloud sync for hand histories (offline-first, sync in background)
- Chance Kornuth and Alex Foxen as founding pro accounts

### Out of Scope for v1.0
- PLO support
- Android or web app
- Cross-session villain profiles
- Solver / GTO integrations
- Pro analytics dashboard
- Social features (comments, reactions)
- Advanced hand history search and filtering

---

## Technical Constraints

- **Platform:** iOS only, SwiftUI
- **Language:** Swift
- **Bundle ID:** com.airdrummin.Aeches
- **Architecture:** All hand recording state is local to `HandEntryView` and its child components. No `@EnvironmentObject` or observable context layer.
- **Offline-first:** All recording works without network. Sync is background/silent.
- **In-app purchases:** App Store IAP for subscriptions and à la carte purchases
- **Storage:** Cloud sync for hand histories (provider TBD — likely Firebase or CloudKit). In-memory only during development.
- **Privacy:** Standard user hand histories are always private. Pro content visible to paying subscribers only.

### Known Limitations / Future Cleanup
- **`isAutoFolded` naming.** The `isAutoFolded: Bool` flag on `Action` is the batch-rewind marker for *all* system-generated actions — preflop auto-folds (`preflopJump`) and post-flop auto-checks (`postflopJump`). The name is misleading for the check case; rename to `isAutoAction` in a future pass.
- **Two position-label paths diverge as players fold.** Table display labels (`seatPositions`) are computed over all seats (`Array(0..<tableSize)`), while labels frozen onto `Action` records (`positionFor(seat:)`) use `activeSeatSequence` (active only). These drift apart once seats fold; reconcile in a future pass.
- **Seat gestures are deliberately one `DragGesture`.** Tap and swipe are classified inside a single `DragGesture(minimumDistance: 0)` in `SeatSelectionView.swift` — do **not** split them into `.onTapGesture` + `.simultaneousGesture` + `.highPriorityGesture`. SwiftUI's arbitration between layered recognizers is fragile (iOS 18 worsens it) and a shared mute-flag gets stuck. See the comment on that gesture for the full rationale. (Sizing is no longer a seat gesture — it lives on the Raise/Bet control-bar buttons, which use the same single-`DragGesture` tap-vs-hold pattern; see `SizingOverhaul.md`.)
- **Card entry is lossy on save.** The live `CardGroup`/`CardFrame` suit modes (bound/footnote/relationship, explicit `x`) are the faithful artifact only *while recording* — the shorthand transcript renders them in full. On save, `buildHeroCards()` collapses to per-card `Card.suit` (so footnote/relationship distinctions are lost), and board cards (flop/turn/river groups) are not persisted at all. Reconcile when cloud sync / the History screen lands.

---

## File Structure (key files)

| File | Purpose |
|---|---|
| `Aeches/HandEntryView.swift` | Full hand recording engine, two-row Control Bar (Undo · actions · Next Street), per-street card picker, shorthand transcript, all phase logic |
| `Aeches/SeatSelectionView.swift` | Shared components only: `TableOvalView`, `SeatButtonView`, `SeatState`, `seatPosition()` |
| `Aeches/Models.swift` | All data models and enums. `calculatePositions()` + `positionLabels(for:)` are the single source of truth for position labels (the only thing here intended to change — and only the label convention). Otherwise treat as stable. |
| `Aeches/ContentView.swift` | Tab bar, `RecordTab`, design tokens (`Color` extensions) |
| `Aeches/NewSessionView.swift` | Session creation screen |
| `Aeches/LoginView.swift` | Auth screen |
| `Aeches/AechesApp.swift` | App entry point, auth gate |

---

## Data Model

All named models carry a `UUID` and conform to `Codable`. Data is in-memory only during development — no backend is wired until cloud sync is implemented. All models are pure Swift structs/enums.

### Enums

**`Suit`**
`.spades` `.hearts` `.diamonds` `.clubs`
Suit is always `Suit?` on a card — `nil` means the suit was not recorded.

**`Rank`**
`.ace .king .queen .jack .ten .nine .eight .seven .six .five .four .three .two`

**`ActionType`**
`.fold .check .call .open .raise`
A preflop call with no raise in front (a "limp") is stored as `.call` — the display layer may label it "Limp" contextually.

**`VillainTag`**
`.omc .lag .tag .fish .reg .unknown`

**`StreetName`**
`.preflop .flop .turn .river`
Extension `next()` on `StreetName` is defined in `HandEntryView.swift`.

**`Outcome`**
`.win .lose .chop`

**`PotUnit`**
`.bigBlinds .dollars .chips`
`.dollars` — cash game sessions, renders with `$` prefix.
`.chips` — tournament sessions, renders as a plain number.
Set automatically from session type — the user never chooses directly.

**`SizingType`**
`.multiple` — e.g. 2x, 2.5x
`.potFraction` — e.g. ½ pot, pot
`.bigBlinds` — flat BB amount
`.dollars` — flat dollar amount (cash games)
`.chips` — flat chip amount (tournaments)

**`SessionType`**
`.cash` `.tournament`

---

### Card
```
id:    UUID
rank:  Rank
suit:  Suit?        // nil = unknown
```

### RaiseSizing
```
type:   SizingType
value:  Double?     // nil for named presets like "Pot"
label:  String      // display string e.g. "2x", "2.5x", "50%", "Pot", "All-in"
```

`RaiseSizing` is attached to `.open`/`.raise` actions sized via the Raise/Bet button hold (see Hold-to-size), and to a `.call` marked `All-in` via the Call-button hold (the all-in marker — see All-in flow). It is `nil` on unsized actions (quick taps, swipes, and ordinary calls/checks/folds).

### Action
```
id:         UUID
seatIndex:  Int           // 0-based seat index
position:   String        // frozen label e.g. "BTN", "UTG" — calculated at record time
actionType: ActionType
sizing:     RaiseSizing?  // sized .open/.raise, or a .call marked All-in; nil otherwise
```

### Street
```
id:         UUID
name:       StreetName
boardCards: [Card]        // empty for preflop, 3 for flop, 1 for turn/river
actions:    [Action]
```

### Villain
```
id:          UUID
seatIndex:   Int
tag:         VillainTag?
descriptor:  String?      // e.g. "middle aged guy with headphones"
notes:       String?      // running reads, updated during session
isActive:    Bool         // false = busted out or left the table
```

### Hand
```
id:               UUID
sessionId:        UUID
handNumber:       Int
title:            String?
timestamp:        Date
heroSeatIndex:    Int
buttonSeatIndex:  Int
activeSeatIndices: [Int]  // occupied seats this hand — drives position label calculation
holeCards:        [Card]  // hero's hole cards, 0–2
streets:          [Street] // only streets that were played
outcome:          Outcome? // nil if hand abandoned or outcome not recorded
potSize:          Double?
potUnit:          PotUnit?
effectiveStack:   Double?  // optional — the hand entry UI records this in big blinds (shortest stack by the flop)
commentary:       String?
```

### Session
```
id:            UUID
type:          SessionType
name:          String        // cash game name or tournament name
date:          Date
tableSize:     Int           // 6, 8, 9, or 10 — fixed for the session
heroSeatIndex: Int           // locked for the session
stakes:        String?       // cash only e.g. "2/5"
buyIn:         Double?       // tournament only
bullet:        Int?          // tournament only — rebuy count
startingStack: Double?       // cash only, optional
villains:      [Villain]     // session-scoped, keyed by seatIndex
hands:         [Hand]
startedAt:     Date
endedAt:       Date?
```

---

### Position Label Calculation

Position labels (BTN, SB, BB, UTG, etc.) are calculated at hand record time from:
- `buttonSeatIndex` on the hand
- `activeSeatIndices` on the hand

Labels are assigned based on the **occupied seat count only** — empty/unoccupied seats are skipped entirely and do not consume a position slot. A 6-occupied game gets exactly 6 labels (UTG, HJ, CO, BTN, SB, BB); a 9-occupied game gets `UTG, UTG+1, MP, LJ, HJ, CO, BTN, SB, BB`. The convention anchors UTG (first-to-act) and the button-relative late seats (LJ/HJ/CO + blinds/button), with MP/MP+1 the middle filler — see `PokerActionReference.md` "Positions by Table Size" for the full ladder. Labels are stored frozen on each `Action` at the moment of recording.

`calculatePositions(buttonSeatIndex:activeSeatIndices:)` (with `positionLabels(for:)`) is a free function in `Models.swift` and is the single source of truth for all position label logic. The hand-entry UI passes it the **occupied** seats (all seats minus the empty set).
