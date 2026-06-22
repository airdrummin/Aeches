# Display Layout Refactor — Hand Entry Screen

Authoritative plan for re-sizing and re-balancing the Record screen's vertical layout
(table / card strip / control bar / card picker / transcript). Worked out in discussion;
this file is the single reference. Implement in the phases below — nothing here is built yet.

Related: `README.md` (§ Core Feature: Hand Entry UI), `PokerActionReference.md`.
Touches `Aeches/SeatSelectionView.swift` (table geometry) and `Aeches/HandEntryView.swift`
(body layout, control bar, picker, transcript).

---

## Implementation status

**Phases 1–3 implemented** (code only — Phase 4 device pass is still pending a build by the user).

Two intentional deviations from the numbers below, settled during implementation:
- **Table frame in play uses `maxHeight: .infinity`, not a soft-cap 360.** Capping the frame
  while pinning the dock to the bottom would require a bottom Spacer that reads as a void on
  tall phones. Letting the (aspect-locked, non-distorting) frame absorb all slack as oval margin
  gives zero void and is simpler. Seat-select clamps the frame to **320** (no dock to pin).
  → On a Pro Max the oval carries ~80 pt of margin each side (the intended breathing room). If
  that ever reads too floaty, swap to a finite max + accept a small bottom gap.
- **Control region height = `234`** (`controlRegionHeight` in `HandEntryView`), i.e. control bar
  (~124, with the 54 pt action row) + a 5-line transcript slot (~110). The picker fills it with
  distributed spacing.

---

## Goals

1. **Bigger, consistent table** — one table size across all phases (no 300 → 250 shrink).
2. **Table never distorts** — the oval stays a handsome poker proportion at every size.
3. **Table never moves** — opening the card picker, placing the button, changing streets,
   and lengthening the transcript must not resize or shift the oval.
4. **Tidy transcript** — a glance (3–5 lines) during play; full read via the expand drawer.
5. **No mid-screen void, no overflow** — graceful on every phone we ship to.

## Device floor

**844 pt (iPhone 16e).** Apple no longer sells any sub-6.1″ phone (SE/mini discontinued
Feb 2025). We design to 844 and let the clamp degrade gracefully if an older device ever
appears — **no device-specific code**.

---

## Locked spec

### #1 — Table (the hero)
- **Aspect-lock at 1.40.** Replace `ry = h * 0.36` with `ry = rx / 1.4` (vertical radius
  derived from width, not frame height). The oval can no longer distort — frame height
  becomes pure margin around it.
- **Frame clamp: `minHeight 290`, soft `maxHeight ~360`.** Min guarantees swipe room; with
  aspect-lock the max is only about limiting whitespace, not shape.
- **`rx` stays `w * 0.40`** (current width). Not widening the table now; revisit later if it
  reads small.
- **One sizing for all phases** — seat-select through showdown use the same table. On
  seat-select (no dock below) the frame simply absorbs more slack as margin → the large
  centered oval we already show there.

### #2 — Card strip
- **Unchanged:** fixed ~95 pt, cards 40×40, four groups side-by-side.
- Keep the always-reserved caption row (stops the strip jumping when suit captions appear).

### #3 — Control bar
- **Action chips: 48 → 54 pt tall, text 14 → 16 pt.** The primary one-thumb control; bought
  with spare budget.
- Utility row (Undo / Next) **unchanged**.
- Total height **~125 pt**, pinned to the bottom of the dock.

### #4 — Transcript
- Inline: **floor 3 lines, cap 5 lines** (header ≈ 25 pt + ~16 pt/line → 73–105 pt).
- Reserved at its **5-line height (105 pt)** so it never moves the table; content flexes
  3–5 within that slot (short content = a little internal breathing room).
- Leftover beyond the cap on big phones → **breathing room around the table** (margin in the
  flexible table frame), never a taller log and never a void.
- **Hide the inline transcript while the picker is open** (today it stays as a sliver — change it).
- Full read / Copy / push → the existing **expand drawer**, unchanged.

---

## Layout model (the mechanics that make it hold)

Top-packed `VStack`: `nav · status · TABLE FRAME (flexible) · divider · DOCK (fixed)`.

```
┌─ header ────────────────────────┐  fixed (nav + status)
│ TABLE FRAME                      │  FLEXIBLE: maxHeight .infinity, minHeight 290,
│   aspect-locked oval, centered   │  soft max ~360. Absorbs ALL device slack as
│   (extra height = margin)        │  margin around the fixed-size oval.
├─ divider ───────────────────────┤
│ DOCK  (FIXED height ≈ 325)       │  Pinned to bottom. Constant across states →
│   card strip            95       │  the table frame above it is constant per
│   ┌ control region  230 ┐        │  device → the oval never drifts.
│   │ control bar     125 │  OR    │
│   │ transcript slot 105 │ picker │  Picker (≈174 natural) FILLS the 230 region
│   └─────────────────────┘ (174→  │  (extra space → larger key spacing); transcript
│                            230)  │  hides. Region height unchanged → table still.
└──────────────────────────────────┘
```

**Why the table can't move:**
- The **dock is a fixed-height container** (`strip 95` + `control region 230` ≈ **325**).
- The **control region** is reserved at a constant **230** = `control bar 125` + `transcript
  slot 105` (the taller of the two states; the picker's ~174 is shorter and is stretched to
  fill 230).
- Because the dock height is identical whether the control bar **or** the picker is showing,
  the flexible table frame above it is constant for a given device → the oval is rock-stable
  on picker toggle, button placement, and street changes.
- Device slack flows only into the **table-frame margin** (and a tiny bottom gap on the very
  largest phones if the soft max is hit) — never a mid-screen void.

