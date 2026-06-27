import SwiftUI

// MARK: - Pulse

/// A pure-function pulse. Ticks only while `isActive` (paused otherwise → no per-frame cost and
/// phase is exactly 0). Exposes a 0…1 `phase` so each call site interpolates whatever it wants
/// (scale, opacity, shadow). This is the single source of pulse motion in the app — there is no
/// `@State`, no `repeatForever`, and no manual cancellation, so a "stuck pulse" is impossible by
/// construction. Amplitudes at call sites are intentionally small: the timeline samples the sine
/// at an arbitrary phase the instant a pulse turns on (no ramp-in), so amplitude *is* the
/// worst-case activation step — do not raise them.
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

// MARK: - Table Oval View

enum SwipeDirection { case up, down, left, right }

struct TableOvalView: View {
    let tableSize: Int
    let heroSeat: Int?
    let buttonSeat: Int?
    let seatStates: [Int: SeatState]
    let activeSeat: Int?
    let positions: [Int: String]
    var emptySeats: Set<Int> = []   // seats with no player — rendered as a dashed empty ring
    let onSeatTap: (Int) -> Void
    var onSeatSwipe: (Int, SwipeDirection) -> Void = { _, _ in }
    var instruction: String? = nil
    var actionText: String? = nil
    var minHeight: CGFloat = 300   // default = the original fixed 300; the Record screen passes a
    var maxHeight: CGFloat = 300   // flexible range so the felt fills the slack / eases when needed.

    // One unified gesture per seat classifies tap vs. swipe — no competing gestures.
    @State private var touchSeat: Int? = nil        // seat under the active touch
    @State private var touchMoved: Bool = false      // moved past the tap threshold (→ swipe, not tap)

    // Dealer gap at top, as a fraction of each shape's width on either side of top-center.
    // The pinstripe sits inside the rail (narrower frame), so a slightly larger fraction keeps
    // the two gaps visually aligned at the top. See `Racetrack`.
    private let railGapFrac: CGFloat = 0.15
    private let pinGapFrac:  CGFloat = 0.17

    var body: some View {
        GeometryReader { geo in
            let w  = geo.size.width
            let h  = geo.size.height
            let cx = w / 2
            let cy = h / 2
            let rx = w * 0.40
            // Aspect-lock: the vertical radius is derived from the horizontal one (a fixed
            // width:height ratio) rather than from the frame height, so the table can never
            // distort — extra frame height becomes pure margin around it. Real poker tables run
            // ~2:1; this racetrack uses 1.8:1 so the table itself fills most of the height it would
            // otherwise leave as margin. Width stays at 0.40·w because the side (cap) seats already
            // sit near the screen edge (see seatPosition). See DisplayLayoutPlan.md §#1.
            let ry = rx / 1.8
            let railW = w * 0.045

            ZStack {

                // ── Depth shadows ──────────────────────────────────────
                Racetrack()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: rx * 2 + railW + 18, height: ry * 2 + railW + 10)
                    .offset(y: 14)
                    .blur(radius: 14)

                Racetrack()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: rx * 2 + railW + 8, height: ry * 2 + railW + 4)
                    .offset(y: 7)
                    .blur(radius: 5)

                // ── Outer rim ─────────────────────────────────────────
                Racetrack()
                    .fill(Color(hex: "#1A0E00"))
                    .frame(width: rx * 2 + railW + 3, height: ry * 2 + railW + 3)

                // ── Gold rail — two arcs with gap at top ───────────────
                let railGradient = LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#F5D070"), location: 0.0),
                        .init(color: Color(hex: "#E8C055"), location: 0.15),
                        .init(color: Color(hex: "#C9983A"), location: 0.45),
                        .init(color: Color(hex: "#A47220"), location: 0.75),
                        .init(color: Color(hex: "#8A5E12"), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Rail — a single open racetrack stroke with a dealer gap at top-center; the round
                // line cap rounds off the two rail tips that frame the dealer station.
                Racetrack(gapFrac: railGapFrac)
                    .stroke(railGradient, style: StrokeStyle(lineWidth: railW, lineCap: .round))
                    .frame(width: rx * 2, height: ry * 2)

                // ── Specular highlight on top of rail ──────────────────
                Racetrack(gapFrac: railGapFrac)
                    .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: railW * 0.35, lineCap: .round))
                    .frame(width: rx * 2, height: ry * 2)
                    .offset(y: -railW * 0.15)

