import Foundation
import SwiftData

/// A generated morning briefing, cached per calendar day so opening the app
/// repeatedly doesn't re-bill an API call. `dayKey` is a `yyyy-MM-dd` string
/// rather than a `Date` because that's what SwiftData predicates compare
/// cleanly.
@Model
final class DailyBriefing {
    @Attribute(.unique) var dayKey: String
    var generatedAt: Date
    /// The model's narrative. May be empty when the briefing was assembled
    /// without an API key, in which case the UI shows the facts alone.
    var narrative: String
    /// The deterministic facts the narrative was written from, kept so the
    /// briefing still reads correctly offline and so the user can see exactly
    /// what the model was told.
    var factsSummary: String
    var usedModelRawValue: String

    init(dayKey: String, narrative: String, factsSummary: String, usedModelRawValue: String) {
        self.dayKey = dayKey
        self.generatedAt = .now
        self.narrative = narrative
        self.factsSummary = factsSummary
        self.usedModelRawValue = usedModelRawValue
    }

    static func dayKey(for date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
