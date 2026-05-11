# AECHES
## Poker Table Flow — Interaction Design Specification
*For Cursor / SwiftUI Development*

---

## 1. Screen Layout

The hand entry screen is a single persistent view. It never navigates away during a hand. All interaction happens in place, top to bottom:

| Zone | Description |
|------|-------------|
| **Zone 1 — Header** | Hand number, phase indicator, status text (e.g. 'Dealer: Seat 4 · Record action or fill in cards') |
| **Zone 2 — Table** | Oval poker table with gold rail, seat buttons, dealer button, HH watermark. Always visible. |
| **Zone 3 — Card Strip** | 7 persistent card slots: 2 hole cards, 3 flop, 1 turn, 1 river. Always visible. |
| **Zone 4 — Action Controller** | Back arrow │ action buttons │ forward arrow. Context-aware. Sits just above the tab bar. |
| **Zone 5 — Tab Bar** | Record · History · Marketplace · Profile (system nav, always present) |

Zones 2 and 3 operate independently — the user can fill in cards at any time without affecting action recording, and vice versa.

---

## 2. Session & Hand Setup Flow

### 2.1 Session Creation

Before any hand is recorded, the user creates a session. This is a one-time setup per session.

- **Cash Game or Tournament** — User selects session type
- **Cash Game fields:** Name (e.g. 'Aria 2/5'), Stakes (e.g. '2/5'), optional Starting Stack
- **Tournament fields:** Tournament name, Buy-in amount, Bullet count (rebuy tracking)
- **Table size picker:** 6 / 8 / 9 / 10 seats — fixed for the entire session
- Session is created → user lands on the Hand Entry screen

### 2.2 Phase 1 — Hero Seat Selection (First Hand Only)

On the very first hand of a session, the user must select their seat. This locks in for the entire session.

- All seat buttons are tappable and pulsing/highlighted to prompt selection
- User taps their seat → seat locks as 'YOU' with a persistent label
- Hero seat cannot be changed mid-session
- Hero seat is stored on the Session model as `heroSeatIndex`

### 2.3 Phase 2 — Dealer Button Placement (Every Hand)

At the start of every hand, the user must confirm the dealer button seat.

- App auto-suggests the next seat clockwise from the previous hand's button
- Suggested seat is highlighted — user taps to confirm or taps a different seat to override
- Dealer button (D badge) appears on the confirmed seat
- `buttonSeatIndex` is stored on the Hand model
- Once confirmed, app auto-calculates position labels (BTN, SB, BB, UTG, HJ, CO) based on active seats
- UTG seat auto-highlights immediately → Phase 3 begins

---

## 3. Gesture System

Two input methods are always available and always in sync. Power users use direct seat taps; the Action Controller guides sequential play.

### 3.1 Direct Seat Tap — Tap-to-Cycle

Applies to all seats, all streets. Tap a seat repeatedly to cycle through actions:

| Tap | Action |
|-----|--------|
| 1st tap | Call ✓ (green checkmark) |
| 2nd tap | Raise ↑↑ (gold up-arrows — count reflects bet level) |
| 3rd tap | Fold ✗ (red X) |
| 4th tap | Loops back to Call |

**Swipe left on any seat** = clear that seat back to neutral (no action recorded).

### 3.2 Action Controller — Bottom Bar

Persistent bar just above the tab bar. Contains:

| Element | Behavior |
|---------|----------|
| **← Back Arrow** | Undo last action. Steps back one seat in the action sequence. |
| **Action Buttons** | Context-aware buttons for the currently highlighted seat (see Section 5). |
| **→ Forward Arrow** | Preflop only: advance to next seat, auto-folding skipped seats. |

The controller always reflects the currently highlighted seat. Tapping a seat on the table updates the controller. Using the controller updates the table. They are the same state.

---

## 4. Raise Arrow Visual System

The number of arrows on a seat button indicates the current aggression level — the bet count at the time that seat raised. This is calculated dynamically based on the action sequence on the current street.

