import SwiftUI

// MARK: - Table Oval View

struct TableOvalView: View {
    let tableSize: Int
    let heroSeat: Int?
    let buttonSeat: Int?
    let seatStates: [Int: SeatState]
    let activeSeat: Int?
    let positions: [Int: String]
    let onSeatTap: (Int) -> Void
    var instruction: String? = nil
    var actionText: String? = nil

    @State private var instructionPulse: Bool = false

    // Rail gap at top — trim coordinates (0=right, 0.25=bottom, 0.5=left, 0.75=top)
    private let gapCenter: Double = 0.75
    private let gapHalf:   Double = 0.07   // ~50° of arc left open for dealer

    var body: some View {
        GeometryReader { geo in
            let w  = geo.size.width
            let h  = geo.size.height
            let cx = w / 2
            let cy = h / 2
            let rx = w * 0.40
            let ry = h * 0.36
            let railW = w * 0.058

            ZStack {

                // ── Depth shadows ──────────────────────────────────────
                Ellipse()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: rx * 2 + railW + 18, height: ry * 2 + railW + 10)
                    .offset(y: 14)
                    .blur(radius: 14)

                Ellipse()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: rx * 2 + railW + 8, height: ry * 2 + railW + 4)
                    .offset(y: 7)
                    .blur(radius: 5)

                // ── Outer rim ─────────────────────────────────────────
                Ellipse()
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

                // Arc 1: from gapEnd → right side (trim: gapCenter+gapHalf → 1.0)
                Ellipse()
                    .trim(from: gapCenter + gapHalf, to: 1.0)
                    .stroke(railGradient, style: StrokeStyle(lineWidth: railW, lineCap: .round))
                    .frame(width: rx * 2, height: ry * 2)

                // Arc 2: from right side → gapStart (trim: 0 → gapCenter-gapHalf)
                Ellipse()
                    .trim(from: 0, to: gapCenter - gapHalf)
                    .stroke(railGradient, style: StrokeStyle(lineWidth: railW, lineCap: .round))
                    .frame(width: rx * 2, height: ry * 2)

                // ── Specular highlight on top of rail ──────────────────
                Ellipse()
                    .trim(from: gapCenter + gapHalf, to: 1.0)
                    .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: railW * 0.35, lineCap: .round))
                    .frame(width: rx * 2, height: ry * 2)
                    .offset(y: -railW * 0.15)

                Ellipse()
                    .trim(from: 0, to: gapCenter - gapHalf)
                    .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: railW * 0.35, lineCap: .round))
                    .frame(width: rx * 2, height: ry * 2)
                    .offset(y: -railW * 0.15)

                // ── Felt surface ───────────────────────────────────────
                Ellipse()
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
                    .frame(width: rx * 1.82, height: ry * 1.82)

                // Felt vignette
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.clear, Color.black.opacity(0.5)],
                            center: .center,
                            startRadius: min(rx, ry) * 0.5,
                            endRadius: max(rx, ry) * 0.95
                        )
                    )
                    .frame(width: rx * 1.82, height: ry * 1.82)

                // ── Brass pinstripe — two arcs ─────────────────────────
                let pinW: CGFloat = rx * 1.72
                let pinH: CGFloat = ry * 1.72

                Ellipse()
                    .trim(from: gapCenter + gapHalf + 0.01, to: 1.0)
                    .stroke(Color(hex: "#C99A3A"), lineWidth: 1.5)
                    .frame(width: pinW, height: pinH)

                Ellipse()
                    .trim(from: 0, to: gapCenter - gapHalf - 0.01)
                    .stroke(Color(hex: "#C99A3A"), lineWidth: 1.5)
                    .frame(width: pinW, height: pinH)

                // ── Inner shadow groove ────────────────────────────────
                Ellipse()
                    .stroke(Color.black.opacity(0.65), lineWidth: 3)
                    .frame(width: pinW - 4, height: pinH - 4)

                // ── Stitching ring ─────────────────────────────────────
                Ellipse()
                    .stroke(
                        Color(hex: "#FFE6A0").opacity(0.09),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    .frame(width: rx * 1.52, height: ry * 1.52)

                // ── HH watermark / phase instruction / action text ────
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
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                                instructionPulse = true
                            }
                        }
                        .onChange(of: instruction) { _, _ in
                            instructionPulse = false
                            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                                instructionPulse = true
                            }
                        }
                } else if let actionText {
                    Text(actionText)
                        .font(.custom("Georgia", size: 13))
                        .fontWeight(.semibold)
                        .tracking(1.5)
                        .foregroundStyle(Color.gold.opacity(0.38))
                        .transition(.opacity)
                        .onAppear { instructionPulse = false }
                } else {
                    Text("HH")
                        .font(.custom("Georgia", size: 30))
                        .fontWeight(.black)
                        .tracking(-2)
                        .foregroundStyle(Color.gold.opacity(0.07))
                        .transition(.opacity)
                        .onAppear { instructionPulse = false }
                }

                // ── Seats ──────────────────────────────────────────────
                ForEach(0..<tableSize, id: \.self) { i in
                    let pos = seatPosition(index: i, total: tableSize, cx: cx, cy: cy, rx: rx, ry: ry)
                    SeatButtonView(
                        index: i,
                        isHero: heroSeat == i,
                        hasButton: buttonSeat == i,
                        state: seatStates[i],
                        isActive: activeSeat == i,
                        position: positions[i]
                    )
                    .position(x: pos.x, y: pos.y)
                    .onTapGesture { onSeatTap(i) }
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
        .frame(height: 300)
        .animation(.easeInOut(duration: 0.2), value: tableSize)
        .animation(.easeInOut(duration: 0.35), value: instruction)
    }
}

