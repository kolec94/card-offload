import SwiftUI

@main
struct CardOffloadApp: App {
    @StateObject private var session = OffloadSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}