| Bet Level | Visual | Poker Term |
|-----------|--------|------------|
| 2-bet | ↑↑ (two arrows) | First raise / open raise |
| 3-bet | ↑↑↑ (three arrows) | Re-raise |
| 4-bet | ↑↑↑↑ (four arrows) | 4-bet |
| 5-bet+ | ↑ (one bold/strong arrow) | 5-bet or higher — simplified for space |

The arrow count is set at the moment the seat's action is recorded. It does not change retroactively. If a seat 3-bets, they get 3 arrows; if the original raiser then 4-bets back, they get 4 arrows.

---

## 5. Preflop Action Flow

### 5.1 Opening State

- UTG seat auto-highlights immediately after dealer button is confirmed
- Action Controller shows preflop options: `[ Fold ] [ Call ] [ Raise ]`
- No bet is yet open — but preflop is unique: the BB is a forced bet, so UTG always faces a bet
- All seats start neutral (no action state)

### 5.2 Auto-Fold Logic — Skipped Seats

When a user taps a seat or advances via the controller, any seats that were skipped in position order are automatically assigned a Fold (red X). The app infers they folded because they took no action.

> **Auto-Fold Rule:**
> When seat X acts, every seat between the previous acting seat and seat X (in clockwise position order) is auto-folded.
>
> **Example:** Button is Seat 4. UTG = Seat 7. If user taps Seat 2 first (a raise), Seats 7, 8, 9, 1 are auto-folded.
> Then if user taps Seat 4 (a call), Seat 3 is auto-folded (it was between Seat 2 and Seat 4).

### 5.3 Action Sequence — Step by Step

Example: 9-handed, Button on Seat 4. UTG = Seat 7.

| Step | Action |
|------|--------|
| **Step 1** | UTG (Seat 7) auto-highlights. User taps Seat 2 directly → Seats 7, 8, 9, 1 auto-fold. Seat 2 = Raise (↑↑). |
| **Step 2** | User taps Seat 4 → Seat 3 auto-folds (between Seat 2 and Seat 4). Seat 4 = Call (✓). |
| **Step 3** | User taps Seat 2 again → Seats 5, 6 auto-fold. Action is back on Seat 2 — raiser faced a caller, no re-raise. Street closes. Move to flop. |

### 5.4 Street Close Detection — Preflop

The system closes the preflop street when the last aggressor has no unresolved action facing them.

- If no raise: street closes when action returns to BB (they may check or raise)
- If raise: street closes when action returns to the raiser and everyone else has called or folded
- If re-raise (3-bet, 4-bet etc.): street closes when action returns to the last aggressor and all others have responded

The app tracks this automatically. Tapping the raiser's seat again when action is closed = confirm street end, not a new action.

### 5.5 Facing a Re-raise — Action Must Be Recorded

If Seat 2 raises (↑↑), Seat 4 re-raises (↑↑↑), and the user taps Seat 2 again — Seat 2 must act before the street can close. The tap enters Seat 2 into the cycle: Call → Raise → Fold. The street does not close until Seat 2's action is recorded.

### 5.6 Action Controller — Preflop

- **→ Forward:** advances to the next seat in clockwise order, auto-folding all seats in between
- **← Back:** undoes the last action and steps back one seat
- **Action buttons:** `[ Fold ] [ Call ] [ Raise ]` — applies to the currently highlighted seat

---

## 6. Post-Flop Action Flow (Flop, Turn, River)

### 6.1 Street Transition

- When preflop closes, the card strip flop slots become active (highlight/pulse)
- The table resets action states — all seats return to neutral
- First player to act post-flop is determined by position: first active seat left of the button
- That seat auto-highlights immediately

### 6.2 Post-Flop Action Options

Unlike preflop, post-flop has two starting states based on whether a bet is open:

**No Bet Open (first to act, or after a check):**
```
Action buttons: [ Check ]  [ Bet ]

Check = no chips committed. Action passes to next player.
Bet   = chips committed. All remaining players must respond.
```

