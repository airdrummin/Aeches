# Pulse Animation Refactor — Implementation Plan

**Status:** Approved, ready to implement.
**Scope:** Replace the imperative `@State` + `repeatForever` + `onAppear`/`onChange` pulse machinery — in **all three** places it currently lives (seat highlight pulse, Next Street button pulse, felt instruction-text pulse) — with **one** declarative `TimelineView`-driven primitive that is a pure function of time and an on/off input. iOS / SwiftUI.

This document is self-contained. An AI or developer should be able to execute the refactor from this file alone. Read it fully before editing.

**Goal:** after this refactor there must be **no leftover pulse state, lifecycle hooks, or cancellation code** in any of the three pulses — `pulseScale`, `nextStreetPulse`, `instructionPulse`, and every `onAppear`/`onChange` pulse handler are gone, replaced by a single shared `Pulse` view.

---

## 1. Files involved

| File | Role |
|---|---|
| `Aeches/SeatSelectionView.swift` | Home of the shared `Pulse` primitive (new). Owns the **seat highlight pulse** (`SeatButtonView`) and the **instruction-text pulse** (`TableOvalView`). **Primary file.** |
| `Aeches/HandEntryView.swift` | `ControlBar` — owns the **Next Street button pulse**; also `commitAction` (one cosmetic note, no change required). |

Nothing else changes. **Do not touch** routing, state, or logic: `highlightedSeat`, `streetClosedDecisively`, `settleAfterCommit`, `commitAction`/`finishSwipe`/tap routing, `recordAction`, `recomputeDerivedState`, street-close, fold-out, rewind. The pulse only *reads* its inputs.

---

## 2. Why this refactor (context)