                // ── Felt surface ───────────────────────────────────────
                Racetrack()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color(hex: "#2E7055"), location: 0.0),
                                .init(color: Color(hex: "#1A4A34"), location: 0.45),
                                .init(color: Color(hex: "#0D2E1C"), location: 0.75),
                                .init(color: Color(hex: "#061810"), location: 1.0),
                            ],
                            center: UnitPoint(x: 0.42, y: 0.35),
                            startRadius: 0,
                            endRadius: max(rx, ry) * 1.6
                        )
                    )
                    .frame(width: rx * 1.88, height: ry * 1.88)

                // Felt vignette
                Racetrack()
                    .fill(
                        RadialGradient(
                            colors: [Color.clear, Color.black.opacity(0.5)],
                            center: .center,
                            startRadius: min(rx, ry) * 0.5,
                            endRadius: max(rx, ry) * 0.95
                        )
                    )
                    .frame(width: rx * 1.88, height: ry * 1.88)

                // ── Brass pinstripe — single open racetrack ────────────
                let pinW: CGFloat = rx * 1.72
                let pinH: CGFloat = ry * 1.72

                Racetrack(gapFrac: pinGapFrac)
                    .stroke(Color(hex: "#C99A3A"), lineWidth: 1.5)
                    .frame(width: pinW, height: pinH)

                // ── Inner shadow groove ────────────────────────────────
                Racetrack()
                    .stroke(Color.black.opacity(0.65), lineWidth: 3)
                    .frame(width: pinW - 4, height: pinH - 4)

                // ── Stitching ring ─────────────────────────────────────
                Racetrack()
                    .stroke(
                        Color(hex: "#FFE6A0").opacity(0.09),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    .frame(width: rx * 1.52, height: ry * 1.52)

                // ── HH watermark / phase instruction / action text ────
                // When both instruction and actionText are provided (hand-closed phase: outcome above,
                // tap-to-deal below), they stack. Otherwise each shows alone as before.
                if let instruction {
                    VStack(spacing: 6) {
                        if let actionText {
                            Text(actionText)
                                .font(.custom("Georgia", size: 11))
                                .fontWeight(.semibold)
                                .tracking(2)
                                .foregroundStyle(Color.gold.opacity(0.55))
                                .transition(.opacity)
                        }
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
                } else if let actionText {
                    Text(actionText)
                        .font(.custom("Georgia", size: 13))
                        .fontWeight(.semibold)
                        .tracking(1.5)
                        .foregroundStyle(Color.gold.opacity(0.38))
                        .transition(.opacity)
                } else {
                    Text("HH")
                        .font(.custom("Georgia", size: 30))
                        .fontWeight(.black)
                        .tracking(-2)
                        .foregroundStyle(Color.gold.opacity(0.07))
                        .transition(.opacity)
                }

                // ── Seats ──────────────────────────────────────────────
                ForEach(0..<tableSize, id: \.self) { i in
                    let pos = seatPosition(index: i, total: tableSize, cx: cx, cy: cy, rx: rx, ry: ry)
                    SeatButtonView(
                        index: i,
                        isHero: heroSeat == i,
                        state: seatStates[i],
                        isActive: activeSeat == i,
                        position: positions[i],
                        isEmpty: emptySeats.contains(i)
                    )
                    .position(x: pos.x, y: pos.y)
                    // ONE gesture per seat classifies tap vs. swipe. A single
                    // DragGesture(minimumDistance: 0) avoids the gesture-arbitration conflicts that
                    // break taps when .onTapGesture / .simultaneousGesture / .highPriorityGesture are
                    // layered together. At minimumDistance 0, onEnded fires even for a stationary tap.
                    // Lessons (do not "refactor" back into multiple recognizers): SwiftUI can't reliably
                    // split tap/swipe across separate gestures (iOS 18 worsens it). Sizing is no longer
                    // a seat gesture — it lives on the Raise/Bet control-bar buttons (see SizingOverhaul.md).
                    // Tuning dial: swipe threshold 12pt.
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if touchSeat != i {
                                    touchSeat = i
                                    touchMoved = false
                                }
                                let moved = (value.translation.width * value.translation.width
                                             + value.translation.height * value.translation.height).squareRoot()
                                if moved > 12 { touchMoved = true }   // it's a drag → swipe, not tap
                            }
                            .onEnded { value in
                                let seat = touchSeat ?? i
                                let t = value.translation
                                let moved = (t.width * t.width + t.height * t.height).squareRoot()
                                touchSeat = nil; touchMoved = false

                                if moved > 12 {
                                    if abs(t.width) > abs(t.height) {
                                        onSeatSwipe(seat, t.width > 0 ? .right : .left)
                                    } else {
                                        onSeatSwipe(seat, t.height > 0 ? .down : .up)   // y grows downward
                                    }
                                } else {
                                    onSeatTap(seat)                 // tap → cycle / jump / commit
                                }
                            }
                    )
                }

                // ── Dealer button — on the felt, in front of the seat ──
                // Placed along the seat→center line so it sits on the table (real-table read) and
                // stays on-screen for every seat, including the edges. `inset` = distance onto felt.
                if let btn = buttonSeat {
                    let seat = seatPosition(index: btn, total: tableSize, cx: cx, cy: cy, rx: rx, ry: ry)
                    let dx = cx - seat.x
                    let dy = cy - seat.y
                    let len = max(1, (dx * dx + dy * dy).squareRoot())
                    let inset: CGFloat = 40
                    DealerPuck()
                        .position(x: seat.x + dx / len * inset,
                                  y: seat.y + dy / len * inset)
                }

                // ── Dealer label — drawn last so it sits on top ────────
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(Color.gold.opacity(0.5))
                        .frame(width: 10, height: 1)
                    Text("DEALER")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(Color.gold)
                    Rectangle()
                        .fill(Color.gold.opacity(0.5))
                        .frame(width: 10, height: 1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(hex: "#0D0D0D"))
                        .overlay(Capsule().stroke(Color.gold.opacity(0.5), lineWidth: 1))
                )
                .shadow(color: Color.black.opacity(0.8), radius: 4, y: 2)
                .position(x: cx, y: cy - ry - railW * 0.1)

            }
            .frame(width: w, height: h)
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .animation(.easeInOut(duration: 0.2), value: tableSize)
        .animation(.easeInOut(duration: 0.35), value: instruction)
    }

}

