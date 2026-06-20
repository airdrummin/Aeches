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

3. **Place dealer button** — tap any seat to set the dealer for this hand. The first highlight (UTG, or BB in short-handed games) appears automatically. Phase transitions to Recording.

4. **Recording** — both halves are active simultaneously. Several input paths coexist:
   - **Action Controller Bar** (bottom bar): primary action input. Context-aware buttons:
     - Bet context (preflop, or any street with an open bet): **Fold / Call / Raise**
     - No-bet context (post-flop, no aggression yet): **Check / Bet**
     - Forward arrow (preflop only): folds the currently highlighted seat and advances to the next
   - **Rewind button** (gold capsule, top-left of table, always visible during recording): steps back one action at a time. System-generated auto-action batches (preflop auto-folds, post-flop auto-checks) are removed in a single press, and when a jump empties the street the highlight returns to that street's first-to-act seat (not the seat that was tapped). When the current street has no actions left, the next press reopens the previous street with its last actor highlighted and its actions intact — a further press then undoes within that street.
   - **Next Street / End Hand button** (top-right of table): active in two cases:
     - The current street is fully closed (all active players acted / responded to the last raise)
     - **Preflop fast-forward**: a raise exists on the street AND 2+ players have committed AND no committed player faces unresolved aggression. Clicking the button auto-folds every remaining unacted seat (marked as system-generated so Rewind removes them cleanly) and advances to the flop. Note: in a limped pot BB must act before the button goes live — BB always has the option.
   - **Direct seat tap** routing — preflop and post-flop are two separate models (dispatched on the current street). Tapping the **highlighted seat** cycles its action in place in both, looping forever with no blank state (bet context: Call → Raise → Fold → Call → …; no-bet: Check → Bet → Check → …); street-close never fires during cycling, and the only way to undo is the Rewind button. A **re-aggression guard** applies to both models: if the highlighted seat has already acted but now owes a response to new aggression, every tap on another seat is a no-op until that seat cycles its response. Beyond that:
     - **Preflop (navigation model)** — a tap moves the action *to* the tapped seat. The **hero seat is fully participatory** — functionally identical to any other active seat (the "HERO" label is cosmetic only). Tapping a **resolved or folded seat** is a no-op, and you cannot jump *past* a seat that has already acted this street (it must respond in sequence). Tapping **any other active seat** does a preflop jump: auto-folds the seat being left (if it never acted) and every active seat skipped clockwise, then records the tapped seat's default (a call/limp) and leaves it on the clock — this covers both never-acted seats and seats that owe again after a raise (e.g. UTG facing a 3-bet).
     - **Post-flop (two contexts, dispatched on whether a bet exists)** — a skipped seat checks, never folds (no fold-by-skipping post-flop). Tapping a **resolved or folded seat** is a no-op in both. **No bet yet:** a tap does a post-flop jump mirroring the preflop jump — auto-*checks* the seat on the clock (if unacted) and every unacted seat skipped clockwise, then lands the tapped seat at Check (tap again to cycle Check → Bet). **A bet exists:** strict order only — only the exact next seat that owes action can be tapped; it commits the seat on the clock (default Call) and lands the tapped seat at Call.
   - **Direct seat swipe** (decisive shortcut) — swipe a seat to record a specific action in one gesture, without cycling: **← Fold, ↑ Raise, → Bet, ↓ Call/Check** (resolved by context; a direction that's illegal in the current context is a no-op). A swipe follows the same routing as a tap but lands the swiped action directly instead of cycling to it. Crucially, **the highlight stays on the swiped seat** — a swipe never moves the action to the next player (doing so would force the app to guess and seed that next seat's action, committing a decision the user never made). The user advances by aiming the next gesture at the next seat, exactly as with taps. A swipe that *closes* a street stays on that seat and lights the Next Street button — it never auto-advances the street. (Implemented in `HandEntryView.swift` routing + `SeatSelectionView.swift` gestures.)
   - **Hold-to-size** (optional) — press and hold a seat, then slide, to attach a size to a bet/raise (`2.5x`, `40%`, `Pot`, `All-in`); a floating readout follows the thumb, snapping to the strip. Quick swipe = unsized; hold = sized. Sizes are relative notation only — no chip/pot math. Shown as a pill on the seat's bottom rim.
   - **Card strip** (bottom half): tap any slot to open the inline card picker. Rank grid first (A K Q J T 9 8 7 6 5 4 3 2), then suit (♠ ♥ ♦ ♣ + unknown). Suit is always optional. Picker auto-advances to next empty slot after each entry.

5. **Street progression** — a street is closed once all active players have acted / responded to the last raise. When the closing action is entered via the **Action Controller Bar**, the street advances automatically; when it is entered via a **seat tap**, the **Next Street button** lights up and the user taps to advance (seat taps never auto-advance). On advance, state resets for the next street (actions cleared, bet level reset, highlight moves to first active seat left of dealer). The Action Controller Bar label updates: Preflop → Flop → Turn → River.

6. **Hand close** — two paths:
   - **Fold-out**: when all but one player folds at any point, the hand closes immediately. No user action required.
   - **Showdown**: when the river closes with 2+ active players, a **Win / Lose / Chop** overlay appears centered on the table. Tap the outcome to close.

7. **Summary state** — the hand stays on its number (e.g. "Hand #2") with an outcome summary in the status line and a colored dot:
   - Green dot + "You win"
   - Red dot + "You lose"
   - Gold dot + "Chop"
   - Muted dot + "Seat X wins" (fold-out where hero already folded)
   The "New Hand →" button is now active in the Action Controller Bar.

