import SwiftUI

@main
struct AechesApp: App {
    @StateObject private var store = SessionStore(backing: FileHandStore())
    @State private var isAuthenticated = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            root
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    // Flush the debounced write before the app leaves the foreground so the last
                    // hand survives a background/terminate.
                    if phase != .active { store.flush() }
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        ContentView()
        #else
        if isAuthenticated {
            ContentView()
        } else {
            LoginView(onAuthenticated: { isAuthenticated = true })
        }
        #endif
    }
}