// MARK: - Seat Button View

struct SeatState {
    enum Action { case fold, call, check, open, raise, foldedOut }
    var action: Action?
    var betLevel: Int = 0
    var priorActions: [Action] = []  // all actions this street except the current one, oldest first
    var sizeLabel: String? = nil     // size attached to the current bet/raise, e.g. "2.5x", "40%"
    var isAllIn: Bool = false        // seat is all-in (no chips left) — persists across streets
}

struct SeatButtonView: View {
    let index: Int
    let isHero: Bool
    let state: SeatState?
    let isActive: Bool
    var position: String? = nil
    var isEmpty: Bool = false        // no player here — a dashed empty ring, no label or action

    private let size: CGFloat = 50

    private var isFoldedOut: Bool { state?.action == .foldedOut }

    private var bg: LinearGradient {
        if isFoldedOut {
            return LinearGradient(colors: [Color(hex: "#111111"), Color(hex: "#0A0A0A")], startPoint: .top, endPoint: .bottom)
        }
        if state?.isAllIn == true {
            return LinearGradient(colors: [Color(hex: "#2E1F08"), Color(hex: "#1C1305")], startPoint: .top, endPoint: .bottom)
        }
        switch state?.action {
        case .fold:
            return LinearGradient(colors: [Color.foldRedBg, Color.foldRedBg.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        case .call, .check:
            return LinearGradient(colors: [Color.winGreenBg, Color.winGreenBg.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        case .open, .raise:
            return LinearGradient(colors: [Color(hex: "#2A2210"), Color(hex: "#1A1508")], startPoint: .top, endPoint: .bottom)
        case nil, .foldedOut:
            if isHero {
                return LinearGradient(colors: [Color(hex: "#1F4A35"), Color(hex: "#0F2A1D")], startPoint: .top, endPoint: .bottom)
            }
            return LinearGradient(colors: [Color(hex: "#2A2A2A"), Color(hex: "#1A1A1A")], startPoint: .top, endPoint: .bottom)
        }
    }

    private var borderColor: Color {
        if isFoldedOut { return Color(hex: "#2A2A2A") }
        if isActive { return Color.white }
        if state?.isAllIn == true { return Color(hex: "#E8943C") }   // amber — committed, persists
        if isHero {
            return state?.action == .fold ? Color.foldRed : Color.goldLight
        }
        switch state?.action {
        case .fold:          return Color.foldRed
        case .call, .check:  return Color.winGreen
        case .open, .raise:  return Color.gold
        case nil:            return Color(hex: "#444444")
        case .foldedOut:     return Color(hex: "#2A2A2A")
        }
    }

    private var labelColor: Color {
        if isFoldedOut { return Color(hex: "#444444") }
        if state?.isAllIn == true { return Color(hex: "#F5C277") }   // amber action symbol when all-in
        switch state?.action {
        case .fold:          return Color.foldRed
        case .call, .check:  return Color.winGreen
        case .open, .raise:  return Color.gold
        case nil, .foldedOut: return Color.white
        }
    }

    private var label: String {
        switch state?.action {
        case .fold:      return "✕"
        case .call:      return "✓"
        case .check:     return "—"
        case .open:      return "→"
        case .raise:     return ""   // handled by raiseArrows view builder
        case .foldedOut: return position ?? "\(index + 1)"
        case nil:        return position ?? "\(index + 1)"
        }
    }

    // 2D raise arrow layouts — pattern-recognisable at a glance, inspired by card pips.
    @ViewBuilder
    private var actionLabel: some View {
        if state?.action == .raise {
            raiseArrows(level: max(1, state?.betLevel ?? 1))
        } else {
            Text(label)
                .font(.system(size: state == nil || isFoldedOut ? 11 : 13, weight: .bold, design: .rounded))
                .foregroundStyle(labelColor)
        }
    }

    @ViewBuilder
    private func raiseArrows(level: Int) -> some View {
        switch level {
        case 1:
            // 2-bet — ↑↑ side by side (open raise)
            HStack(spacing: 1) {
                up(11); up(11)
            }
        case 2:
            // 3-bet — triangle: 1 top, 2 bottom
            VStack(spacing: 1) {
                up(10)
                HStack(spacing: 2) { up(10); up(10) }
            }
        case 3:
            // 4-bet — 2×2 grid
            VStack(spacing: 1) {
                HStack(spacing: 2) { up(9); up(9) }
                HStack(spacing: 2) { up(9); up(9) }
            }
        case 4:
            // 5-bet — arrow + "5" badge upper-right
            arrowWithBadge("5")
        default:
            // 6-bet+ — arrow + numeric badge upper-right
            arrowWithBadge("\(level + 1)")
        }
    }

    private func up(_ size: CGFloat) -> some View {
        Text("↑")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(labelColor)
    }

    private func arrowWithBadge(_ badge: String) -> some View {
        ZStack {
            up(12)
            Text(badge)
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(labelColor)
                .offset(x: 7, y: -7)
        }
    }

    // MARK: - Prior-action badges

    /// One prior action rendered as a small colored pill. `.open` is a post-flop bet (→); a
    /// `.raise` re-raises an existing bet (↑↑) — they are deliberately distinct.
    private struct Badge { let text: String; let bg: Color; let fg: Color }

    private func badge(for action: SeatState.Action) -> Badge? {
        switch action {
        case .open:      return Badge(text: "→",  bg: Color(hex: "#C9A84C"), fg: Color(hex: "#0D0D0D"))
        case .raise:     return Badge(text: "↑↑", bg: Color(hex: "#C9A84C"), fg: Color(hex: "#0D0D0D"))
        case .call:      return Badge(text: "✓",  bg: Color(hex: "#27AE60"), fg: Color(hex: "#0A2A0A"))
        case .check:     return Badge(text: "—",  bg: Color(hex: "#27AE60"), fg: Color(hex: "#0A2A0A"))
        case .fold:      return Badge(text: "✕",  bg: Color(hex: "#C0392B"), fg: .white)
        case .foldedOut: return nil
        }
    }

    private func pill(_ b: Badge) -> some View {
        Text(b.text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(b.fg)
            .frame(minWidth: 18)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(b.bg))
            .overlay(Capsule().stroke(Color(hex: "#0D0D0D"), lineWidth: 1.5))
    }

    /// Up to three badge slots around the seat's upper edge. 1→upper-left; 2→+top; 3→+upper-right;
    /// 4+→ upper-left collapses to a gray "+N" with the two most-recent actions at top/upper-right.
    @ViewBuilder
    private var badgeOverlay: some View {
        let priors = state?.priorActions ?? []
        if !priors.isEmpty && !isFoldedOut {
            let n = priors.count
            let upperLeft: Badge? = n >= 4
                ? Badge(text: "+\(n - 2)", bg: Color(hex: "#666666"), fg: Color(hex: "#111111"))
                : badge(for: priors[0])
            let top: Badge? = {
                switch n {
                case 0, 1: return nil
                case 2, 3: return badge(for: priors[1])
                default:   return badge(for: priors[n - 2])
                }
            }()
            let upperRight: Badge? = {
                switch n {
                case 0, 1, 2: return nil
                case 3:       return badge(for: priors[2])
                default:      return badge(for: priors[n - 1])
                }
            }()

            ZStack {
                if let b = upperLeft  { pill(b).offset(x: -size * 0.52, y: -size * 0.52) }
                if let b = top        { pill(b).offset(x: 0,            y: -size * 0.62) }
                if let b = upperRight { pill(b).offset(x:  size * 0.52, y: -size * 0.52) }
            }
        }
    }

    /// Size pill on the seat's bottom rim — shown only when the current action carries a size.
    /// Symbols are untouched; this rides the bottom edge, clear of the top-edge prior-action badges.
    /// Suppressed for an all-in seat — the amber ALL IN pill replaces it (sizing == "All-in" anyway).
    @ViewBuilder
    private var sizeOverlay: some View {
        if let label = state?.sizeLabel, !isFoldedOut, state?.isAllIn != true {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: "#E8D5A3"))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .frame(minWidth: 18)
                .background(Capsule().fill(Color(hex: "#14110A")))
                .overlay(Capsule().stroke(Color(hex: "#C9A84C"), lineWidth: 1.2))
                .offset(y: size * 0.5)
        }
    }

    /// Amber ALL IN pill on the seat's bottom rim, persisting every street once the seat is all-in.
    @ViewBuilder
    private var allInOverlay: some View {
        if state?.isAllIn == true, !isFoldedOut {
            Text("ALL IN")
                .font(.system(size: 7, weight: .black))
                .tracking(0.3)
                .foregroundStyle(Color(hex: "#2A1B08"))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color(hex: "#E8943C")))
                .offset(y: size * 0.5)
        }
    }

