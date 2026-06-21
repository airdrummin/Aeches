# Card Entry Refactor — Plan Index

This package is the **complete, self-contained spec** for reworking the card-entry flow in the
Aeches iOS app. It is written so an AI assistant with **no prior context** can execute it. Read this
INDEX in full first; it holds the shared spec, the current-code map, and the conventions every phase
depends on. Then execute the phase files in order.

> **The user compiles/runs the app themselves. Do NOT run `xcodebuild` or launch the simulator.**
> Make the edits, explain what changed, and let the user build.

---

## How to use these docs

1. Read this INDEX completely (spec + current-code map + conventions).
2. Execute **Phase 1** ([Phase-1-Model-Logic-Notation.md](Phase-1-Model-Logic-Notation.md)) — the data
   model, the entry state machine, the notation, and the `ShorthandReference.md` update. After Phase 1
   the *behavior* is correct and verifiable via the on-screen shorthand transcript, even though the
   card strip still looks interim.
3. Stop. Let the user verify behavior via the transcript.
4. Execute **Phase 2** ([Phase-2-Visual-Redesign.md](Phase-2-Visual-Redesign.md)) — the strip's card
   faces + caption design, and the picker's dimming polish.

Each phase file has its own **Acceptance checklist** and **Worked examples** (test cases). Treat the
worked examples as the source of truth for behavior — if code disagrees with a worked example, the
code is wrong.

---

## Background: what this is and where it lives

Aeches is an iOS-only SwiftUI poker hand-history recorder. The relevant feature is the **per-street
card picker** on the Record screen: a persistent bottom "strip" of 7 card slots (2 hole, 3 flop, 1
turn, 1 river) plus a docked picker panel that opens when you tap a slot.

**Files (all paths relative to repo root):**

| File | Role |
|---|---|
| `Aeches/HandEntryView.swift` | The entire hand-recording engine. **All card-entry code lives here** — the slot model (`CardSlot`), the per-group state, the picker panel UI, the entry handlers, the notation formatter (`groupNotation`), the card strip, and the shorthand transcript. This is the only Swift file Phase 1/2 modify. |
| `Aeches/Models.swift` | Pure data models (`Card`, `Suit`, `Rank`, `Hand`, etc.). **Do NOT modify.** Our entry-time `CardSlot`/`CardGroup` are view-local types in `HandEntryView.swift`, not here. |
| `Aeches/SeatSelectionView.swift` | Table/seat components. **Not touched** by this refactor. |
| `ShorthandReference.md` | Authoritative spec for the shorthand notation. **Phase 1 updates §2.** |

**Design tokens** (defined as `Color` extensions in `Aeches/ContentView.swift`), used throughout:
`appBackground #0D0D0D`, `surface #161616`, `surface2 #1E1E1E`, `surface3 #252525`, `gold #C9A84C`,
`goldLight #E8D5A3`, `textBody #DDDDDD`, `textMuted #888888`, `borderDark #3A3A3A`,
`foldRed #C0392B`. Filled card faces use cream `#F5F0E8`; heart/diamond glyphs on cream use
`#C0392B`, and on the dark suit buttons use `#E74C3C`.

---

## THE LOCKED SPEC (authoritative)

A **card group** is one street's set of frames: hole = 2 frames, flop = 3, turn = 1, river = 1.
Entry is always **left-to-right**; the order you fill cards in does not matter, so tapping any slot
focuses the **left-most empty** frame, never the slot you tapped.

### The three suit modes

A group's suit information is in exactly one of these modes at a time:

| Mode | Meaning | Hole example | Flop example |
|---|---|---|---|
| **bound** | Each suit is assigned to a *specific* card. | `AdJx` (Ace IS the diamond) | `Qh5h3x` |
| **footnote** | Suits are an *unassigned* note on the group — "one of these is X, doesn't matter which." | `AJdx` | `Q53hhx` |
| **relationship** | An abstract relationship/texture from a shortcut button. | `AJs` / `AJo` | `Q53r` / `Q53m` / `Q53tt` |

Plus an implicit **none** mode: ranks entered, no suit info yet (`AJ`, `Q53`).

### How the mode is decided — the first-suit rule

The mode is set at the moment the **first suit of the group** is pressed:

