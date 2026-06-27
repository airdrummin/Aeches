import Foundation

// MARK: - HandStore (the cloud seam)
//
// Everything above this protocol is storage-agnostic: the file implementation today, a cloud
// conformer later, swapped with no consumer change. `SessionStore` owns one of these and never
// knows which kind it holds.

protocol HandStore {
    /// Load the full session set at app start. Returns `[]` on a missing/unreadable/version-mismatched
    /// file — never throws (a corrupt dev file should boot empty, not crash).
    func load() -> [Session]
    /// Persist the full session set. Implementations may debounce; the bytes need not be on disk when
    /// this returns.
    func save(_ sessions: [Session])
    /// Force any pending (debounced) write to complete synchronously. Called on scenePhase
    /// background/terminate so the last hand isn't lost.
    func flush()
}

extension HandStore {
    func flush() {}   // most backends (e.g. in-memory) write synchronously and need no flush
}

// MARK: - FileHandStore (Codable JSON, atomic + debounced)

/// v1 local store: the whole session set as one pretty-printed JSON document in Application Support.
/// Inspectable and resettable while iterating. A future `CloudHandStore` conforms to the same protocol
/// and maps the per-hand write intent (`SessionStore.saveHand`) to one document write.
final class FileHandStore: HandStore {
    /// Bump on any model change during the build to discard the old dev file (no migration code while
    /// iterating — see the Index's "Throwaway dev data" principle).
    private static let storeVersion = 2   // bumped: Hand gained `lastStreet` (Phase 3)

    /// The version travels with the data so `load()` can discard a stale file.
    private struct Payload: Codable {
        var storeVersion: Int
        var sessions: [Session]
    }

    private let fileURL: URL
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.airdrummin.Aeches.handstore")

    // Debounce state — only ever touched on `queue`.
    private var pendingSessions: [Session]?
    private var pendingWrite: DispatchWorkItem?

    init(filename: String = "aeches-store.json", debounceInterval: TimeInterval = 0.4) {
        self.debounceInterval = debounceInterval
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(filename)
    }

    /// Path to the JSON file, for manual inspection while testing.
    var debugFileURL: URL { fileURL }

    func load() -> [Session] {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? Self.decoder.decode(Payload.self, from: data),
              payload.storeVersion == Self.storeVersion       // dev throwaway: stale version → empty
        else { return [] }
        return payload.sessions
    }

    func save(_ sessions: [Session]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingSessions = sessions          // newest snapshot wins
            self.pendingWrite?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.writePending() }
            self.pendingWrite = work
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: work)
        }
    }

    func flush() {
        queue.sync {
            self.pendingWrite?.cancel()
            self.writePending()
        }
    }

    /// Write the latest pending snapshot now. Must run on `queue`.
    private func writePending() {
        guard let sessions = pendingSessions else { return }
        pendingSessions = nil
        pendingWrite = nil
        let payload = Payload(storeVersion: Self.storeVersion, sessions: sessions)
        guard let data = try? Self.encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)   // temp-file + rename, never a torn file
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]   // inspectable on disk
        return e
    }()
    private static let decoder = JSONDecoder()
}

// MARK: - InMemoryHandStore (tests / previews)

/// A non-persistent backing for SwiftUI previews and manual testing — same protocol, no disk.
final class InMemoryHandStore: HandStore {
    private var stored: [Session]
    init(_ initial: [Session] = []) { stored = initial }
    func load() -> [Session] { stored }
    func save(_ sessions: [Session]) { stored = sessions }
}
