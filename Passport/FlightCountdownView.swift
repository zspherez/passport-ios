import SwiftUI

/// Split-flap (Solari-board) countdown to the customer's next scheduled
/// flight. Per-second TimelineView tick drives the digits; each tile uses
/// an opacity + slide transition keyed off its digit value so individual
/// characters flip when they change rather than the whole row redrawing.
struct FlightCountdownView: View {
    let flights: [Flight]
    /// Tapping the board opens the flights manager so the customer can add
    /// more / fix mistakes / verify times.
    let onTap: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let next = nextFlight(now: now) {
            let remaining = max(0, Int(next.departureAt.timeIntervalSince(now)))
            Button(action: onTap) {
                VStack(spacing: 10) {
                    HStack(spacing: 4) {
                        DigitPair(value: remaining / 3600)
                        Separator()
                        DigitPair(value: (remaining % 3600) / 60)
                        Separator()
                        DigitPair(value: remaining % 60)
                    }
                    Text("\(next.flightCodes) · \(next.originAirport) → \(next.destinationAirport)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Brand.gold)
                        .textCase(.uppercase)
                        .tracking(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(white: 0.18), lineWidth: 1)
                )
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        } else {
            EmptyView()
        }
    }

    private func nextFlight(now: Date) -> Flight? {
        flights
            .filter { $0.departureAt > now }
            .sorted { $0.departureAt < $1.departureAt }
            .first
    }
}

// MARK: - Tiles

/// Two adjacent flap tiles for a zero-padded 0..99 number (hour/minute/sec).
private struct DigitPair: View {
    let value: Int
    var body: some View {
        let s = String(format: "%02d", max(0, min(99, value)))
        HStack(spacing: 3) {
            FlapTile(character: String(s.first!))
            FlapTile(character: String(s.last!))
        }
    }
}

/// One flap card: dark rounded rectangle with a thin horizontal split line
/// through the vertical midpoint (the seam of a real Solari flap). The
/// character animates in from the bottom and out to the top whenever it
/// changes, mimicking the physical motion of the flap rotating around the
/// seam.
private struct FlapTile: View {
    let character: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(white: 0.18), lineWidth: 0.5)
                )

            // Seam — pure black 1pt line at vertical center, inset slightly
            // so the corners stay rounded.
            Rectangle()
                .fill(Color.black)
                .frame(height: 1.5)
                .padding(.horizontal, 2)

            Text(character)
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundColor(Brand.gold)
                .monospacedDigit()
                .id(character)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal:   .move(edge: .top).combined(with: .opacity)
                ))
        }
        .frame(width: 30, height: 46)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: character)
    }
}

private struct Separator: View {
    var body: some View {
        Text(":")
            .font(.system(size: 26, weight: .heavy, design: .monospaced))
            .foregroundColor(Brand.gold.opacity(0.55))
    }
}
