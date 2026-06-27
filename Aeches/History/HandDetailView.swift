import SwiftUI

/// The per-hand hub reached from History. Shows the full, read-only transcript (rendered from the
/// stored `Hand` via the Phase 3 pure builder) and is the launch point for the two hand actions.
/// Replay (Phase 5) and Edit (Phase 6) are present-but-stubbed so the navigation is in place now.
struct HandDetailView: View {
    let hand: Hand
    @EnvironmentObject private var store: SessionStore
    @State private var copied = false

    private var sessionName: String? { store.session(id: hand.sessionId)?.name }
    private var position: String {
        calculatePositions(buttonSeatIndex: hand.buttonSeatIndex,
                            activeSeatIndices: hand.occupiedSeatIndices)[hand.heroSeatIndex] ?? ""
    }
    private var hole: String { groupNotation(hand.holeGroup) }
    private var transcriptText: String { transcript(for: hand) }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    transcriptCard
                    actions
                }
                .padding(16)
            }
        }
        .navigationTitle("Hand #\(hand.handNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let sessionName {
                    Text(sessionName)
                        .font(.custom("Arial", size: 13))
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
                ResultChip(result: hand.result)
            }
            HStack(spacing: 10) {
                if !position.isEmpty {
                    Text(position)
                        .font(.custom("Arial", size: 14)).fontWeight(.bold)
                        .foregroundStyle(Color.gold)
                }
                if !hole.isEmpty {
                    Text(hole)
                        .font(.custom("Courier New", size: 18))
                        .foregroundStyle(Color.goldLight)
                }
                if let eff = hand.effectiveStack {
                    Text("\(Int(eff))bb eff")
                        .font(.custom("Arial", size: 12))
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Transcript

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HAND HISTORY")
                    .font(.custom("Arial", size: 11)).fontWeight(.bold)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.custom("Arial", size: 12))
                        .foregroundStyle(Color.gold)
                }
                .buttonStyle(.plain)
            }
            Text(transcriptText)
                .font(.custom("Courier New", size: 13))
                .foregroundStyle(Color.textBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderDark, lineWidth: 1))
    }

    // MARK: Actions (stubbed until Phase 5 / 6)

    private var actions: some View {
        HStack(spacing: 12) {
            actionButton("Replay", icon: "play.fill")        // → ReplayView(hand:)  (Phase 5)
            actionButton("Edit",   icon: "pencil")           // → recorder in edit mode (Phase 6)
        }
    }

    private func actionButton(_ title: String, icon: String) -> some View {
        // Present-but-stubbed: the nav slots exist now; wired in their phases.
        Button(action: {}) {
            Label(title, systemImage: icon)
                .font(.custom("Arial", size: 14)).fontWeight(.bold)
                .foregroundStyle(Color.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.surface2))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.5)
    }

    private func copy() {
        UIPasteboard.general.string = transcriptText
        withAnimation(.easeInOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) { copied = false }
        }
    }
}