    var body: some View {
        if isEmpty {
            emptyBody
        } else {
            Pulse(isActive: isActive) { phase in
                seatBody.scaleEffect(1.0 + 0.04 * phase)
            }
        }
    }

    /// An unoccupied seat: a dashed grey ring with nothing inside, dimmed back. Still tappable (the
    /// gesture lives on the parent) so it can be filled back in during Edit-Seats mode.
    private var emptyBody: some View {
        Circle()
            .fill(Color(hex: "#0E0E0E"))
            .frame(width: size, height: size)
            .overlay(
                Circle().stroke(
                    Color(hex: "#3A3A3A"),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
            )
            .opacity(0.55)
    }

    private var seatBody: some View {
        ZStack {
            if !isFoldedOut {
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: size, height: size)
                    .offset(y: 3)
                    .blur(radius: 4)
            }

            Circle()
                .fill(bg)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: isFoldedOut ? 1 : (isActive || isHero ? 2.5 : 1.5))
                )
                .overlay(
                    Group {
                        if !isFoldedOut {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.12), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    }
                )
                .shadow(color: isFoldedOut ? .clear : (isActive ? Color.white.opacity(0.45) : isHero ? Color.goldLight.opacity(0.15) : .clear), radius: isActive ? 10 : 6)
                .opacity(isFoldedOut ? 0.35 : 1.0)
                .overlay(badgeOverlay)
                .overlay(sizeOverlay)
                .overlay(allInOverlay)

