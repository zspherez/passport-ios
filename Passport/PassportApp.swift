import SwiftUI

@main
struct PassportApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            // Re-drain the pending-stamp queue every time the app comes
            // back to the foreground. The queue also self-triggers on
            // network reachability flips, but explicit re-attempts here
            // cover "user backgrounded → switched wifi → returned" without
            // waiting for the path monitor to notice.
            if phase == .active {
                Task { await CheckinQueue.shared.flush() }
            }
        }
    }
}
