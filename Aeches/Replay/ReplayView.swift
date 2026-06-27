import SwiftUI

/// Read-only step-through of a saved hand. Renders the real table + card strip + transcript purely
/// from the `Hand` via the Phase 3 functions — advanced one street at a time. No engine, no mutation,
/// no seat gestures or picker: it reuses the render components, not the recording interactions.
struct ReplayView: View {
    let hand: Hand
    @State private var index: Int = 0

    private struct Frame: Equatable {
        let street: StreetName    // the street whose board + actions this frame shows
        let revealed: Int         // how many of that street's actions are revealed (0 = board/deal only)
        let showdown: Bool        // reveal villain cards + the final outcome on the felt
    }

    /// Every replay beat. Each street walks prefix 0 (board/deal) → 1 → … → all its actions, so stepping
    /// reveals **one action at a time**, not a whole street at once. A final Showdown beat (villains +
    /// outcome) is appended when the hand was contested to the end.
    private var frames: [Frame] {
        let order: [StreetName] = [.preflop, .flop, .turn, .river]
        let lastIdx = order.firstIndex(of: hand.lastStreet) ?? 0
        var result: [Frame] = []
        for s in order.prefix(lastIdx + 1) {
            for c in replayStops(for: s, in: hand) { result.append(Frame(street: s, revealed: c, showdown: false)) }
        }
        if hand.reachedShowdown, let last = result.last {
            result.append(Frame(street: last.street, revealed: last.revealed, showdown: true))
        }
        return result
    }

    private var frame: Frame { frames[min(index, frames.count - 1)] }
    private var isLastFrame: Bool { index >= frames.count - 1 }

    // MARK: Derived render inputs (all pure functions of the hand)

    /// Actions revealed so far: every prior street in full, plus this street's revealed prefix. Drives
    /// the all-in badge so a seat reads all-in exactly when its jam is stepped past, not before.
    private var revealedActions: [Action] {
        let order: [StreetName] = [.preflop, .flop, .turn, .river]
        let idx = order.firstIndex(of: frame.street) ?? 0
        let prior = order.prefix(idx).flatMap { actions(on: $0, in: hand) }
        return prior + Array(actions(on: frame.street, in: hand).prefix(frame.revealed))
    }

    private var tableSeatStates: [Int: SeatState] {
        seatStates(streetActions: Array(actions(on: frame.street, in: hand).prefix(frame.revealed)),
                   foldedBefore: foldedBefore(street: frame.street, in: hand),
                   allIn: Set(revealedActions.filter { $0.sizing?.label == "All-in" }.map(\.seatIndex)),
                   allActions: revealedActions,
                   highlighted: nil,
                   owes: { _ in false })
    }
    private var positions: [Int: String] {
        calculatePositions(buttonSeatIndex: hand.buttonSeatIndex, activeSeatIndices: hand.occupiedSeatIndices)
    }
    private var emptySeats: Set<Int> { Set(0..<hand.tableSize).subtracting(hand.occupiedSeatIndices) }

    private func reached(_ s: StreetName) -> Bool {
        let order: [StreetName] = [.preflop, .flop, .turn, .river]
        return (order.firstIndex(of: s) ?? 0) <= (order.firstIndex(of: frame.street) ?? 0)
    }

    private func streetLabel(_ s: StreetName) -> String {
        switch s {
        case .preflop: return "PREFLOP"
        case .flop:    return "FLOP"
        case .turn:    return "TURN"
        case .river:   return "RIVER"
        }
    }
    private var stepLabel: String {
        if frame.showdown { return "SHOWDOWN" }
        let n = actions(on: frame.street, in: hand).count
        return (frame.revealed == 0 || n == 0)
            ? streetLabel(frame.street)
            : "\(streetLabel(frame.street)) \(frame.revealed)/\(n)"
    }
    // Outcome shows on the showdown beat AND on the final beat of a fold-out (which has no showdown).
    private var feltText: String { (frame.showdown || isLastFrame) ? outcomeText : streetLabel(frame.street) }

    /// Felt outcome at the showdown step — derived (the recorder's transient summary isn't persisted).
    private var outcomeText: String {
        switch hand.result {
        case .win:  return "You win"
        case .lose: return "You lose"
        case .chop: return "Chop"
        case .folded:
            let s = hand.stillInSeatIndices
            return s.count == 1 ? "Seat \(s[0] + 1) wins" : "Showdown"
        case .incomplete: return "Showdown"
        }
    }