// MARK: - Seat Button View

struct SeatState {
    enum Action { case fold, call, check, open, raise, foldedOut }
    var action: Action?
    var betLevel: Int = 0
}

struct SeatButtonView: View {
    let index: Int
    let isHero: Bool
    let hasButton: Bool
    let state: SeatState?
    let isActive: Bool
    var position: String? = nil

    private let size: CGFloat = 50
    @State private var pulseScale: CGFloat = 1.0

    private var isFoldedOut: Bool { state?.action == .foldedOut }

    private var bg: LinearGradient {
        if isFoldedOut {
            return LinearGradient(colors: [Color(hex: "#111111"), Color(hex: "#0A0A0A")], startPoint: .top, endPoint: .bottom)
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
        switch state?.action {
        case .fold:          return Color.foldRed
        case .call, .check:  return Color.winGreen
        case .open, .raise:  return Color.gold
        case nil:            return isHero ? Color.goldLight : Color(hex: "#444444")
        case .foldedOut:     return Color(hex: "#2A2A2A")
        }
    }

    private var labelColor: Color {
        if isFoldedOut { return Color(hex: "#444444") }
        switch state?.action {
        case .fold:          return Color.foldRed
        case .call, .check:  return Color.winGreen
        case .open, .raise:  return Color.gold
        case nil, .foldedOut: return Color.white
        }
    }

    private var label: String {
        switch state?.action {
        case .fold:   return "✕"
        case .call:   return "✓"
        case .check:  return "—"
        case .open, .raise:
            let level = state?.betLevel ?? 1
            switch level {
            case 1:  return "↑↑"
            case 2:  return "↑↑↑"
            case 3:  return "↑↑↑↑"
            default: return "↑"
            }
        case .foldedOut: return position ?? "\(index + 1)"
        case nil:        return position ?? "\(index + 1)"
        }
    }

    var body: some View {
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

            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: state == nil || isFoldedOut ? 11 : 13, weight: .bold, design: .rounded))
                    .foregroundStyle(labelColor)
                if isHero && state == nil {
                    Text("YOU")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.goldLight.opacity(0.8))
                }
            }
            .opacity(isFoldedOut ? 0.5 : 1.0)

            if hasButton {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .overlay(Circle().stroke(Color.gold, lineWidth: 1.5))
                    Text("D")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Color.black)
                }
                .offset(x: 18, y: -18)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isActive ? pulseScale : 1.0)
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulseScale = 1.08
                }
            } else {
                pulseScale = 1.0
            }
        }
    }
}

// MARK: - Felt Shape (clips dealer gap at top)

struct TableFeltShape: Shape {
    let rx: CGFloat
    let ry: CGFloat

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        var path = Path()
        path.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        return path
    }
}

// MARK: - Seat Position Math

func seatPosition(index: Int, total: Int, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) -> CGPoint {
    let dealerGap: Double = 75
    let startDeg: Double = 90 - dealerGap / 2
    let arcDeg: Double = 360 - dealerGap
    let step = total <= 1 ? 0.0 : arcDeg / Double(total - 1)
    let deg = startDeg - Double(index) * step
    let rad = deg * .pi / 180
    return CGPoint(
        x: cx + rx * 1.15 * cos(rad),
        y: cy - ry * 1.15 * sin(rad)
    )
}