- If a rank frame is **still empty** at that moment (you're interleaving) → **bound**.
- If **all ranks are already filled** → **footnote**.
- Pressing a **shortcut button** (`s`/`o`/`r`/`m`/`tt`) → **relationship** (regardless of the above).

Once bound is set, subsequent explicit suits keep binding to cards (to the card you just ranked).
Once footnote is set, subsequent explicit suits append to the footnote list.

### Entry rules (the state machine)

- **Cursor (`focusIndex`)** = the frame currently being worked (just-ranked / awaiting suit).
- **Opening a group**: cursor = left-most empty frame, else 0 if full. Ignores which slot was tapped.
- **Rank press**:
  - Group **not full**: if the cursor frame is empty, set its rank and the cursor **stays** (so a
    following suit binds to it); if the cursor frame already has a rank, set the rank on the left-most
    empty frame and move the cursor there. **No suit wipe.**
  - Group **full**: this is a **replace** → **wipe ALL suit info** (mode→none, clear footnote,
    relationship, and every frame's bound suit), set the rank at the cursor position, then advance the
    cursor cyclically `(cursor+1) % capacity`. This is "typing a fresh hand starts clean ranks-only."
- **Explicit suit press** (`♠ ♥ ♦ ♣`, and `x` = unknown):
  - No-op if the group has **no rank yet** (and the button is dimmed — see gating).
  - If mode is `none`, set mode via the first-suit rule (empty frame → bound, else footnote).
  - **bound**: set the cursor frame's suit (the just-ranked card). `x` leaves the suit unrecorded
    (nil). Suiting does **not** advance the cursor (the next *rank* advances it); pressing another
    suit re-suits the same card (a correction).
  - **footnote**: append the suit letter (`s/h/d/c`, or `x`) to the footnote list. Cap at the group's
    capacity (N); once full, **wrap-replace** from index 0. Display always pads to N characters using
    `x` for unfilled slots (so `AJ`+`d` shows `AJdx`).
- **Shortcut press** (`s`/`o` hole; `r`/`m`/`tt` flop):
  - No-op if **not all ranks are filled** (and the button is dimmed — see gating).
  - mode → relationship; set the relationship value; clear bound suits and the footnote list.
- **Done**: closes the picker. No mutation — blanks already render as `x` via the notation. (A bound
  card with no suit, when another card is suited, displays `x`.)
- **Clear**: resets the open group to empty frames, mode none, cursor 0.

### Mode override summary (consequences of the rules above)

- Any **rank-replace** (typing into a full group) wipes suits → clean ranks-only.
- Pressing a **shortcut** from any state → relationship, wiping bound/footnote.
- Pressing an **explicit suit** when all ranks are full → footnote, wiping any relationship and any
  prior bound assignment. (So `AJs` + `♦` → `AJdx`; a completed `AdJs`, re-opened, + `♣` → `AJcx`.)
- There is **no single-card editing**. To change any card, re-enter the group left-to-right.

### Two-tier dimming (UI gating)

- **Suit buttons (`♠ ♥ ♦ ♣`) and `x`**: enabled once the group has **≥1 rank**; dimmed before that.
- **Relationship buttons (`s`/`o`, `r`/`m`/`tt`)**: enabled only when **all** of the group's ranks
  are filled; dimmed before that.
- **Rank buttons**: always enabled.
- Dimmed = reduced opacity (~0.35) **and** non-interactive (disabled), matching the disabled
  action-chip treatment already used in `ControlBar`.

### Turn / River (single frame)

One card has no "which card" ambiguity, so turn/river support **bound only** (rank + optional suit on
the card). **No footnote, no relationship, no shortcut buttons.** A lone unsuited card renders as a
bare rank (`J`), a suited one as `Jh`. (`x` for a lone card is allowed but unusual.)

### Notation (strip caption + transcript) — see Phase 1 for the formatter, ShorthandReference for prose

| Mode | Hole | Flop | Turn/River |
|---|---|---|---|
| none | `AJ` | `Q53` | `J` |
| bound | `AdJx` | `Qh5h3x` | `Jh` |
| footnote | `AJdx` (ranks, then suit letters padded to N with `x`) | `Q53hhx` | n/a |
| relationship | `AJs` / `AJo` | `Q53r` / `Q53m` / `Q53tt` | n/a |

- **On-screen footnote caption** = the lowercase suit letters only (e.g. `dx`, `hhx`), all gold,
  Courier register. (The ranks are already on the card faces above it.)
- **On-screen relationship caption** = the *word*: `suited` / `offsuit` / `rainbow` / `mono` /
  `two tone`.
- **Transcript / Copy** = the full compact token from the table above (letters, and `s/o/r/m/tt`),
  inline in the hand line. Two-tone's transcript token is `tt`.

### Deferred (out of scope for both phases)

- **Persistence fidelity.** `Hand.holeCards` is `[Card]` with a per-card `suit` and cannot represent
  footnote/relationship. `buildHeroCards()` stays lossy (collapses to per-card on save). The live
  transcript (computed from the groups) is the correct artifact while recording. Board cards are not
  saved today either. Reconcile in a future pass — **do not attempt here.**

---

## Current implementation map (what exists today, to be changed)

In `Aeches/HandEntryView.swift`:

- **Slot model**: `struct CardSlot { var rank: String?; var suit: String?; var qualifier: String? }`
  (near the bottom of the file). `qualifier` currently holds `s/o` (hole) and `r/m` (flop). **Phase 1
  removes `qualifier`** and moves relationship into the group.
- **Per-group state** (top of `HandEntryView`):
  `@State heroCards: [CardSlot]` (2), `flopCards: [CardSlot]` (3), `turnCard: CardSlot`,
  `riverCard: CardSlot`, `entryStreet: CardStreet?`, `focusIndex: Int`.
- **`enum CardStreet { case hole, flop, turn, river; var count: Int }`**.
- **Handlers** (to be rewritten): `openCardEntry(_:focus:)`, `closeEntry()`, `clearEntryGroup()`,
  `rankTapped(_:)`, `suitTapped(_:)`, `relationshipTapped(_:)`, `textureTapped(_:)`,
  `groupCards(_:)`, `setGroupCard(_:_:_:)`.
- **Notation** (to be rewritten): `groupNotation(_:)`, `cardToken(_:markUnknown:)`, `suitLetter(_:)`.
- **Picker UI** (`cardPickerPanel` and helpers `suitCluster`, `shortcutSquares`, `iconButton`,
  `suitSquare`, `unknownSuitSquare`, `shortcutSquare`, `rankRow`): the picker was recently rebuilt to
  a compact layout — rank grid (7 over 6), then ONE centered control row: trash icon (Clear, pinned
  left), the suit cluster `♠ ♥ ♦ ♣ x | <shortcuts>` (centered), checkmark icon (Done, pinned right).
  Flop shortcuts are currently `r`/`m` and must become `r`/`m`/`tt`.
- **Card strip** (`cardStrip`, `streetSection`, `CardSlotView`): renders the 7 slots. `CardSlotView`
  shows rank + suit (or `qualifier` letter when no suit). **Phase 2 redesigns this** to render group
  card faces + a caption.
- **Transcript** (`handShorthand` and helpers): `boardToken(for:)` calls `groupNotation`;
  `actorSegment` calls `groupNotation(.hole)` to attach hero hole cards. These must keep working with
  the rewritten `groupNotation`.
- **Save**: `buildHeroCards()` converts `heroCards` → `[Card]` (stays lossy — see Deferred).

---

## Conventions

- **Do not build/run.** The user compiles. Provide edits + a change summary only.
- **Do not modify `Models.swift`** or `SeatSelectionView.swift`.
- Match the surrounding code style in `HandEntryView.swift` (comment density, naming, SwiftUI idioms).
- Keep all card-entry state local to `HandEntryView` (no new observable/environment layers) — this is
  an explicit architectural constraint of the app.
- Preserve the single-`DragGesture` seat handling in `SeatSelectionView.swift` (unrelated, but do not
  refactor it as a side effect).
- The worked examples in each phase are acceptance tests. Implement to satisfy them exactly.

---

## Phases

| Phase | File | Delivers | Verify by |
|---|---|---|---|
| 1 | [Phase-1-Model-Logic-Notation.md](Phase-1-Model-Logic-Notation.md) | `CardGroup`/`CardFrame` model; entry state machine; two-tier gating; `tt` button; `groupNotation` rewrite; `ShorthandReference.md` §2 update; interim strip rendering that compiles | Reading the on-screen shorthand transcript while entering hands — it must match the Worked Examples |
| 2 | [Phase-2-Visual-Redesign.md](Phase-2-Visual-Redesign.md) | Final strip design: rank-forward card faces + footnote/relationship caption beneath each group, baseline-aligned; dimming polish | Visual inspection against the mockup sketches in that file |

Execute 1, pause for user verification, then 2.