            VStack(spacing: 1) {
                actionLabel
                if isHero && !isFoldedOut {
                    Text("HERO")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.goldLight.opacity(0.8))
                }
            }
            .opacity(isFoldedOut ? 0.5 : 1.0)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Dealer Button Puck

/// The dealer button, drawn on the felt in front of a seat (positioned by `TableOvalView`) rather
/// than pinned to the seat's corner — so it reads like a real table and never clips off-screen on
/// edge seats.
struct DealerPuck: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.45), radius: 3)
                .overlay(Circle().stroke(Color.gold, lineWidth: 1.5))
            Text("D")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Color.black)
        }
    }
}

// MARK: - Racetrack Shape

/// A stadium / racetrack outline: flat top & bottom, semicircular left & right ends (corner
/// radius = half the frame height). The single source of the table's silhouette — every layer
/// (rail, felt, pinstripe, stitching, shadows) is framed from this so they all share one shape.
///
/// `gapFrac` > 0 opens a dealer gap centered on the TOP edge, given as a fraction of the frame
/// width on each side of top-center. The path then traces clockwise from the gap's right edge all
/// the way around to its left edge as one *open* sub-path, so a round-capped stroke yields the two
/// rail tips that frame the dealer station. `gapFrac == 0` is a closed loop (used for the fills).
struct Racetrack: Shape {
    var gapFrac: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r   = rect.height / 2          // corner radius = half-height → true stadium
        let cx  = rect.midX
        let cy  = rect.midY
        let top = rect.minY
        let bot = rect.maxY
        let leftC  = rect.minX + r         // center-x of the left end cap
        let rightC = rect.maxX - r         // center-x of the right end cap

