import SwiftUI

@main
struct AechesApp: App {
    @State private var isAuthenticated = false

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            ContentView()
                .preferredColorScheme(.dark)
            #else
            if isAuthenticated {
                ContentView()
                    .preferredColorScheme(.dark)
            } else {
                LoginView(onAuthenticated: {
                    isAuthenticated = true
                })
                .preferredColorScheme(.dark)
            }
            #endif
        }
    }
}