**Facing a Bet:**
```
Action buttons: [ Fold ]  [ Call ]  [ Raise ]

Fold  = red X. Player is out of the hand.
Call  = green checkmark. Player matches the bet.
Raise = gold arrows. Bet level increments by 1.
```

The app switches between these two states automatically based on whether an open bet exists on the current street. The controller always shows the correct options.

### 6.3 Check-Then-Bet Scenario

Common post-flop scenario: player checks, then faces a bet from a later player.

| Step | Action |
|------|--------|
| **Step 1** | Seat 2 auto-highlights. User selects Check. Action moves to Seat 4. |
| **Step 2** | Seat 4 highlights. User selects Bet. A bet is now open on this street. |
| **Step 3** | App brings action back to Seat 2 — they now face a bet. Controller switches to `[ Fold ] [ Call ] [ Raise ]`. |
| **Step 4** | Seat 2 acts. If they call or fold, and no other players remain, street closes. |

### 6.4 Auto-Highlight Logic — Post-Flop

- First to act = first active (not folded) seat clockwise from the button (i.e. small blind position if still in, or next active seat)
- Auto-highlight moves clockwise through active seats
- Folded seats are skipped — they do not highlight
- When action comes back to a seat that already acted (e.g. check-then-bet scenario), that seat re-highlights

### 6.5 Action Controller — Post-Flop

Post-flop the forward arrow is removed. The controller shows only action buttons for the currently highlighted seat:

- No open bet: `[ Check ]  [ Bet ]`
- Bet open: `[ Fold ]  [ Call ]  [ Raise ]`
- **← Back arrow remains:** undoes last action, re-highlights previous seat

### 6.6 Direct Seat Tap — Post-Flop

Direct tap still works post-flop. Tap a seat to act on it. However:

- First tap on a seat = first action in the current context (Check if no bet, Call if bet open)
- Subsequent taps cycle through available options for that context
- Swipe left = clear that seat's post-flop action

---

## 7. Hand Close Logic

The system continuously monitors the number of active (not-folded) players. A hand closes under two conditions:

### 7.1 Fold-Out — One Player Remains

| | |
|--|--|
| **Detection** | System detects only 1 active player remaining after a fold action |
| **Behavior** | Hand auto-saves immediately. No user action required. |
| **Card Entry** | User may optionally enter any known cards (hero hole cards, board cards). Villain cards cannot be entered — they were never shown. |
| **CTA** | Button changes to `New Hand →` |
| **Villain Hole Cards** | **LOCKED.** Not available. Villain cards are only visible at showdown. |

### 7.2 Showdown — River Action Closes with 2+ Players

| | |
|--|--|
| **Detection** | River action closes (last bet called or check-check) with 2 or more active players |
| **Behavior** | `SHOWDOWN` prompt appears on screen |
| **Winner Selection** | User selects who won: Win / Lose / Chop (for hero), or tap the winning villain seat |
| **Villain Hole Cards** | **UNLOCKED.** User may tap each villain seat that went to showdown to enter their hole cards via the standard card picker. |
| **Auto-Save** | Hand saves after winner is selected and any optional cards are entered. |
| **CTA** | Button changes to `New Hand →` |

### 7.3 New Hand Flow

When the user taps `New Hand →`:

