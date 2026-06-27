import SwiftUI

/// The History tab: every recorded hand, newest-first, each row tappable into `HandDetailView`.
/// Purely store-driven — no live recording `@State` is read; a `Hand` renders itself via the Phase 3
/// pure functions (`transcript(for:)`, `groupNotation`) and its derived `result`.
struct HistoryListView: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                let hands = store.allHands()
                if hands.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(hands) { hand in
                            NavigationLink(value: hand.id) {
                                HistoryRow(hand: hand, sessionName: store.session(id: hand.sessionId)?.name)
                            }
                            .listRowBackground(Color.surface)
                            .listRowSeparatorTint(Color.borderDark)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .navigationDestination(for: UUID.self) { id in
                        if let hand = store.hand(id: id) {
                            HandDetailView(hand: hand)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "suit.spade")
                .font(.system(size: 34))
                .foregroundStyle(Color.gold.opacity(0.7))
            Text("No hands yet")
                .font(.custom("Georgia", size: 19))
                .foregroundStyle(Color.textBody)
            Text("Record your first hand in the Record tab —\nit'll show up here.")
                .font(.custom("Arial", size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textMuted)
        }
        .padding()
    }
}

// MARK: - Row

/// One hand at a glance: number + session, hero position + hole, the outcome chip, a one-line
/// shorthand snippet (the first action line), and eff/date. Cheap — builds the transcript once and
/// takes a single line.
struct HistoryRow: View {
    let hand: Hand
    let sessionName: String?

    private var position: String {
        calculatePositions(buttonSeatIndex: hand.buttonSeatIndex,
                            activeSeatIndices: hand.occupiedSeatIndices)[hand.heroSeatIndex] ?? ""
    }
    private var hole: String { groupNotation(hand.holeGroup) }

    /// The first action line of the shorthand (the header is dropped — its hand#/hole/position/eff are
    /// already broken out into the row's own fields).
    private var snippet: String {
        transcript(for: hand)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst()
            .first { !$0.isEmpty }
            .map(String.init) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hand #\(hand.handNumber)")
                    .font(.custom("Georgia", size: 16))
                    .foregroundStyle(Color.textBody)
                if let sessionName {
                    Text("· \(sessionName)")
                        .font(.custom("Arial", size: 12))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                ResultChip(result: hand.result)
            }

            HStack(spacing: 8) {
                if !position.isEmpty {
                    Text(position)
                        .font(.custom("Arial", size: 12)).fontWeight(.bold)
                        .foregroundStyle(Color.gold)
                }
                if !hole.isEmpty {
                    Text(hole)
                        .font(.custom("Courier New", size: 13))
                        .foregroundStyle(Color.goldLight)
                }
                if let eff = hand.effectiveStack {
                    Text("\(Int(eff))bb")
                        .font(.custom("Arial", size: 11))
                        .foregroundStyle(Color.textMuted)
                }
            }

            if !snippet.isEmpty {
                Text(snippet)
                    .font(.custom("Courier New", size: 12))
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Result chip

/// Small colored capsule for the hero result. Shared by the list row and the detail header.
struct ResultChip: View {
    let result: HandResult

    private var color: Color {
        switch result {
        case .win:        return Color.winGreen
        case .lose:       return Color.foldRed
        case .chop:       return Color.gold
        case .folded:     return Color.textMuted
        case .incomplete: return Color.textMuted
        }
    }

    var body: some View {
        Text(result.label)
            .font(.custom("Arial", size: 10)).fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }
}

#Preview {
    HistoryListView()
        .environmentObject(SessionStore(backing: InMemoryHandStore()))
        .preferredColorScheme(.dark)
}
