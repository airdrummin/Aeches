import Foundation
import Combine   // ObservableObject + @Published (not reliably re-exported via SwiftUI for synthesis)

// MARK: - SessionStore (single source of truth)
//
// The app-wide store of sessions and the hands inside them. Record writes through it; History and
// Replay read from it. Loads via the injected `HandStore` on init and persists on every mutation
// (the backing store debounces). Holds the store behind the protocol, so it's testable with
// `InMemoryHandStore` and cloud-swappable with no consumer change.
//
// Note (README invariant, intentionally reversed in this phase): this is the one observable context
// layer in the app. Recording *interaction* state still lives in `HandEntryView`; only the persisted
// hand data lives here.
//
// Not `@MainActor`-annotated: every mutation originates from the main-thread SwiftUI UI, and marking
// the class `@MainActor` makes the synthesized `objectWillChange` actor-isolated, which fails the
// nonisolated `ObservableObject` requirement under this project's concurrency settings.

final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session]

    /// Edit/Resume request slot. `HandDetailView` sets it to a hand's id; `ContentView` switches to the
    /// Record tab and `HandEntryView` consumes it (auto-skip current → rehydrate → clear). nil = none.
    @Published var editingHandID: UUID? = nil

    /// Set by the recorder's "Done" (end of an Edit/Resume) so `ContentView` returns to the History tab.
    @Published var jumpToHistory: Bool = false

    private let backing: HandStore

    init(backing: HandStore) {
        self.backing = backing
        self.sessions = backing.load()
    }

    // MARK: Sessions

    /// Create or update a session by id.
    func upsertSession(_ session: Session) {
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[i] = session
        } else {
            sessions.append(session)
        }
        persist()
    }

    func session(id: UUID) -> Session? { sessions.first { $0.id == id } }

    // MARK: Hands

    /// The single persist path for a hand: **upsert by `hand.id`** within its session. Close,
    /// re-close (after Undo), post-close card edits, and (Phase 6) edit-write-back all land here, so
    /// re-saving updates in place instead of duplicating. A future cloud backing maps this one call to
    /// one document write.
    func saveHand(_ hand: Hand, in sessionId: UUID) {
        guard let si = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        if let hi = sessions[si].hands.firstIndex(where: { $0.id == hand.id }) {
            sessions[si].hands[hi] = hand
        } else {
            sessions[si].hands.append(hand)
        }
        persist()
    }

    /// Look up one hand by its durable id across all sessions (e.g. Undo-at-close reading the
    /// just-closed snapshot, Replay/Edit resolving a row).
    func hand(id: UUID) -> Hand? {
        for s in sessions {
            if let h = s.hands.first(where: { $0.id == id }) { return h }
        }
        return nil
    }

    /// Delete one hand by id from its session. No renumber — remaining hands keep their recorded
    /// `handNumber` (gaps are fine; the number is a display ordinal, `Hand.id` is the durable key).
    func deleteHand(_ id: UUID, in sessionId: UUID) {
        guard let si = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[si].hands.removeAll { $0.id == id }
        persist()
    }

    /// Delete a whole session and all its hands.
    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    /// The next hand number for a session — one past its highest existing (1 if empty). Seeds the
    /// recorder so numbering is per-session and continues across relaunch / resume.
    func nextHandNumber(in sessionId: UUID) -> Int {
        ((session(id: sessionId)?.hands.map(\.handNumber).max()) ?? 0) + 1
    }

    /// Every hand across every session, newest-first — the History feed. Ties on timestamp fall back to
    /// the higher hand number, so hands recorded in the same instant stay in a stable, sensible order.
    func allHands() -> [Hand] {
        sessions.flatMap { $0.hands }.sorted {
            $0.timestamp != $1.timestamp ? $0.timestamp > $1.timestamp : $0.handNumber > $1.handNumber
        }
    }

    // MARK: Persistence

    private func persist() { backing.save(sessions) }

    /// Force the backing store to flush any debounced write now (scenePhase background/terminate).
    func flush() { backing.flush() }
}
