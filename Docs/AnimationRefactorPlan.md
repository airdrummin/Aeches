# Pulse Animation Refactor — Implementation Plan

**Status:** Approved, ready to implement.
**Scope:** Replace the imperative `@State` + `repeatForever` + `onChange` pulse machinery (seat highlight pulse and Next Street button pulse) with a declarative `TimelineView`-driven pulse that is a pure function of time and its on/off input. iOS / SwiftUI.

This document is self-contained. An AI or developer should be able to execute the refactor from this file alone. Read it fully before editing.

**Goal:** after this refactor there must be **no leftover pulse state, lifecycle hooks, or cancellation code** — `pulseScale`, `nextStreetPulse`, and the `onAppear`/`onChange` pulse handlers are all gone.

---

## 1. Files involved

| File | Role |
|---|---|
| `Aeches/SeatSelectionView.swift` | `SeatButtonView` — owns the seat highlight **pulse**. **Primary file.** |
| `Aeches/HandEntryView.swift` | `ControlBar` — owns the **Next Street button pulse**; also `commitAction` (one cosmetic note, no change required). |

Nothing else changes. **Do not touch** routing, state, or logic: `highlightedSeat`, `streetClosedDecisively`, `settleAfterCommit`, `commitAction`/`finishSwipe`/tap routing, `recordAction`, `recomputeDerivedState`, street-close, fold-out, rewind. The pulse only *reads* its inputs.

---

## 2. Why this refactor (context)