1. All seat action states clear (fold icons, call icons, raise arrows removed)
2. Card strip resets — all 7 slots return to empty
3. Dealer button advances one seat clockwise as the default suggestion
4. App prompts: 'Confirm button seat' — suggested seat is highlighted
5. User taps to confirm or taps a different seat to override
6. Hand number increments (Hand #2, Hand #3, etc.)
7. UTG auto-highlights → Phase 3 recording begins

---

## 8. Villain Profiles & Seat Management

### 8.1 Adding a Villain

- Long press on any non-hero seat → opens villain profile sheet
- Quick tag picker: `OMC / LAG / TAG / Fish / Reg / Unknown`
- Optional text descriptor field (e.g. 'middle aged guy with headphones')
- Optional running notes field — can be added to throughout the session
- Villain profiles persist across all hands within the session

### 8.2 Busting / Clearing a Villain

- Swipe left on a seat → 'Bust Player' option appears
- Confirming bust sets `isActive = false` on that villain
- Seat returns to neutral — available for a new player
- Hands already recorded retain the original villain descriptor — historical record is preserved

### 8.3 Villain Hole Cards (Showdown Only)

- Villain hole cards can **ONLY** be entered when the hand reached showdown
- After winner selection, user taps a villain's seat to open their card picker
- Same card picker flow as hero hole cards (rank → suit, suit optional)
- If hand ended by fold, villain seats are **locked** — no card entry

---

## 9. Card Strip

The card strip runs across the bottom of the table area and is always visible. It contains 7 slots:

| Slot | Contents |
|------|----------|
| **HOLE** | 2 slots — hero's hole cards |
| **FLOP** | 3 slots — community cards, flop |
| **TURN** | 1 slot — community card, turn |
| **RIVER** | 1 slot — community card, river |

### 9.1 Card Entry Flow

1. Tap any card slot → rank grid appears inline (`A K Q J T 9 8 7 6 5 4 3 2`)
2. Tap a rank → suit picker appears (`♠ ♥ ♦ ♣ + ?`)
3. Suit is optional — tap `?` to record rank only
4. For hole cards: after selecting first card's rank, `s` (suited) and `o` (offsuit) shortcuts appear
5. After entering a card, picker auto-advances to the next empty slot
6. Tap `Clear` on a slot to remove a card
7. Tap `Done` or tap outside to dismiss picker

### 9.2 Accepted Notation

| Notation | Meaning |
|----------|---------|
| `AK` | Ace-King, suit unknown |
| `AKo` | Ace-King offsuit |
| `AKs` | Ace-King suited |
| `AhKs` | Ace of hearts, King of spades |
| `AxKs` | Ace unknown suit, King of spades |

Cards can be entered at any time — before, during, or after action recording. There is no prescribed order.

---

## 10. Visual State Reference

Quick reference for all seat button states:

| State | Visual | Description |
|-------|--------|-------------|
| **Neutral** | Gray circle, seat number | No action recorded |
| **Hero** | Gold border, 'YOU' label | Session-locked hero seat |
| **Dealer** | D badge on seat | Button position for this hand |
| **Highlighted** | Pulsing ring / glow | Currently active — awaiting action |
| **Call** | Green checkmark ✓ | Player called |
| **Raise** | Gold arrows ↑↑ / ↑↑↑ etc. | Player raised — arrow count = bet level |
| **Fold** | Red X ✗ | Player folded (manual or auto) |
| **Check** | Dash or neutral with tick | Player checked (post-flop) |
| **Bet** | Gold arrows ↑↑ (first bet) | Player bet (post-flop opening bet) |

---

## 11. Data Model Mapping

How the interaction maps to the Swift data models defined in the README:

| Interaction | Data Model |
|-------------|------------|
| Seat tap (call) | `Action { actionType: .call, seatIndex: N, position: "BTN" }` — position frozen at record time |
| Seat tap (raise) | `Action { actionType: .raise, seatIndex: N, sizing: nil }` — no sizing in v1 flow |
| Seat tap (fold) | `Action { actionType: .fold, seatIndex: N }` |
| Auto-fold | `Action { actionType: .fold, seatIndex: N }` — generated programmatically |
| Check (post-flop) | `Action { actionType: .check, seatIndex: N }` |
| Bet (post-flop) | `Action { actionType: .open, seatIndex: N }` — first bet on a street |
| Street close | New `Street` object created, actions array begins fresh |
| Showdown | `Hand.outcome` set; villain `Card` objects created if entered |
| New Hand | New `Hand` object created; `Session.hands` array appended |

> **Note:** `RaiseSizing` is `nil` for all raise/bet actions in the initial flow. Sizing entry is a future enhancement that can be layered in without changing the core action recording model.

---

*Aeches — Poker Table Flow Specification | v1.0*
*iOS only · SwiftUI · com.airdrummin.Aeches*
