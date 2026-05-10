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

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let cy = h / 2
            let rx = w * 0.42
            let ry = h * 0.38

            ZStack {
                // ── Felt table ────────────────────────────────────────
                TableFeltShape(rx: rx, ry: ry)
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#26614A"), Color(hex: "#123A26"), Color(hex: "#081E14")],
                            center: UnitPoint(x: 0.36, y: 0.3),
                            startRadius: 0,
                            endRadius: max(w, h) * 0.7
                        )
                    )
                    .frame(width: w, height: h)

                // Rail
                Ellipse()
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "#F0C868"), Color(hex: "#D4A33E"), Color(hex: "#BC8A2A"), Color(hex: "#A47220")],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: w * 0.055
                    )
                    .frame(width: rx * 2 + w * 0.055, height: ry * 2 + w * 0.055)

                // Brass pinstripe
                Ellipse()
                    .stroke(Color(hex: "#C99A3A"), lineWidth: 1.5)
                    .frame(width: rx * 1.85, height: ry * 1.85)

                // Inner shadow groove
                Ellipse()
                    .stroke(Color.black.opacity(0.6), lineWidth: 2.5)
                    .frame(width: rx * 1.82, height: ry * 1.82)

                // Stitching ring
                Ellipse()
                    .stroke(Color(hex: "#FFE6A0").opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: rx * 1.65, height: ry * 1.65)

                // HH watermark
                Text("HH")
                    .font(.custom("Georgia", size: 32))
                    .fontWeight(.black)
                    .tracking(-2)
                    .foregroundStyle(Color.gold.opacity(0.08))

                // Dealer notch label
                Text("DEALER")
                    .font(.custom("Arial", size: 8))
                    .fontWeight(.heavy)
                    .tracking(2.5)
                    .foregroundStyle(Color.gold.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#1A1205"))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.gold.opacity(0.4), lineWidth: 1))
                    .position(x: cx, y: cy - ry * 0.88)

                // ── Seats ─────────────────────────────────────────────
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
            }
            .frame(width: w, height: h)
        }
        .frame(height: 280)
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

    private var bg: Color {
        switch state?.action {
        case .fold:          return Color.foldRedBg
        case .call, .check:  return Color.winGreenBg
        case .open, .raise:  return Color(hex: "#221C0A")
        case nil:            return isHero ? Color.feltGreen : Color.surface2
        }
    }

    private var border: Color {
        if isActive { return Color.gold }
        switch state?.action {
        case .fold:          return Color.foldRed
        case .call, .check:  return Color.winGreen
        case .open, .raise:  return Color.gold
        case nil:            return isHero ? Color.gold : Color.borderDark
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
            Circle()
                .fill(bg)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle().stroke(border, lineWidth: isActive ? 2.5 : 2)
                )
                .shadow(color: isActive ? Color.gold.opacity(0.5) : .clear, radius: 8)

            VStack(spacing: 1) {
                Text(label)
                    .font(.custom("Arial", size: 11))
                    .fontWeight(.bold)
                    .foregroundStyle(border)
                if isHero && state == nil {
                    Text("YOU")
                        .font(.custom("Arial", size: 7))
                        .foregroundStyle(Color.gold.opacity(0.6))
                }
            }

            if hasButton {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.gold, lineWidth: 1.5))
                    Text("D")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Color.black)
                }
                .offset(x: 16, y: -16)
            }
        }
        .frame(width: 44, height: 44)
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
