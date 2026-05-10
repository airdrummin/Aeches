import SwiftUI

struct SeatSelectionView: View {
    var session: Session
    var onSeatSelected: (Int, Int) -> Void  // (heroSeatIndex, tableSize)
    var onBack: () -> Void

    @State private var tableSize: Int = 9
    @State private var hoveredSeat: Int? = nil

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Nav Bar ───────────────────────────────────────────
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.gold)
                    }
                    Spacer()
                    Text("Select Your Seat")
                        .font(.custom("Arial", size: 17))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.textBody)
                    Spacer()
                    // Balance the chevron
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.clear)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // ── Table ─────────────────────────────────────────────
                TableOvalView(
                    tableSize: tableSize,
                    heroSeat: nil,
                    buttonSeat: nil,
                    seatStates: [:],
                    activeSeat: hoveredSeat,
                    onSeatTap: { seat in
                        onSeatSelected(seat, tableSize)
                    }
                )
                .padding(.horizontal, 8)

                // ── Table Size Picker ─────────────────────────────────
                HStack(spacing: 6) {
                    Text("Table Size")
                        .font(.custom("Arial", size: 11))
                        .fontWeight(.semibold)
                        .tracking(0.8)
                        .foregroundStyle(Color.textMuted)

                    Spacer()

                    ForEach([6, 8, 9, 10], id: \.self) { size in
                        Button(action: { tableSize = size }) {
                            Text("\(size)")
                                .font(.custom("Arial", size: 11))
                                .fontWeight(.bold)
                                .frame(width: 28, height: 20)
                                .background(tableSize == size ? Color.gold : Color.surface3)
                                .foregroundStyle(tableSize == size ? Color(hex: "#0D0D0D") : Color.textMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // ── Instruction ───────────────────────────────────────
                Text("Tap your seat — it stays locked for the session")
                    .font(.custom("Arial", size: 13))
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

// MARK: - Table Oval View

struct TableOvalView: View {
    let tableSize: Int
    let heroSeat: Int?
    let buttonSeat: Int?
    let seatStates: [Int: SeatState]
    let activeSeat: Int?
    let onSeatTap: (Int) -> Void

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

                // ── HH watermark ───────────────────────────────────────
                Text("HH")
                    .font(.custom("Georgia", size: 30))
                    .fontWeight(.black)
                    .tracking(-2)
                    .foregroundStyle(Color.gold.opacity(0.07))

                // ── Seats ──────────────────────────────────────────────
                ForEach(0..<tableSize, id: \.self) { i in
                    let pos = seatPosition(index: i, total: tableSize, cx: cx, cy: cy, rx: rx, ry: ry)
                    SeatButtonView(
                        index: i,
                        isHero: heroSeat == i,
                        hasButton: buttonSeat == i,
                        state: seatStates[i],
                        isActive: activeSeat == i
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
    }
}

// MARK: - Seat Button View

struct SeatState {
    enum Action { case fold, call, check, open, raise }
    var action: Action?
    var sizeLabel: String?
}

struct SeatButtonView: View {
    let index: Int
    let isHero: Bool
    let hasButton: Bool
    let state: SeatState?
    let isActive: Bool

    private let size: CGFloat = 50

    private var bg: LinearGradient {
        switch state?.action {
        case .fold:
            return LinearGradient(colors: [Color.foldRedBg, Color.foldRedBg.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        case .call, .check:
            return LinearGradient(colors: [Color.winGreenBg, Color.winGreenBg.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        case .open, .raise:
            return LinearGradient(colors: [Color(hex: "#2A2210"), Color(hex: "#1A1508")], startPoint: .top, endPoint: .bottom)
        case nil:
            if isHero {
                return LinearGradient(colors: [Color(hex: "#1F4A35"), Color(hex: "#0F2A1D")], startPoint: .top, endPoint: .bottom)
            }
            return LinearGradient(colors: [Color(hex: "#2A2A2A"), Color(hex: "#1A1A1A")], startPoint: .top, endPoint: .bottom)
        }
    }

    private var borderColor: Color {
        if isActive { return Color.gold }
        switch state?.action {
        case .fold:          return Color.foldRed
        case .call, .check:  return Color.winGreen
        case .open, .raise:  return Color.gold
        case nil:            return isHero ? Color.gold : Color(hex: "#444444")
        }
    }

    private var label: String {
        switch state?.action {
        case .fold:   return "✕"
        case .call:   return "✓"
        case .check:  return "—"
        case .open:   return "↑"
        case .raise:  return state?.sizeLabel ?? "↑↑"
        case nil:     return "\(index + 1)"
        }
    }

    var body: some View {
        ZStack {
            // Base shadow
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: size, height: size)
                .offset(y: 3)
                .blur(radius: 4)

            // Seat circle
            Circle()
                .fill(bg)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: isActive || isHero ? 2.5 : 1.5)
                )
                // Top specular highlight
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
                .shadow(color: isActive ? Color.gold.opacity(0.6) : isHero ? Color.gold.opacity(0.2) : .clear, radius: isActive ? 10 : 6)

            // Label
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: state == nil ? 15 : 13, weight: .bold, design: .rounded))
                    .foregroundStyle(state == nil ? Color.white : borderColor)
                if isHero && state == nil {
                    Text("YOU")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.gold.opacity(0.8))
                }
            }

            // Dealer button badge
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

#Preview {
    SeatSelectionView(
        session: Session(type: .cash, name: "Test", date: Date(), tableSize: 9, heroSeatIndex: 0),
        onSeatSelected: { _, _ in },
        onBack: {}
    )
}
