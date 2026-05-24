import SwiftUI

/// Single source of truth for the passport client's brand palette. Update the
/// values here and every view that references `Brand.gold` / `Brand.bg` moves
/// in lockstep — no more drift between RegisterView, PassportView, etc.
enum Brand {
    static let gold = Color(red: 0.87, green: 0.66, blue: 0.32)
    static let bg = Color(red: 0.06, green: 0.06, blue: 0.07)
}