    // MARK: View

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 12) {
                TableOvalView(
                    tableSize: hand.tableSize,
                    heroSeat: hand.heroSeatIndex,
                    buttonSeat: hand.buttonSeatIndex,
                    seatStates: tableSeatStates,
                    activeSeat: nil,                 // read-only: no pulsing cue
                    positions: positions,
                    emptySeats: emptySeats,
                    onSeatTap: { _ in },             // inert — replay never mutates
                    actionText: feltText,
                    minHeight: 250,
                    maxHeight: 300
                )
                cardRow
                transcriptPanel
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .navigationTitle("Replay · Hand #\(hand.handNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cardRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ReplayCardGroup(group: hand.holeGroup, label: "HOLE")
                if reached(.flop),  let g = hand.flopGroup  { ReplayCardGroup(group: g, label: "FLOP") }
                if reached(.turn),  let g = hand.turnGroup  { ReplayCardGroup(group: g, label: "TURN") }
                if reached(.river), let g = hand.riverGroup { ReplayCardGroup(group: g, label: "RIVER") }
                if frame.showdown {
                    ForEach(hand.showdownSeatIndices, id: \.self) { seat in
                        if let g = hand.villainGroups[seat] {
                            ReplayCardGroup(group: g, label: positions[seat] ?? "Seat \(seat + 1)")
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var transcriptPanel: some View {
        ScrollView {
            Text(transcript(for: hand))
                .font(.custom("Courier New", size: 13))
                .foregroundStyle(Color.textBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 150)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderDark, lineWidth: 1))
    }

    private var controls: some View {
        HStack {
            stepButton("Prev", icon: "chevron.left", enabled: index > 0) { index -= 1 }
            Spacer()
            Text(stepLabel)
                .font(.custom("Arial", size: 12)).fontWeight(.bold)
                .foregroundStyle(Color.textMuted)
            Spacer()
            stepButton("Next", icon: "chevron.right", enabled: index < frames.count - 1) { index += 1 }
        }
        .padding(.horizontal, 4)
    }

    private func stepButton(_ title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { action() } }) {
            Label(title, systemImage: icon)
                .font(.custom("Arial", size: 14)).fontWeight(.bold)
                .foregroundStyle(enabled ? Color.gold : Color.textMuted)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(Color.surface2))
                .overlay(Capsule().stroke(Color.borderDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// A read-only card group: faces + caption + texture pill, rendered from the same pure helpers the
/// recording strip uses (`faceFrame`/`uniformFootnoteSuit`/`footnoteGlyphs`/`relationshipWord`,
/// `groupNotation`, `CardFrameView`, `CardTextureBadge`) — minus the picker, gestures, and cues.
struct ReplayCardGroup: View {
    let group: CardGroup
    let label: String

    var body: some View {
        let g = group
        let anyKnown = g.frames.contains { $0.suit.knownSymbol != nil }
        let footnoteSuit = uniformFootnoteSuit(g)
        let glyphSet: [String]? = (g.mode == .footnote && footnoteSuit == nil) ? footnoteGlyphs(g) : nil
        let relWord: String? = (g.mode == .relationship) ? relationshipWord(g.relationship) : nil

        VStack(spacing: 6) {
            Text(label)
                .font(.custom("Arial", size: 10)).fontWeight(.bold)
                .foregroundStyle(Color.textMuted)

            HStack(spacing: 4) {
                ForEach(g.frames.indices, id: \.self) { i in
                    CardFrameView(
                        frame: faceFrame(g.frames[i], footnoteSuit: footnoteSuit),
                        showBoundSuit: g.mode == .bound || footnoteSuit != nil,
                        boundUnknown: g.mode == .bound &&
                            (g.frames[i].suit == .unknown || (g.frames[i].suit == .unspecified && anyKnown)),
                        suitRun: g.suitRun,
                        isActive: false
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if glyphSet != nil || relWord != nil {
                    CardTextureBadge(glyphSet: glyphSet, relWord: relWord).offset(y: 9)
                }
            }

            let notation = groupNotation(g)
            Text(notation.isEmpty ? " " : notation)
                .font(.custom("Courier New", size: 13)).fontWeight(.bold).tracking(1)
                .foregroundStyle(Color.goldLight)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(height: 20).padding(.top, 6)
        }
    }
}
