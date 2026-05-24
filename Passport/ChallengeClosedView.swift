import SwiftUI

/// Gate shown in Release builds on any day that isn't the configured
/// challenge date. Customers shouldn't be able to register or scan from a
/// non-event day, so the rest of the app is unreachable from here.
struct ChallengeClosedView: View {
    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "calendar")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundColor(Brand.gold)
                Text("Mother's Day Challenge")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(.white)
                Text("Come back on \(ChallengeWindow.challengeDateLabel)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("The passport opens that morning at each Mother's Ruin location.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ChallengeClosedView()
}