        var p = Path()
        guard gapFrac > 0 else {
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
            return p
        }

        let gx = rect.width * gapFrac      // half-gap, measured along the top straight
        // Clockwise from the gap's right edge: top straight → right cap → bottom straight → left cap
        // → top straight back to the gap's left edge. Angles: 0°=east, 90°=south (y grows down).
        p.move(to: CGPoint(x: cx + gx, y: top))
        p.addLine(to: CGPoint(x: rightC, y: top))
        p.addRelativeArc(center: CGPoint(x: rightC, y: cy), radius: r,
                         startAngle: .degrees(-90), delta: .degrees(180))   // → (rightC, bot)
        p.addLine(to: CGPoint(x: leftC, y: bot))
        p.addRelativeArc(center: CGPoint(x: leftC, y: cy), radius: r,
                         startAngle: .degrees(90), delta: .degrees(180))    // → (leftC, top)
        p.addLine(to: CGPoint(x: cx - gx, y: top))
        return p
    }
}

// MARK: - Seat Position Math

/// Seats ride a racetrack just outside the rail. The ring is the rail expanded *anisotropically* —
/// only a hair on the sides (the end caps already sit near the screen edge) and more on the flat
/// top/bottom — so seats lift cleanly off the rail without the side seats clipping off-screen.
/// Seats are spread evenly by arc length over the perimeter minus a dealer gap centered at the top.
func seatPosition(index: Int, total: Int, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> CGPoint {
    let srx = rx + rx * 0.03           // side clearance — small; caps are tight to the screen edge
    let sry = ry + rx * 0.13           // top/bottom lift off the rail
    let r   = sry                      // stadium corner radius
    let a   = max(0, srx - sry)        // half-length of each flat straight
    let arc = CGFloat.pi * r           // length of one semicircular cap
    let perim = 4 * a + 2 * arc

    // Wide enough that the two top seats clear the dealer station and land on the rounded ends —
    // nobody sits where the dealer is, like a real table.
    let gapHalf: CGFloat = 0.115       // half the dealer gap, as a fraction of perimeter
    let usable  = 1 - 2 * gapHalf
    let f = total <= 1 ? 0.5 : gapHalf + usable * CGFloat(index) / CGFloat(total - 1)
    let d = f * perim                  // arc length, clockwise from top-center

    // Segments clockwise from top-center: topR(a) → rightCap(arc) → bottom(2a) → leftCap(arc) → topL(a)
    let x: CGFloat, y: CGFloat
    if d < a {                                         // top straight, center → right corner
        x = cx + d;                 y = cy - r
    } else if d < a + arc {                            // right cap, top → bottom
        let ang = -CGFloat.pi / 2 + (d - a) / r
        x = cx + a + r * cos(ang);  y = cy + r * sin(ang)
    } else if d < 3 * a + arc {                        // bottom straight, right → left
        x = cx + a - (d - a - arc); y = cy + r
    } else if d < 3 * a + 2 * arc {                    // left cap, bottom → top
        let ang = CGFloat.pi / 2 + (d - 3 * a - arc) / r
        x = cx - a + r * cos(ang);  y = cy + r * sin(ang)
    } else {                                           // top straight, left corner → center
        x = cx - a + (d - 3 * a - 2 * arc); y = cy - r
    }
    return CGPoint(x: x, y: y)
}

