import Foundation

/// Hard date gate for the challenge. In Release the app is only usable on
/// May 9, 2027 (device local time). DEBUG builds skip the gate so we can
/// keep iterating on the flow any day of the year.
enum ChallengeWindow {
    /// Calendar day the challenge runs. Update before re-shipping.
    static let challengeYear  = 2027
    static let challengeMonth = 5
    static let challengeDay   = 9

    /// True if the user should be allowed to use the app right now.
    static var isOpen: Bool {
        #if DEBUG
        return true
        #else
        return isChallengeDay(Date())
        #endif
    }

    /// Pure date check, exposed for tests / previews.
    static func isChallengeDay(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return comps.year == challengeYear
            && comps.month == challengeMonth
            && comps.day == challengeDay
    }

    /// Pretty version of the challenge date for display.
    static var challengeDateLabel: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let comps = DateComponents(
            calendar: cal,
            year: challengeYear,
            month: challengeMonth,
            day: challengeDay
        )
        guard let date = cal.date(from: comps) else { return "May \(challengeDay), \(challengeYear)" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
