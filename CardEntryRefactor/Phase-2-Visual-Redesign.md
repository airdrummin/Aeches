# Phase 2 — Strip Visual Redesign

**Prerequisite:** [INDEX.md](INDEX.md) read, and **Phase 1 complete and verified** (the data model is
`CardGroup`/`CardFrame`, the entry logic and notation are correct, the transcript matches the Phase 1
Worked Examples). This phase replaces the *interim* strip rendering from Phase 1 Step 6 with the final
design. All edits are in `Aeches/HandEntryView.swift`.

**Goal:** the card strip visually distinguishes the three suit modes at a glance, using the rule:
**a suit on the card face = assigned (bound); a caption beneath the group = unassigned (footnote
letters) or abstract (relationship word).**

---

## The visual language (what each state looks like)

Each street group = a row of rank-forward **card faces**, with an optional **caption** hanging below
the group (not below any single card). Card faces stay baseline-aligned across HOLE/FLOP/TURN/RIVER;
only captions hang lower, so the strip's top line is even.

ASCII sketches (cream face = filled, outline = empty):

```
EMPTY (hole)            RANKS ONLY (AJ)         BOUND (AdJx)
┌──┐ ┌──┐               ┌──┐ ┌──┐               ┌──┐ ┌──┐
│? │ │? │               │A │ │J │               │A │ │J │
└──┘ └──┘               └──┘ └──┘               │♦ │ │x │      ← suit/"x" ON the face
                                                └──┘ └──┘

FOOTNOTE (AJdx)         RELATIONSHIP (AJs)      FLOP FOOTNOTE (Q53hhx)
┌──┐ ┌──┐               ┌──┐ ┌──┐               ┌──┐ ┌──┐ ┌──┐
│A │ │J │               │A │ │J │               │Q │ │5 │ │3 │
└──┘ └──┘               └──┘ └──┘               └──┘ └──┘ └──┘
  ╶ dx ╴                 ╶suited╴                  ╶ hhx ╴       ← caption UNDER the group
```

Key distinctions:
- **bound**: each card face shows rank + its suit pip; a suitless card in a bound group shows a small
  grey `x` on its own face (so `AdJx` reads "Ace=♦, Jack=unknown"). No caption.
- **footnote**: card faces show **rank only**; a single centered caption shows the lowercase suit
  letters padded to N with `x` (`dx`, `hhx`) in Courier/gold.
- **relationship**: card faces show **rank only**; caption shows the **word** (`suited`, `offsuit`,
  `rainbow`, `mono`, `two tone`).
- **none**: rank-only faces, no caption.
- **turn/river**: bound-only — rank + optional suit on the single face, never a caption.

---

## Styling tokens (match the rest of the app)

- **Card face (filled)**: bg cream `#F5F0E8`, corner radius 6–8. Rank: black `#1A1A1A`, bold,
  ~16–18pt. Suit pip (bound): below the rank, ~10–11pt; hearts/diamonds `#C0392B`, spades/clubs
  `#1A1A1A`. Suitless-in-bound `x`: grey `~#888`, bold, ~10pt.
- **Card face (empty)**: bg `surface2 #1E1E1E`, 1px `borderDark` (≈0.5α), `?` in `borderDark`.
- **Focused frame** (while its group's picker is open and it's the cursor): gold border (2px) + soft
  gold shadow — reuse the existing active-slot treatment.
- **Footnote caption**: Courier New, bold, ~13–14pt, letter-spacing ~2, color `goldLight #E8D5A3`,
  on a `#1C1810` pill with a `gold@35%` border, radius 7, tight horizontal padding. Keep it **narrow
  and centered** under the group (must NOT span the full card-row width — that's what made an earlier
  version read as one-pip-per-card).
- **Relationship caption**: same pill, but Arial ~11pt, lowercase word, letter-spacing ~1.
- Captions are **lowercase**; the words are exactly `suited` / `offsuit` / `rainbow` / `mono` /
  `two tone`.