The pulse is currently **imperative per-view animation state**: each view holds a `@State` scale, starts a `repeatForever` animation in `onAppear`/`onChange`, and must manually cancel it. This pattern caused two separate bugs already:
1. The `repeatForever` was never cancelled (plain assignment doesn't stop a repeating animation).
2. A `scaleEffect(isActive ? pulseScale : 1.0)` gate decoupled the rendered scale from the property the cancel acted on, so the pulse stuck whenever the highlight moved without an ambient `withAnimation` (e.g. action buttons).

Both are currently *fixed*, but the machinery remains fragile (depends on `repeatForever` cancellation semantics + lifecycle callbacks firing + ambient transactions). The refactor removes the machinery entirely.

### The principle
**The pulse is a pure function of `(time, isOn)`.** No animation state, no `repeatForever`, no `onChange`, no cancellation. `TimelineView(.animation(paused:))` ticks only while the pulse is on; when off, the scale is literally `1.0`. This makes "stuck pulse" impossible by construction and removes all dependence on how the highlight moved.

---

## 3. Current architecture (exact code to replace)

### 3.1 `SeatButtonView` (`SeatSelectionView.swift`)

State property (near the top of the struct, ~line 365):
```swift
@State private var pulseScale: CGFloat = 1.0
```

End of `var body` (~lines 619–644) — the ZStack is closed, then:
```swift
        }
        .frame(width: size, height: size)
        // Scale always reads pulseScale (NOT gated by isActive): the onChange below drives it to 1.0
        // with a finite animation when the seat deactivates, which is what actually cancels the
        // repeatForever. Gating here would hide that cancel from the rendered scale and leave the
        // pulse stuck whenever the highlight moves without an ambient animation (e.g. action buttons).
        .scaleEffect(pulseScale)
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                pulseScale = 1.0
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulseScale = 1.08
                }
            } else {
                // Wrap in an explicit finite animation so the in-flight repeatForever is actually
                // cancelled — assigning the value plainly does not stop a repeating animation.
                withAnimation(.easeInOut(duration: 0.2)) { pulseScale = 1.0 }
            }
        }
    }
}
```

> Note: `isActive` is already the single on/off input. The parent passes `activeSeat: streetClosedDecisively ? nil : highlightedSeat` to `TableOvalView`, so `isActive` is false for every seat during a decisive close — the pulse logic does not need to know about `streetClosedDecisively` directly.

### 3.2 `ControlBar` (`HandEntryView.swift`)

State property (~line 1406):
```swift
@State private var nextStreetPulse: CGFloat = 1.0
```

`nextStreetButton` (~lines 1459–1509):
```swift
    private var nextStreetButton: some View {
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
        // Pulses only on a decisive street close — the cue hands off here from the seat ring.
        .scaleEffect(nextStreetPulsing ? nextStreetPulse : 1.0)
        .onChange(of: nextStreetPulsing) { _, pulsing in
            if pulsing {
                nextStreetPulse = 1.0
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    nextStreetPulse = 1.06
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { nextStreetPulse = 1.0 }
            }
        }
    }
```

`nextStreetPulsing: Bool` is the on/off input (already a prop on `ControlBar`, passed `streetClosedDecisively` from the call site). The `.shadow(...)` glow line is a discrete (non-repeating) state change — **keep it**; only the scale machinery is being replaced.

---

## 4. Target architecture (exact new code)

### 4.1 `SeatButtonView` — replace the pulse machinery with `TimelineView`

**Delete** the `@State private var pulseScale` property.

**Replace** the `var body` opening so the existing ZStack is moved into a private `seatBody`, and `body` wraps it in a `TimelineView`. Concretely:

Change the body from:
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
to:
```swift
    var body: some View {
        // Pulse is a pure function of time × isActive. The timeline ticks only while this seat is on
        // the clock (paused otherwise → no per-frame cost, and scale is exactly 1.0 when inactive).
        TimelineView(.animation(paused: !isActive)) { context in
            seatBody
                .scaleEffect(pulseScale(at: context.date))
        }
    }

    private var seatBody: some View {
        ZStack {
            ... existing content unchanged ...
        }
        .frame(width: size, height: size)
    }

    /// Gentle highlight pulse (1.0 → 1.04). Pure function of the timeline clock; returns 1.0 when the
    /// seat isn't on the clock so an inactive seat never scales.
    private func pulseScale(at date: Date) -> CGFloat {
        guard isActive else { return 1.0 }
        let phase = (sin(date.timeIntervalSinceReferenceDate * 3.5) + 1) / 2   // 0…1
        return 1.0 + 0.04 * phase
    }
```

Notes:
- Keep the ZStack's existing `.frame(width: size, height: size)` on `seatBody` (it was the last modifier before `.scaleEffect`).
- Everything inside the ZStack (shadows, border, glow, badges, size pill, HERO label, dealer button, `isActive`-driven `borderColor`/`shadow`) is **unchanged** — those are discrete states, not pulse machinery.
- Amplitude is intentionally small (`0.04`) so the time-based pulse has no visible "pop" if a seat activates mid-sine. Do not raise it back to `0.08`.
- `sin` resolves via the existing `import SwiftUI` (Foundation). If the compiler can't find it, add `import Foundation`.

### 4.2 `ControlBar` — same treatment for the Next Street button

**Delete** the `@State private var nextStreetPulse` property.

**Replace** `nextStreetButton` so the Button moves into a private `nextStreetButtonBody` and `nextStreetButton` wraps it in a `TimelineView`:
```swift
    private var nextStreetButton: some View {
        TimelineView(.animation(paused: !nextStreetPulsing)) { context in
            nextStreetButtonBody
                .scaleEffect(nextStreetPulseScale(at: context.date))
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

    /// Gentle pulse (1.0 → 1.05) while a decisive close hands the cue to this button.
    private func nextStreetPulseScale(at date: Date) -> CGFloat {
        guard nextStreetPulsing else { return 1.0 }
        let phase = (sin(date.timeIntervalSinceReferenceDate * 3.5) + 1) / 2
        return 1.0 + 0.05 * phase
    }
```

The `.shadow(...)` glow stays inside `nextStreetButtonBody` exactly as-is (discrete state on `nextStreetPulsing`).

### 4.3 `commitAction` — leave as-is (documentation note only)

`commitAction` (`HandEntryView.swift`) is wrapped in `withAnimation(.easeInOut(duration: 0.15))`. This was originally added partly as a belt-and-suspenders for the old pulse cancel. After this refactor it is **no longer needed for the pulse**, but it still provides smooth `isActive`-driven border/glow transitions on a button press (matching the swipe path). **Keep it** — it is intentional, not leftover. No edit required; do not remove it expecting a pulse change.

---

## 5. Deletions checklist (no leftover code)

- [ ] `@State private var pulseScale: CGFloat = 1.0` in `SeatButtonView`
- [ ] `.scaleEffect(pulseScale)` modifier (replaced by `scaleEffect(pulseScale(at:))` inside the TimelineView)
- [ ] `SeatButtonView`'s `.onAppear { … }` pulse starter
- [ ] `SeatButtonView`'s `.onChange(of: isActive) { … }` pulse handler
- [ ] `@State private var nextStreetPulse: CGFloat = 1.0` in `ControlBar`
- [ ] `ControlBar`'s `.scaleEffect(nextStreetPulsing ? nextStreetPulse : 1.0)` modifier
- [ ] `ControlBar`'s `.onChange(of: nextStreetPulsing) { … }` pulse handler

After editing, grep to confirm zero references remain:
```
grep -rn "pulseScale\|nextStreetPulse\b\|repeatForever" Aeches/*.swift
```
Expected result: **no matches** (no `repeatForever` anywhere in the pulse paths). If `repeatForever` appears elsewhere unrelated to pulsing, leave it.

---

## 6. Why this is safe (cannot affect other systems)

- The new code reads only `isActive` (seat) and `nextStreetPulsing` (button) — the **same inputs** the old code read. No new inputs, no writes to any model/state.
- `TimelineView` is a pure layout/redraw container; wrapping a seat or a button does not change its frame, position, gesture attachment, or hit-testing. The seat's `DragGesture` is applied by the parent (`TableOvalView`) on the positioned view, not inside `SeatButtonView`, so it is untouched.
- `paused: !isActive` / `paused: !nextStreetPulsing` means only the on-the-clock seat (and the button only during a decisive close) ever ticks — no per-frame cost for the other ~9 seats.
- No routing, street-close, fold-out, rewind, or card logic is read or modified.

---

## 7. Acceptance test scenarios

Build, then verify by hand (6-handed unless noted):

1. **Exactly one pulse:** during recording, only the on-the-clock seat pulses; all others are still.
2. **Button input:** UTG → press Raise → only UTG+1 pulses (UTG calm). Press Fold down the line → only the new on-clock seat pulses; previously-acted/folded seats are still. (This was the bug that motivated the refactor — confirm it's gone.)
3. **Swipe input:** same as #2 via swipes — identical result.
4. **Tap-cycle:** tapping the on-clock seat to cycle keeps that seat pulsing throughout.
5. **Decisive close:** a swipe/button that closes the round → the acted seat goes fully plain (no ring, no pulse), and the **Flop/Turn/River/Showdown** button pulses.
6. **Tap-completed round:** tap-cycling the last seat to a closing action → seat keeps pulsing, Next Street button is lit but **not** pulsing.
7. **Rewind:** rewinding back to an on-clock seat resumes its pulse; rewinding out of a decisive close moves the pulse from the button back to the seat.
8. **New hand:** after dealing, the first actor pulses; no stale pulse anywhere.
9. **Performance/visual:** no flicker, no "pop" when a seat activates, no seat stuck enlarged.

---

## 8. DRY / architecture principles

- **Pulse = pure function of `(time, isOn)`.** No animation `@State`, no `repeatForever`, no manual cancellation — the entire "stuck pulse" bug class is removed by construction.
- **One on/off input per pulse:** `isActive` for seats, `nextStreetPulsing` for the button. These remain the single sources of truth, set by the existing routing/state — the refactor does not add a parallel signal.
- **Discrete highlight states stay discrete:** border width, border color, glow shadow, HERO/dealer chrome are driven directly by `isActive`/`nextStreetEnabled`/`nextStreetPulsing` and are left exactly as they are — only the continuous *scale pulse* moves to `TimelineView`.
