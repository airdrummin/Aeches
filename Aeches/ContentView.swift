import SwiftUI

struct ContentView: View {
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
    }
}

// MARK: - Tab Placeholders

struct RecordTab: View {
    @State private var activeSession: Session? = nil
    @State private var heroSeat: Int? = nil
    @State private var tableSize: Int = 9

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if activeSession == nil {
                    NewSessionView(
                        onSessionCreated: { session in activeSession = session },
                        onBack: nil
                    )
                } else if heroSeat == nil {
                    SeatSelectionView(
                        session: activeSession!,
                        onSeatSelected: { seat, size in
                            heroSeat = seat
                            tableSize = size
                        },
                        onBack: {
                            activeSession = nil
                        }
                    )
                } else {
                    // Hand entry (TableScreen) comes next
                    ZStack {
                        Color.appBackground.ignoresSafeArea()
                        Text("Seat \((heroSeat ?? 0) + 1) locked — hand entry coming next")
                            .foregroundStyle(Color.textMuted)
                        VStack {
                            HStack {
                                Button(action: { heroSeat = nil }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Color.gold)
                                        .padding(16)
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct HistoryTab: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                Text("History")
                    .foregroundStyle(Color.textMuted)
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
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
}
