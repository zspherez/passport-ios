import SwiftUI

@main
struct PassportApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var deepLinks = DeepLinkRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deepLinks)
                // Universal Links: a system-camera scan of the venue QR
                // (or any tap on the AASA-matched host) opens the app and
                // hands us the URL here. Park it on the router so whichever
                // screen is in front can react.
                .onOpenURL { url in
                    deepLinks.ingest(url: url)
                }
                // Same path for cold launches: SwiftUI surfaces the
                // userActivity for the Universal Link the app was opened
                // from. Forward the URL through the same ingest hook so
                // there's a single code path.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        deepLinks.ingest(url: url)
                    }
                }
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