---

## Step 1 — Group view that renders faces + caption

Replace the interim rendering from Phase 1 Step 6. Build a `groupStripView(street:)` (or refactor
`streetSection`) that:

1. Renders the street label (`HOLE`/`FLOP`/`TURN`/`RIVER`) as today (gold when active).
2. Renders the frames as a row of card faces from `group(for: street).frames`, highlighting the cursor
   frame when `entryStreet == street && focusIndex == i`.
3. Renders a caption beneath the row from the group's mode:
   - `.footnote` → the padded letter string (`footnote` padded to capacity with `x`, joined). Reuse the
     same padding logic as `groupNotation`'s footnote branch (factor a small helper so they can't
     drift).
   - `.relationship` → the word via a `relationshipWord(_:)` map: `s→suited, o→offsuit, r→rainbow,
     m→mono, tt→two tone`.
   - `.bound` / `.none` → no caption.
4. Reserves consistent vertical space so the card-face baseline is identical across all four groups
   (captions hang into reserved space below; groups without a caption simply leave it empty). Tap a
   group/frame still calls `openCardEntry(street)`.

Keep the strip's existing outer layout (the four groups spaced across the row, the active-group gold
outline on `streetSection`).

## Step 2 — Update `CardFrameView` (was `CardSlotView`)

Rename/replace `CardSlotView` to render a `CardFrame` plus a `mode` flag (so it knows whether to draw a
bound suit on the face vs nothing for footnote/relationship/none):

```swift
struct CardFrameView: View {
    let frame: CardFrame
    let showBoundSuit: Bool       // true only when the group is .bound
    let isActive: Bool
    // empty -> outlined "?"; filled -> cream face with rank; if showBoundSuit and frame.suit != nil
    // -> suit pip under rank; if showBoundSuit and frame.suit == nil and the group has another suited
    //    frame -> small grey "x"; otherwise rank only.
}
```

The "show grey x for a suitless card in a bound multi-card group" needs the group context — pass a
`boundUnknown: Bool` computed by the parent (`group.mode == .bound && frame.suit == nil && anyOtherFrameSuited`).

## Step 3 — Dimming polish

Phase 1 already disabled illegal buttons. Verify the dimmed appearance reads as "not yet," not
"broken": opacity ~0.35, no border glow, but the glyph still legible. Confirm the suit cluster +
`r m tt` row stays centered and fits on the narrowest target (iPhone SE width). If cramped, tighten
`suitCluster` spacing (6 → 5) before shrinking square sizes.

---

## Acceptance checklist (Phase 2)

- [ ] Card faces are baseline-aligned across HOLE/FLOP/TURN/RIVER; captions hang below without
      shifting the faces.
- [ ] **bound** shows suits on the card faces (and a grey `x` on a suitless card when its partner is
      suited); **no** caption.
- [ ] **footnote** shows rank-only faces + a narrow, centered, Courier/gold letter caption (`dx`,
      `hhx`) that clearly does not align one-pip-per-card.
- [ ] **relationship** shows rank-only faces + a word caption (`suited`/`offsuit`/`rainbow`/`mono`/
      `two tone`).
- [ ] Turn/River never show a caption.
- [ ] Focused frame highlights with the gold ring while its picker is open.
- [ ] Footnote caption padding uses the SAME helper as `groupNotation` (no drift).
- [ ] Dimmed buttons read as "not yet"; flop control row fits centered on a narrow phone.

---

## Visual reference (states to eyeball)

Build mentally / on device against these (matches the sketches above):

- Hole empty · `AJ` · `AdJx` · `AJdx` · `AJs`
- Flop `Qh5h3x` (bound) · `Q53hhx` (footnote) · `Q53r` / `Q53tt` (relationship)
- Turn `Jh` · `J`

Each must be instantly distinguishable as bound (suit on face) vs footnote (letters below) vs
relationship (word below).
