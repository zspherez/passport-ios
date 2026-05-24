import SwiftUI

struct ContentView: View {
    @State private var hasPassport: Bool = LocalStore.passportToken != nil

    var body: some View {
        Group {
            if !ChallengeWindow.isOpen {
                ChallengeClosedView()
            } else if hasPassport {
                PassportView(onReset: { hasPassport = false })
            } else {
                RegisterView(onRegistered: { hasPassport = true })
            }
        }
    }
}

#Preview {
    ContentView()
}
