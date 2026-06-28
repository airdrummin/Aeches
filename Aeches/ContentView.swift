import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var activeTab: Tab = .record

    enum Tab {
        case record, history, marketplace, profile
    }

    var body: some View {
        TabView(selection: $activeTab) {
            RecordTab()
                .tabItem {
                    Image(systemName: "suit.spade.fill")
                    Text("Record")
                }
                .tag(Tab.record)

            HistoryTab()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("History")
                }
                .tag(Tab.history)

            MarketplaceTab()
                .tabItem {
                    Image(systemName: "storefront")
                    Text("Marketplace")
                }
                .tag(Tab.marketplace)

            ProfileTab()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
                .tag(Tab.profile)
        }
        .tint(Color.gold)
        .preferredColorScheme(.dark)
        // Edit/Resume from History: jump to the Record tab so the (always-mounted) recorder handles it.
        .onChange(of: store.editingHandID) { _, id in
            if id != nil { activeTab = .record }
        }
        // "Done" at the end of an edit/resume returns to History.
        .onChange(of: store.jumpToHistory) { _, jump in
            if jump { activeTab = .history; store.jumpToHistory = false }
        }
    }
}

// MARK: - Tab Placeholders

struct RecordTab: View {
    @EnvironmentObject private var store: SessionStore
    @State private var activeSession: Session? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if let session = activeSession {
                    HandEntryView(
                        session: session,
                        onBack: { activeSession = nil }
                    )
                } else {
                    NewSessionView(
                        onSessionCreated: { session in
                            store.upsertSession(session)   // persist before recording into it
                            activeSession = session
                        },
                        onBack: nil
                    )
                }
            }
            .navigationBarHidden(true)
        }
        // If the active session is deleted from History, drop it so the recorder doesn't write into a
        // ghost. (Compares ids — [Session] isn't Equatable.)
        .onChange(of: store.sessions.map(\.id)) { _, _ in
            guard let s = activeSession, store.session(id: s.id) == nil else { return }
            activeSession = nil
            #if DEBUG
            let today = Self.todaysSession(in: store)
            store.upsertSession(today)
            activeSession = today
            #endif
        }
        #if DEBUG
        // Dev scaffold (removed with the real session/auth flow): boot into TODAY's session — find one
        // dated today, else create one named for the date. New hands continue the day's numbering; a new
        // calendar day starts a new session group. (Back → New Session still makes extra groups.)
        .onAppear {
            guard activeSession == nil else { return }
            let today = Self.todaysSession(in: store)
            store.upsertSession(today)
            activeSession = today
        }
        #endif
    }

    #if DEBUG
    private static func todaysSession(in store: SessionStore) -> Session {
        if let existing = store.sessions.first(where: { Calendar.current.isDateInToday($0.date) }) {
            return existing
        }
        return Session(type: .cash, name: todayName, date: Date(), tableSize: 9, heroSeatIndex: 0)
    }
    private static var todayName: String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"   // e.g. "Sat, Jun 28"
        return f.string(from: Date())
    }
    #endif
}

struct HistoryTab: View {
    var body: some View { HistoryListView() }
}

struct MarketplaceTab: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                Text("Marketplace")
                    .foregroundStyle(Color.textMuted)
            }
            .navigationTitle("Marketplace")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ProfileTab: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                Text("Profile")
                    .foregroundStyle(Color.textMuted)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Design Tokens

extension Color {
    static let appBackground = Color(hex: "#0D0D0D")
    static let surface       = Color(hex: "#161616")
    static let surface2      = Color(hex: "#1E1E1E")
    static let surface3      = Color(hex: "#252525")
    static let gold          = Color(hex: "#C9A84C")
    static let goldLight     = Color(hex: "#E8D5A3")
    static let textBody      = Color(hex: "#DDDDDD")
    static let textMuted     = Color(hex: "#888888")
    static let borderDark    = Color(hex: "#3A3A3A")
    static let foldRed       = Color(hex: "#C0392B")
    static let foldRedBg     = Color(hex: "#2A1515")
    static let winGreen      = Color(hex: "#27AE60")
    static let winGreenBg    = Color(hex: "#152A1B")
    static let feltGreen     = Color(hex: "#1B3A2D")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionStore(backing: InMemoryHandStore()))
}