**Picker interlock check:** control bar (125) + transcript slot (105) = 230 ≥ picker (174). ✅
The picker always fits in the freed region with room to spare.

### Illustrative per-device numbers
Chrome = top safe area + nav + status + divider + system tab bar (computed at runtime via
`GeometryReader`, not hardcoded). Oval at w≈374: 299 wide × 214 tall (1.40).

| Device | Screen | Chrome | Dock | Table frame | Inline transcript |
|---|---|---|---|---|---|
| iPhone 16e (floor) | 844 | ~209 | 325 | **~310** | 3–5 lines |
| iPhone 15 / 16 | 852 | ~209 | 325 | ~318 | 3–5 |
| iPhone 16 Pro | 874 | ~229 | 325 | ~320 | 3–5 |
| iPhone 16 Pro Max | 932 | ~229 | 325 | ~360 (soft cap; ~18 bottom gap) | 3–5 |

Oval + seat ring ≈ 274 pt tall; fits inside the 290 min with margin to spare. Aspect-lock
makes the vertical ring *slightly tighter* than today at equal frame height (new `ry` 106.9
vs old 111.6 at h≈310), so there is **no seat-overflow risk** — seats move marginally inward.

---

## Phased implementation

### Phase 1 — Table aspect-lock + clamp  *(isolated, low risk)*
**`Aeches/SeatSelectionView.swift`**
- `TableOvalView`, line ~69: change `let ry = h * 0.36` → `let ry = rx / 1.4`.
- Defaults line ~46–47 and the `.frame(minHeight:maxHeight:)` line ~348: leave the frame
  driven by the call site.

**`Aeches/HandEntryView.swift`**
- Table call site, lines ~237–238: replace
  `minHeight: isPlayingPhase ? 250 : 300, maxHeight: isPlayingPhase ? 250 : 300`
  with the flexible band: `minHeight: 290, maxHeight: 360` for **all** phases (drop the
  `isPlayingPhase` split). Add `.frame(maxHeight: .infinity)` behaviour so the frame absorbs
  slack (see Phase 3 — the table becomes the flexible element).

**Verify:** seats stay within bounds at 6/8/9/10; oval reads ~1.40 on seat-select and during
play; nothing clips at the 290 min.

### Phase 2 — Control bar sizing  *(isolated, low risk)*
**`Aeches/HandEntryView.swift`**
- `actionChip`, line ~2019: font `Arial 14` → `16`.
- line ~2023: `.frame(height: 48)` → `54`.
- Leave `undoButton` / `nextStreetButton` untouched.

**Verify:** control bar ≈ 125 pt; Fold/Call/Raise and Check/Bet both still fit full-width.

### Phase 3 — Dock restructure  *(the substantive change)*
**`Aeches/HandEntryView.swift`, body `VStack` lines ~191–310**
- Make the **table frame the flexible element** (`maxHeight: .infinity`, min 290) so it
  absorbs device slack; everything below the divider becomes a **fixed-height dock** pinned
  to the bottom.
- Wrap the control/picker area in a **fixed-height "control region" (~230 pt)**:
  - **Control-bar state** (`entryStreet == nil`): control bar (125) + transcript (fills the
    remaining ~105 slot).
  - **Picker state** (`entryStreet != nil`): `cardPickerPanel` stretched to fill the 230
    region; **transcript hidden**.
- **Hide `transcriptInline` when `entryStreet != nil`** (lines ~283–306): today it renders
  after the if/else regardless — gate it so the picker and transcript never co-exist.
- **`transcriptInline`** (lines ~1360–1400): remove `maxHeight: .infinity`; give it a slot
  of `~105` (5-line cap) with content clamped to a 3-line min. Keep the tap/swipe-up →
  expand drawer behaviour.
- **`cardPickerPanel`** (lines ~1233–1271): allow it to fill the control region height
  (distribute extra space as larger row spacing / touch area) so there is no gap above it.

**Verify (the critical one):** the oval does **not** move or resize when you (a) open/close
the picker, (b) place the button, (c) advance streets, (d) accumulate transcript lines. The
dock stays pinned to the bottom; no mid-screen void; no overflow at 844.

### Phase 4 — Device pass
- Walk 844 / 852 / 874 / 932 in the simulator (user builds): confirm the table-frame numbers
  above, transcript 3–5 lines, picker fits, breathing room reads as intentional (not a void).
- Confirm seat-select shows the large centered oval (more margin, same oval size).

---

## Open / tunable dials (defaults chosen; easy to revisit)
- **Aspect ratio 1.40** — 1.35 reads slightly larger/rounder, 1.45 flatter/longer.
- **Table soft-max 360** — lower it to tighten big-phone margin, raise it to let the oval
  area grow.
- **Transcript slot 105 (5 lines)** — this is what sets the control region to 230 and thus
  gives the picker headroom. Dropping it toward 2–3 lines shrinks the region (less picker
  stretch) at the cost of inline transcript height.
- **`rx` 0.40** — bump toward 0.42–0.44 (and trim horizontal padding) later if the table
  should have more presence; aspect-lock keeps it proportional automatically.

## Risks / watch-items
- **Seat overflow** at the 290 min on 10-handed — verify in Phase 1 (low risk; new ring is
  tighter than today's).
- **Picker fill** — stretching the picker to 230 must not space the rank/suit rows so far
  apart they look detached; cap the inter-row spacing if needed.
- **Animation** — the existing `.animation(... value: entryStreet != nil)` (line ~324) drives
  the picker in/out; with the transcript now hiding, confirm the cross-fade still reads clean
  and the dock height truly stays constant (no 1-frame jump).
- **Two position-label paths** and **lossy card save** noted in `README.md` are unrelated to
  this refactor — do not touch.
