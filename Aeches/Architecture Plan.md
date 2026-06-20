# Aeches — Architecture Plan

This file captures the original architecture and product plan for the Aeches iOS app.
For the current implemented state and behavior, `README.md` is the authoritative reference and
`PokerActionReference.md` is the source of truth for poker action logic.

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

### Table View
- A geometric oval poker table with a gold leather rail, green felt surface, and a gap at 12 o'clock for the house dealer station
- Numbered seat buttons around the rail; supports 6, 8, 9, and 10-seat configurations (set per session, adjustable on the seat-select screen)
- User selects their seat once per session — it stays locked
- At the start of each hand, the user taps one seat to set the dealer button; the first actor highlights automatically (UTG, or BB short-handed)
- The table stays visible at all times — the screen never navigates away during a hand

### Action Recording — Tap, Swipe & Hold
All action is recorded by direct touch on the table — tap, swipe, or hold — plus the action buttons. Every control lives in a **single Control Bar** pinned to the bottom (thumb zone) that morphs by phase; while recording it shows **Rewind** (left) · **action buttons** (middle) · **Next Street / End Hand** (right). Several input paths coexist:
- **Action buttons** (middle of the Control Bar): context-aware — Fold / Call / Raise in a bet context, Check / Bet with no bet. They act on the seat on the clock, then advance the ring to the next player. There is no forward arrow (Fold already folds-and-advances) and no separate back arrow (Rewind is the single undo).
- **Direct seat taps** (top half): preflop and post-flop are two distinct models.
  - Tapping the **highlighted seat** cycles its action in place, looping forever (bet: Call → Raise → Fold → …; no-bet: Check → Bet → …).
  - **Preflop (navigation model):** a tap moves the action *to* that seat, auto-folding everyone skipped clockwise and landing the tapped seat at a call/limp. The hero seat is fully participatory (the "HERO" label is cosmetic only).
  - **Post-flop (two contexts):** with no bet live, a tap auto-*checks* everyone skipped and lands the tapped seat at Check; with a bet live, only the next seat that owes action can be tapped — it commits the seat on the clock (default Call) and lands the tapped seat at Call. A skipped seat checks, never folds.
  - A **re-aggression guard** (both models) blocks taps on other seats while the highlighted seat owes a response to new aggression — it must act first.
- **Direct seat swipes** (decisive shortcut): swipe a seat to record a specific action in one gesture, without cycling — ← Fold, ↑ Raise, → Bet, ↓ Call/Check (by context; an illegal-for-context direction is a no-op). Landing the swiped action directly, a swipe then **advances the ring to the next player without seeding any action** — identical to an action-button press (both share one settle path). The next seat enters empty/waiting; tapping past it later auto-folds/-checks it. A swipe that closes a street holds on the seat and lights the Next Street button — only that button advances a street (no button, tap, or swipe ever does).
- **Hold-to-size** (optional): press-and-hold a seat then slide to attach a relative size to a bet/raise (`2.5x`, `40%`, `Pot`, `All-in`) via a floating readout; shown as a pill on the seat's bottom rim. Quick swipe = unsized; hold = sized. Notation only — no chip/pot math.
- **Rewind** (left of the Control Bar): steps back one action; removes system-generated auto-action batches in a single press; crosses street boundaries. Recording has two step kinds — a *cue-advance* (ring/pulse moves, no log entry) and an *action* (log entry); Rewind reverses a cue-advance before deleting. The cue sits "ahead of the log" either on an empty "waiting" seat (after a button/swipe advance) or on the Next Street button (after a decisive close) — in both cases the first Rewind returns it to the last actor (no delete) before subsequent presses delete. Reversible at hand close — re-opens a showdown overlay, or peels a fold-out.
- **Next Street / End Hand** (right of the Control Bar): the only control that advances a street; active when the street has closed, or via the preflop fast-forward path.
- **Dealing the next hand:** no New Hand button — from the closed state, tap any seat to place the dealer button there and deal the next hand (same gesture as hand #1's button placement).
- **Pulse cue:** exactly one seat pulses (the seat on the clock). A committed close (button/swipe) hands the pulse to the Next Street button and the acted seat goes plain; a tap-completed round leaves the seat pulsing and the button lit-but-calm.
- Seats render state visually — bet `→`, raise `↑↑` pips, call `✓`, check `—`, fold `✕`, gold pulsing ring = on the clock — plus prior-action badges (top edge) for earlier actions this street, and a size pill (bottom rim) when a bet/raise was sized.

Action ordering, street-close detection, fold-out, and showdown all follow `PokerActionReference.md`. The tap/swipe/hold interaction model is implemented in `HandEntryView.swift` (routing) and `SeatSelectionView.swift` (gestures). Flow is not forward-only — Rewind corrects mistakes, crossing back into earlier streets and reversing a closed hand.

### Hole Card Entry
- A single row of all 13 ranks: A K Q J T 9 8 7 6 5 4 3 2
- After tapping rank, suit options appear adjacent to the tap point (minimizing thumb travel)
- Shortcut options: `s` (suited) and `o` (offsuit) as one-tap alternatives to selecting exact suits
- Accepted formats: `AK`, `AKo`, `AKs`, `AKhh`, `AhKx`

### Hand Flow (street by street)
1. Hole cards (optional, entered any time)
2. Preflop action — clockwise from UTG, ending on BB
3. Flop (3 community cards + action — clockwise from the first active seat left of the button)
4. Turn (1 card + action)
5. River (1 card + action)
6. Showdown (Win / Lose / Chop) when the river closes with 2+ players — or an early fold-out the moment only one player remains

The table and card halves operate independently and can be filled in any order.

A standard hand: under 20 seconds. A contested multi-street hand with showdown: under 45 seconds.

### Villain Profiles
- Quick tags: OMC, LAG, TAG, Fish, Reg, Unknown
- Custom text descriptor (e.g. "middle aged guy with headphones")
- Running notes field — add reads throughout the session
- Villain profiles persist across all hands within a session
- Swipe left on a seat to bust/clear a player — hands already recorded retain original descriptor
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

- **No splash screen, no walkthrough, no marketing interstitial**
- First launch goes directly to account creation
- Sign in with Apple (required), Sign in with Google, Email + Password
- All accounts require email verification and phone number
- After account creation → lands on Record tab with single gold CTA: "Start a Session"

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
- Gesture-based hand entry (NLHE cash + tournament)
- 9-seat geometric table view, session-locked hero seat
- Hold + slide sizing selector with presets
- Back-navigation within a hand
- Flexible hole card notation
- Villain profiles with session persistence and swipe-to-bust
- Manual session creation (Cash + Tournament)
- Optional stack size per hand
- Single commentary field per hand
- Personal hand history (local + cloud sync, offline-first)
- Sign in with Apple, Google, Email + Password
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
`.fold .check .call .limp .open .raise`

**`VillainTag`**
`.omC .lag .tag .fish .reg .unknown`

**`StreetName`**
`.preflop .flop .turn .river`

**`Outcome`**
`.win .lose .chop`

**`PotUnit`**
`.bigBlinds .cash`
Cash means dollar amount — applies to both cash games and tournaments. System derives display context from session type.

**`SizingType`**
`.multiple` — e.g. 2x, 2.5x
`.potFraction` — e.g. ½ pot, pot
`.bigBlinds` — flat BB amount
`.cash` — flat dollar/chip amount

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
- `activeSeatIndices` on the hand (empty seats are skipped)

Labels are derived clockwise from the button and stored frozen on each `Action`. Empty seats are skipped — they do not shift label assignments. A 9-seat table with seat 8 empty still assigns CO to seat 7, BTN to seat 9, etc.
