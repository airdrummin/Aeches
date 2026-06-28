import SwiftUI

/// The History tab: a session-grouped accordion. Each session is an expandable header; its hands sit
/// underneath in session order. Hands delete (swipe) / edit / resume (via the detail hub); sessions
/// delete or rename (header menu). Purely store-driven — a `Hand` renders itself via the Phase 3 pure
/// functions and its derived `result`.
struct HistoryListView: View {
    @EnvironmentObject private var store: SessionStore

    @State private var collapsed: Set<UUID> = []                       // expanded by default; tap to collapse
    @State private var editingSession: Session? = nil                 // rename sheet
    @State private var pendingHandDelete: (id: UUID, session: UUID)? = nil
    @State private var pendingSessionDelete: Session? = nil

    private var sessions: [Session] {
        store.sessions.sorted { $0.date != $1.date ? $0.date > $1.date : $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sessions) { session in sessionSection(session) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .navigationDestination(for: UUID.self) { id in HandDetailView(handID: id) }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingSession) { s in
                NavigationStack {
                    NewSessionView(
                        existing: s,
                        onSessionCreated: { store.upsertSession($0); editingSession = nil },
                        onBack: { editingSession = nil }
                    )
                }
            }
            .confirmationDialog("Delete this hand?",
                                isPresented: bool($pendingHandDelete), titleVisibility: .visible) {
                Button("Delete Hand", role: .destructive) {
                    if let p = pendingHandDelete { store.deleteHand(p.id, in: p.session) }
                    pendingHandDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingHandDelete = nil }
            }
            .confirmationDialog("Delete this session?",
                                isPresented: bool($pendingSessionDelete), titleVisibility: .visible) {
                Button("Delete Session", role: .destructive) {
                    if let s = pendingSessionDelete { store.deleteSession(s.id) }
                    pendingSessionDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingSessionDelete = nil }
            } message: {
                if let s = pendingSessionDelete {
                    Text("Deletes \u{201C}\(s.name)\u{201D} and its \(s.hands.count) hand\(s.hands.count == 1 ? "" : "s").")
                }
            }
        }
    }

    // MARK: Session section (accordion)

    @ViewBuilder
    private func sessionSection(_ session: Session) -> some View {
        let hands = session.hands.sorted { $0.handNumber < $1.handNumber }
        DisclosureGroup(isExpanded: expansion(session.id)) {
            if hands.isEmpty {
                Text("No hands yet")
                    .font(.custom("Arial", size: 12)).foregroundStyle(Color.textMuted)
                    .listRowBackground(Color.surface)
            } else {
                ForEach(hands) { hand in
                    NavigationLink(value: hand.id) { HistoryRow(hand: hand, sessionName: nil) }
                        .listRowBackground(Color.surface)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingHandDelete = (hand.id, session.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        } label: {
            sessionHeader(session)
        }
        .tint(Color.gold)
        .listRowBackground(Color.surface)
    }

    private func sessionHeader(_ session: Session) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.custom("Georgia", size: 16)).foregroundStyle(Color.textBody)
                Text("\(session.type == .cash ? "Cash" : "Tournament") · \(session.hands.count) hand\(session.hands.count == 1 ? "" : "s")")
                    .font(.custom("Arial", size: 11)).foregroundStyle(Color.textMuted)
            }
            Spacer()
            Menu {
                Button { editingSession = session } label: { Label("Edit details", systemImage: "pencil") }
                Button(role: .destructive) { pendingSessionDelete = session } label: { Label("Delete session", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textMuted)
                    .padding(.vertical, 6).padding(.leading, 10)
            }
        }
    }

    private func expansion(_ id: UUID) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(id) },
                set: { isExpanded in
                    if isExpanded { collapsed.remove(id) } else { collapsed.insert(id) }
                })
    }

    /// A `Bool` binding that's true while an optional is set, and clears it when dismissed.
    private func bool<T>(_ opt: Binding<T?>) -> Binding<Bool> {
        Binding(get: { opt.wrappedValue != nil }, set: { if !$0 { opt.wrappedValue = nil } })
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