8. **New Hand →** — tap to advance. Hand number increments to #3, state resets, phase returns to placing the dealer button. Hero seat stays locked for the session.

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
  - Gold pulsing ring: currently highlighted seat (action on them)
  - Green fill + HERO label: hero seat
  - Prior-action badges: small colored pills around the seat's upper edge showing that seat's earlier actions *this street*, distinct from its current center action (e.g. a player who raised then called a 3-bet shows a gold ↑↑ pill beside a green ✓ center). Up to 3 slots (upper-left, top, upper-right); 4+ collapses the oldest into a gray "+N". Symbols match the center: → bet, ↑↑ raise, ✓ call, — check, ✕ fold
  - Size pill: when a bet/raise was sized via hold-to-size, a small pill on the seat's *bottom* rim shows the notation (`2.5x`, `40%`, `Pot`, `All-in`). Clear of the top-edge prior-action badges; absent when no size was attached

### Card Entry

- Tap any card slot → rank grid appears (A K Q J T 9 8 7 6 5 4 3 2)
- Tap a rank → suit options appear (♠ ♥ ♦ ♣ + unknown ?)
- Suit is always optional — tap "?" to record rank only
- For hole cards, `s` (suited) and `o` (offsuit) shortcuts available after selecting the first rank
- Accepted notation formats: `AK`, `AKo`, `AKs`, `AhKs`, `AxKs`
- After entering a card, picker auto-advances to the next empty slot
- Tap "Clear" to remove a card, "Done" to dismiss picker

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
- Phase system: selectSeat → placingButton → recordingHand → showdown → handClosed
- Action Controller Bar: Fold/Call/Raise (bet context), Check/Bet (no bet), forward skip (preflop)
- Direct seat tap routing — two separate models: preflop is navigation (tap = jump the action to that seat, folding seats skipped), post-flop is two contexts (no bet = auto-check jump mirroring preflop; bet exists = commit the seat on the clock and advance to the next owing seat). Hero seat is fully participatory; resolved/folded seats no-op; a re-aggression guard forces the highlighted seat to respond before any other tap registers. Highlighted seat cycles in place in both, looping forever with no blank state.
- Prior-action badges — a seat displays its earlier actions this street as small colored pills (up to 3 slots + "+N" overflow), distinct from its current center action
- Rewind button (top-left of table, always visible during recording): undoes one action, crosses street boundaries, strips system-generated auto-action batches (preflop auto-folds, post-flop auto-checks) in a single press
- Street close detection: preflop BB-last rule (limped and raised pots), post-flop check-around, raise-then-respond
- Preflop fast-forward: Next Street button activates when 2+ committed players, a raise exists, and no committed player faces unresolved aggression — button auto-folds remaining seats and advances to flop
- Next Street / End Hand button (top-right of table): active on street close or preflop fast-forward; commits fold-out on pending fold
- Fold-out detection (last player standing wins, hand closes immediately)
- Showdown overlay (Win / Lose / Chop) triggered on river close with 2+ players
- Hand outcome summary state with colored status dot and descriptive text
- `handNumber` single source of truth — advances only on "New Hand →" tap
- Inline card picker — rank then suit, suit optional, auto-advances to next empty slot
- Suited/offsuit shortcuts for hole cards
- Aggression symbols: → = post-flop bet; raise pip-layouts: ↑↑ side-by-side (2-bet), triangle (3-bet), 2×2 grid (4-bet), ↑ + badge number (5-bet+)
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
- **Seat gestures are deliberately one `DragGesture`.** Tap/swipe/hold-to-size are all classified inside a single `DragGesture(minimumDistance: 0)` in `SeatSelectionView.swift` — do **not** split them into `.onTapGesture` + `.simultaneousGesture` + `.highPriorityGesture`. SwiftUI's arbitration between layered recognizers is fragile (iOS 18 worsens it) and a shared mute-flag gets stuck. See the comment on that gesture for the full rationale and tuning dials.

---

## File Structure (key files)

| File | Purpose |
|---|---|
| `Aeches/HandEntryView.swift` | Full hand recording engine, Action Controller Bar, card picker, all phase logic |
| `Aeches/SeatSelectionView.swift` | Shared components only: `TableOvalView`, `SeatButtonView`, `SeatState`, `seatPosition()` |
| `Aeches/Models.swift` | All data models and enums. `calculatePositions()` for position labels. Do not modify. |
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
label:  String      // display string e.g. "2x", "½ Pot", "14BB", "$120"
```

`RaiseSizing` is `nil` on all `Action` records in the current build. Sizing entry is a future enhancement.

### Action
```
id:         UUID
seatIndex:  Int           // 0-based seat index
position:   String        // frozen label e.g. "BTN", "UTG" — calculated at record time
actionType: ActionType
sizing:     RaiseSizing?  // nil in current build
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
effectiveStack:   Double?  // optional, in same unit as potUnit
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

Labels are assigned based on the **active seat count only** — empty seats are skipped entirely and do not consume a position slot. A 6-handed active game gets exactly 6 labels (BTN, SB, BB, UTG, HJ, CO). A 9-handed game gets the full set. Labels are stored frozen on each `Action` at the moment of recording.

`calculatePositions(buttonSeatIndex:activeSeatIndices:)` is a free function in `Models.swift` and is the single source of truth for all position label logic.