The pulse is currently **imperative per-view animation state**, duplicated in three places: each view holds a `@State` scale (or bool), starts a `repeatForever` animation in `onAppear`/`onChange`, and must manually cancel it. This pattern caused two separate bugs already on the seat pulse:
1. The `repeatForever` was never cancelled (plain assignment doesn't stop a repeating animation).
2. A `scaleEffect(isActive ? pulseScale : 1.0)` gate decoupled the rendered scale from the property the cancel acted on, so the pulse stuck whenever the highlight moved without an ambient `withAnimation` (e.g. action buttons).

Both are currently *fixed*, but the machinery remains fragile (depends on `repeatForever` cancellation semantics + lifecycle callbacks firing + ambient transactions). Worse, the **same anti-pattern is copied three times in two files** — so the next maintainer copies whichever neighbor they land on, and the bug class can re-enter through the un-migrated copies. This refactor removes the machinery entirely *and* collapses all three pulses onto one primitive so there is nothing left to copy incorrectly.

### The principle
**A pulse is a pure function of `(time, isOn)`.** No animation state, no `repeatForever`, no `onChange`, no cancellation. A single `TimelineView(.animation(paused:))` ticks only while the pulse is on; when off, the phase is literally `0` and nothing scales. This makes "stuck pulse" impossible by construction and removes all dependence on how the highlight moved.

### One unified system
All three pulses share **one** primitive, `Pulse`, which exposes a `0…1` *phase* rather than baking in a fixed scale. Each call site interpolates whatever properties it wants off that one clock — the seat and button breathe scale only; the instruction text breathes scale **and** opacity **and** shadow. There is no longer a scale-only pulse and a separate richer pulse; there is one clock and three readers.

### Note on two intentional changes (not "identical behavior")
This is a machinery swap, but it is **not** pixel-identical, and that is deliberate:

1. **Amplitude is reduced** (seat `0.08 → 0.04`, instruction `0.02` kept small, button `0.06 → 0.05`). With a paused timeline the sine is sampled at an *arbitrary* phase the instant a pulse turns on, so the scale steps instantly to somewhere in its range — there is no ramp-in. A small amplitude makes that step imperceptible. This is the price of the time-based approach and the reason the amplitudes are intentionally small. **Do not raise them** — a larger value reintroduces a visible "pop" on activation.
2. **Easing changes** from `easeInOut` autoreverse to a raw `sin`. Slightly more evenly-rounded motion. Acceptable and intentional.

These are safe because the **primary** "on the clock" cue is the discrete gold border + glow ring (driven by `isActive`, left untouched). The scale pulse is secondary emphasis only, so a subtler pulse does not weaken the turn indicator — and a more discreet pulse suits the app's "discreet by design" brand.

---

## 3. The shared primitive (new code)

Add this to `SeatSelectionView.swift` (the shared-components file). It is the entire animation engine for all three pulses.

```swift
/// A pure-function pulse. Ticks only while `isActive` (paused otherwise → no per-frame cost and
/// phase is exactly 0). Exposes a 0…1 `phase` so each call site interpolates whatever it wants
/// (scale, opacity, shadow). This is the single source of pulse motion in the app.
struct Pulse<Content: View>: View {
    let isActive: Bool
    var frequency: Double = 3.5
    @ViewBuilder var content: (CGFloat) -> Content   // phase: 0…1 while on, 0 while off

    var body: some View {
        TimelineView(.animation(paused: !isActive)) { context in
            content(phase(at: context.date))
        }
    }

    private func phase(at date: Date) -> CGFloat {
        guard isActive else { return 0 }
        return (sin(date.timeIntervalSinceReferenceDate * frequency) + 1) / 2   // 0…1
    }
}
```

Notes:
- `sin` resolves via the existing `import SwiftUI` (Foundation). If the compiler can't find it, add `import Foundation`.
- `frequency: 3.5` gives a ~1.8s full cycle, matching the old `easeInOut(duration: 0.9).repeatForever(autoreverses:)` cadence.
- `TimelineView` is a pure layout/redraw container — wrapping a view does not change its frame, position, gesture attachment, or hit-testing.

---

## 4. Call-site conversions (exact changes)

### 4.1 `SeatButtonView` — seat highlight pulse (`SeatSelectionView.swift`)

**Delete** the state property (~line 365):
```swift
@State private var pulseScale: CGFloat = 1.0
```

**Replace** the end of `var body` (~lines 619–643). The ZStack and its `.frame(width: size, height: size)` move into a private `seatBody`; `body` wraps it in `Pulse`:

From:
```swift
    var body: some View {
        ZStack {
            ... existing content ...
        }
        .frame(width: size, height: size)
        .scaleEffect(pulseScale)
        .onAppear { ... }
        .onChange(of: isActive) { ... }
    }
```
To:
```swift
    var body: some View {
        Pulse(isActive: isActive) { phase in
            seatBody.scaleEffect(1.0 + 0.04 * phase)
        }
    }

    private var seatBody: some View {
        ZStack {
            ... existing content unchanged ...
        }
        .frame(width: size, height: size)
    }
```

Everything inside the ZStack (shadows, border, glow, badges, size pill, HERO label, dealer button, `isActive`-driven `borderColor`/`shadow`) is **unchanged** — those are discrete states, not pulse machinery.

### 4.2 `TableOvalView` — instruction-text pulse (`SeatSelectionView.swift`)

**Delete** the state property (~line 21):
```swift
@State private var instructionPulse: Bool = false
```

**Replace** the `if let instruction { Text(instruction)… }` block (~lines 161–182). Wrap the text in `Pulse(isActive: instruction != nil)` and drive all three breathing properties off the shared phase. Drop the `onAppear`/`onChange` restart handlers entirely:

From:
```swift
                if let instruction {
                    Text(instruction)
                        .font(.custom("Georgia", size: 20))
                        .fontWeight(.black)
                        .tracking(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.gold.opacity(instructionPulse ? 0.82 : 0.65))
                        .scaleEffect(instructionPulse ? 1.02 : 1.0)
                        .shadow(color: Color.gold.opacity(instructionPulse ? 0.18 : 0.0), radius: 8)
                        .shadow(color: Color.black.opacity(0.7), radius: 4)
                        .transition(.opacity)
                        .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { instructionPulse = true } }
                        .onChange(of: instruction) { _, _ in
                            instructionPulse = false
                            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { instructionPulse = true }
                        }
                }
```
To:
```swift
                if let instruction {
                    Pulse(isActive: true) { phase in
                        Text(instruction)
                            .font(.custom("Georgia", size: 20))
                            .fontWeight(.black)
                            .tracking(3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.gold.opacity(0.65 + 0.17 * phase))
                            .scaleEffect(1.0 + 0.02 * phase)
                            .shadow(color: Color.gold.opacity(0.18 * phase), radius: 8)
                            .shadow(color: Color.black.opacity(0.7), radius: 4)
                            .transition(.opacity)
                    }
                }
```

> `isActive: true` is correct here: the `Pulse` only exists inside the `if let instruction` branch, so it is mounted exactly when an instruction is showing and unmounted otherwise. The continuous clock keeps oscillating across an instruction-text change rather than restarting — the old "re-pulse on change" beat is intentionally dropped in favor of one unified system.

**Also delete** the two now-dead resets in the sibling branches (~lines 190 and 198), which only existed to stop the old imperative pulse:
```swift
                        .onAppear { instructionPulse = false }   // in the `actionText` branch
...
                        .onAppear { instructionPulse = false }   // in the `HH` branch
```
With the pulse scoped to the `instruction` branch, these are no longer needed.

### 4.3 `ControlBar` — Next Street button pulse (`HandEntryView.swift`)

**Delete** the state property (~line 1418):
```swift
@State private var nextStreetPulse: CGFloat = 1.0
```

**Replace** `nextStreetButton` (~lines 1459–1519) so the Button moves into a private `nextStreetButtonBody` and `nextStreetButton` wraps it in `Pulse`:
```swift
    private var nextStreetButton: some View {
        Pulse(isActive: nextStreetPulsing) { phase in
            nextStreetButtonBody.scaleEffect(1.0 + 0.05 * phase)
        }
    }

    private var nextStreetButtonBody: some View {
        Button(action: onNextStreet) {
            HStack(spacing: 3) {
                Text(nextStreetLabel)
                    .font(.custom("Arial", size: 11))
                    .fontWeight(.bold)
                    .tracking(0.5)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(nextStreetEnabled ? Color(hex: "#0D0D0D") : Color.textMuted.opacity(0.5))
            .padding(.horizontal, 11)
            .padding(.vertical, 11)
            .background {
                if nextStreetEnabled {
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.gold, Color(hex: "#9A6820")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                } else {
                    Capsule().fill(Color.surface2)
                }
            }
            .overlay(
                Capsule().stroke(
                    nextStreetEnabled ? Color.goldLight.opacity(0.6) : Color.borderDark.opacity(0.5),
                    lineWidth: 1
                )
            )
            .shadow(color: nextStreetPulsing ? Color.gold.opacity(0.55) : (nextStreetEnabled ? Color.gold.opacity(0.4) : .clear),
                    radius: nextStreetPulsing ? 12 : 6)
        }
        .buttonStyle(.plain)
        .disabled(!nextStreetEnabled)
        .opacity(nextStreetEnabled ? 1.0 : 0.55)
    }
```

The `.shadow(...)` glow line is a discrete (non-repeating) state change on `nextStreetPulsing` — **keep it** inside `nextStreetButtonBody` exactly as-is. Only the scale machinery is replaced.

### 4.4 `commitAction` — leave as-is (documentation note only)

`commitAction` (`HandEntryView.swift`) is wrapped in `withAnimation(.easeInOut(duration: 0.15))`. This was originally added partly as a belt-and-suspenders for the old pulse cancel. After this refactor it is **no longer needed for the pulse**, but it still provides smooth `isActive`-driven border/glow transitions on a button press (matching the swipe path). **Keep it** — it is intentional, not leftover. No edit required; do not remove it expecting a pulse change.

---

## 5. Deletions checklist (no leftover code)

- [ ] `@State private var pulseScale: CGFloat = 1.0` in `SeatButtonView`
- [ ] `.scaleEffect(pulseScale)` + `.onAppear`/`.onChange(of: isActive)` pulse handlers in `SeatButtonView`
- [ ] `@State private var instructionPulse: Bool = false` in `TableOvalView`
- [ ] instruction `Text` pulse handlers: `.onAppear { withAnimation(...repeatForever...) }` and `.onChange(of: instruction)` restart
- [ ] both `.onAppear { instructionPulse = false }` resets in the `actionText` and `HH` branches
- [ ] `@State private var nextStreetPulse: CGFloat = 1.0` in `ControlBar`
- [ ] `.scaleEffect(nextStreetPulsing ? nextStreetPulse : 1.0)` + `.onChange(of: nextStreetPulsing)` in `ControlBar`

After editing, grep to confirm zero references remain:
```
grep -rn "pulseScale\|nextStreetPulse\|instructionPulse\|repeatForever" Aeches/*.swift
```
Expected result: **no matches** — every pulse now flows through `Pulse`, and no `repeatForever` survives in any pulse path. (If `repeatForever` ever appears elsewhere for something that is genuinely not a pulse, leave it — but there is no such case today.)

---

## 6. Why this is safe (cannot affect other systems)

- The new code reads only `isActive` (seat), `instruction != nil` (instruction), and `nextStreetPulsing` (button) — the **same inputs** the old code read. No new inputs, no writes to any model/state.
- `TimelineView` is a pure layout/redraw container; wrapping a seat, the instruction text, or the button does not change its frame, position, gesture attachment, or hit-testing. The seat's `DragGesture` is applied by the parent (`TableOvalView`) on the positioned view, not inside `SeatButtonView`, so it is untouched.
- `paused:` means only an on-the-clock pulse ticks — the on-the-clock seat (one at a time), the button only during a decisive close, the instruction only while shown. No per-frame cost otherwise.
- No routing, street-close, fold-out, rewind, or card logic is read or modified.

---

## 7. Acceptance test scenarios

Build, then verify by hand (6-handed unless noted):

1. **Exactly one seat pulse:** during recording, only the on-the-clock seat pulses; all others are still.
2. **Button input:** UTG → press Raise → only UTG+1 pulses (UTG calm). Press Fold down the line → only the new on-clock seat pulses; previously-acted/folded seats are still. (This was the bug that motivated the refactor — confirm it's gone.)
3. **Swipe input:** same as #2 via swipes — identical result.
4. **Tap-cycle:** tapping the on-clock seat to cycle keeps that seat pulsing throughout.
5. **Decisive close:** a swipe/button that closes the round → the acted seat goes fully plain (no ring, no pulse), and the **Flop/Turn/River/Showdown** button pulses.
6. **Tap-completed round:** tap-cycling the last seat to a closing action → seat keeps pulsing, Next Street button is lit but **not** pulsing.
7. **Rewind:** rewinding back to an on-clock seat resumes its pulse; rewinding out of a decisive close moves the pulse from the button back to the seat.
8. **Instruction pulse:** in `selectSeat` / `placingButton` / closed ("TAP A SEAT TO DEAL") states, the felt instruction text breathes (scale + opacity + glow). Switching instruction text keeps it oscillating smoothly (no hard restart — this is intended). Switching to the `actionText`/`HH` states stops it cleanly.
9. **New hand:** after dealing, the first actor pulses; no stale pulse anywhere.
10. **Activation is imperceptible (not "no pop"):** when a pulse turns on mid-cycle the scale may step instantly to anywhere in its range (there is no ramp-in). At these amplitudes (seat 0.04, button 0.05, instruction 0.02) the step is ≤5% and invisible. Confirm no *visible* pop, no flicker, no element stuck enlarged. **Do not raise the amplitudes** — a larger value makes the activation step visible.

---

## 8. DRY / architecture principles

- **Pulse = pure function of `(time, isOn)`.** No animation `@State`, no `repeatForever`, no manual cancellation — the entire "stuck pulse" bug class is removed by construction.
- **One primitive, three readers.** `Pulse` is the single source of pulse motion. It exposes a `0…1` phase; seat and button read it for scale, the instruction reads it for scale + opacity + shadow. There is no second pulse mechanism to drift or to copy incorrectly.
- **One on/off input per pulse:** `isActive` (seat), `instruction != nil` (instruction), `nextStreetPulsing` (button). These remain the single sources of truth, set by the existing routing/state — the refactor does not add a parallel signal.
- **Discrete highlight states stay discrete:** border width, border color, glow shadow, HERO/dealer chrome are driven directly by `isActive`/`nextStreetEnabled`/`nextStreetPulsing` and are left exactly as they are — only the continuous *pulse* (scale, and for the instruction its opacity/glow breathing) moves to `Pulse`.
- **Amplitudes are intentionally small** (seat 0.04, button 0.05, instruction 0.02) and must not be raised: the time-based pulse has no ramp-in, so amplitude *is* the worst-case activation step. This is a deliberate, documented visual choice, not a value to "restore."
