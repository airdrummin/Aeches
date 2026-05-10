# Aeches — AI Development Reference

This file is the authoritative briefing for any AI assistant working on the Aeches iOS app.
Read this before writing any code, designing any view, or making any architectural decision.

---

## What Aeches Is

Aeches is an iOS-only app built around two tightly coupled pillars:

1. **A hand history recorder** — a tap, swipe, and hold-based UI that lets poker players document hands faster than any existing solution. Zero typing required for a standard hand. Designed for one thumb, mid-session at a live table.

2. **A pro content marketplace** — poker professionals sell access to their hand histories via monthly subscriptions or à la carte session purchases, including live tournament runs.

**Recording is always free.** Aeches monetizes exclusively through a 10% platform fee on marketplace transactions (taken after Apple's 30% App Store cut).

**Founding pros:** Chance Kornuth and Alex Foxen — equity partners and early adopters.

---

## Design System

### Colors
- Background: near-black (e.g. `#0A0A0A` or `#111111`)
- Primary accent: gold (e.g. `#C9A84C` or `#D4AF37`)
- Secondary text: muted gray
- Surface/card: dark gray (e.g. `#1A1A1A` or `#1C1C1E`)
- Error/fold: subtle red
- Success/win: subtle green

**Dark mode is the default and only mode for v1.0.**

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

---

## Core Feature: Hand Entry UI

### Screen Architecture
The hand entry screen is a single persistent view split into two independently operating halves. The screen never navigates away during a hand — everything happens in place.

**Top half — Table**
A geometric oval poker table with gold leather rail, felt surface, and numbered seat buttons. Used to record all table action: dealer button placement, seat actions (fold/call/raise), and villain interaction. The table stays visible at all times.

**Bottom half — Cards**
A persistent strip showing all 7 card slots at once:
- Hero hole cards: 2 slots
- Flop: 3 slots
- Turn: 1 slot
- River: 1 slot

Both halves operate independently. The user can fill in cards before recording action, record action without entering cards, or interleave them freely. There is no prescribed order.

### Screen Flow (within Record tab)
1. **Session creation** — select Cash Game or Tournament, fill in details
2. **Hand entry screen** loads — table visible, card strip visible
3. **Phase 1: Select seat** — tap any seat to lock in as hero (YOU). Seat stays locked for the entire session.
4. **Phase 2: Place dealer button** — tap any seat to place the D button for this hand
5. **Phase 3: Recording** — both halves active. Record in any order:
   - Tap seats to record action (cycles: call → raise → fold → clear)
   - Tap card slots to enter hole cards, flop, turn, river
6. **Save Hand** — hand saved, table resets for Hand #2. Hero seat remains locked.

### Table Design
- Gold leather rail with a clean gap at 12 o'clock for the house dealer station
- DEALER label sits centered in the gap
- Green felt surface with radial gradient and stitching ring
- HH monogram watermark on felt
- Supports 6, 8, 9, and 10-seat configurations — set at session start, displayed with a size picker
- Seat buttons show action state visually: gold for aggressor, green for call, red for fold

### Card Entry
- Tap any card slot → rank grid appears in-line (A K Q J T 9 8 7 6 5 4 3 2)
- Tap a rank → suit options appear (♠ ♥ ♦ ♣ + unknown)
- Suit is always optional — tap "?" to record rank only
- For hole cards, `s` (suited) and `o` (offsuit) shortcuts available after first rank
- Accepted notation formats: `AK`, `AKo`, `AKs`, `AhKs`, `AxKs`
- After entering a card, picker auto-advances to the next empty slot
- Tap "Clear" to remove a card, "Done" to dismiss picker

### Villain Profiles
- Quick tags: OMC, LAG, TAG, Fish, Reg, Unknown
- Custom text descriptor (e.g. "middle aged guy with headphones")
- Running notes field — add reads throughout the session
- Villain profiles persist across all hands within a session
- Swipe left on a seat to bust/clear a player — hands already recorded retain original descriptor
- Villain hole cards entered via their seat (showdown only)
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

## Pro Marketplace

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

## Notifications

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

### In Scope
- Unified hand entry screen — table top half, card strip bottom half, both independent
- Geometric table oval with gold rail, felt, gap at dealer station, 6/8/9/10-seat support
- Session-locked hero seat, per-hand dealer button placement
- Tap-to-cycle seat actions (call / raise / fold)
- Inline card picker — rank then suit, suit optional, auto-advances to next empty slot
- Suited/offsuit shortcuts for hole cards
- Flexible hole card notation: AK, AKo, AKs, AhKs, AxKs
- Villain profiles with session persistence and swipe-to-bust
- Villain hole cards entered via seat tap (showdown only)
- Manual session creation (Cash + Tournament)
- Optional stack size per hand
- Single commentary field per hand
- Personal hand history (local + cloud sync, offline-first)
- Login screen with Sign in with Apple, Google, Email + Password
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
- Chance Kornuth and Alex Foxen as founding pro accounts
- iOS only

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
- **Offline-first:** All recording works without network. Sync is background/silent.
- **In-app purchases:** App Store IAP for subscriptions and à la carte purchases
- **Storage:** Cloud sync for hand histories (provider TBD — likely Firebase or CloudKit)
- **Privacy:** Standard user hand histories are always private. Pro content visible to paying subscribers only. No public browsing of hand history content.

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
`.omC .lag .tag .fish .reg .unknown`

**`StreetName`**
`.preflop .flop .turn .river`

**`Outcome`**
`.win .lose .chop`

**`PotUnit`**
`.bigBlinds .dollars .chips`
`.dollars` — used in cash game sessions, always renders with `$` prefix.
`.chips` — used in tournament sessions, renders as a plain number (no `$`).
The app sets `.dollars` or `.chips` automatically based on session type — the user never chooses.

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

### Action
```
id:         UUID
seatIndex:  Int           // 0-based seat index
position:   String        // frozen label e.g. "BTN", "UTG" — calculated at record time
actionType: ActionType
sizing:     RaiseSizing?  // nil unless action is open/raise
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
notes:       String?      // running reads added during session
isActive:    Bool         // false = busted out or left the table
```

### Hand
```
id:              UUID
sessionId:       UUID
handNumber:      Int
title:           String?
timestamp:       Date
heroSeatIndex:   Int
buttonSeatIndex: Int
activeSeatIndices: [Int]  // which seats were occupied this hand
holeCards:       [Card]   // hero's hole cards, 0-2 cards
streets:         [Street] // preflop through river, only streets that were played
outcome:         Outcome?
potSize:         Double?
potUnit:         PotUnit?
effectiveStack:  Double?  // optional, in same unit as potUnit
commentary:      String?
```

### Villain (session-level)
Villains are stored on the Session, not on individual hands. Each hand references villain info via seatIndex. Villain notes persist for the life of the session only — not across sessions.

### Session
```
id:          UUID
type:        SessionType
name:        String        // cash game name or tournament name
date:        Date
tableSize:   Int           // 6, 8, 9, or 10 — fixed for the session
heroSeatIndex: Int         // locked for the session
stakes:      String?       // cash only e.g. "2/5"
buyIn:       Double?       // tournament only
bullet:      Int?          // tournament only — rebuy count
startingStack: Double?     // cash only, optional
villains:    [Villain]     // keyed to seat indices, session-scoped
hands:       [Hand]
startedAt:   Date
endedAt:     Date?
```

---

### Position Label Calculation

Position labels (BTN, SB, BB, UTG, etc.) are calculated at hand record time from:
- `buttonSeatIndex` on the hand
- `activeSeatIndices` on the hand

Labels are assigned based on the **active seat count only** — empty seats are skipped entirely and do not consume a position slot. A 6-handed active game gets exactly 6 labels (BTN, SB, BB, UTG, HJ, CO). A 9-handed game gets the full set. Labels are stored frozen on each `Action` at the moment of recording.
