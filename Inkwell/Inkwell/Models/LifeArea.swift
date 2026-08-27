import SwiftUI

/// The parts of life this app is meant to hold together. Every task, document,
/// notebook folder, and briefing section can be tagged with one, which is what
/// lets a single app stay compact instead of becoming five separate apps.
///
/// Stored on models as `rawValue` strings so SwiftData predicates can filter on
/// them (SwiftData can't compare custom enums inside `#Predicate`).
enum LifeArea: String, CaseIterable, Identifiable, Codable {
    case school
    case home
    case eca
    case projects
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .school: return "School"
        case .home: return "Home"
        case .eca: return "Activities"
        case .projects: return "Projects"
        case .personal: return "Personal"
        }
    }

    /// Slightly longer label used in pickers and the briefing, where "Activities"
    /// on its own is ambiguous.
    var subtitle: String {
        switch self {
        case .school: return "Classes, homework, exams"
        case .home: return "Chores, family, errands"
        case .eca: return "Clubs, sports, extracurriculars"
        case .projects: return "Side and external projects"
        case .personal: return "Everything else"
        }
    }

    var symbolName: String {
        switch self {
        case .school: return "graduationcap.fill"
        case .home: return "house.fill"
        case .eca: return "figure.run"
        case .projects: return "hammer.fill"
        case .personal: return "person.fill"
        }
    }

    var palette: ColorPalette {
        switch self {
        case .school: return .blue
        case .home: return .green
        case .eca: return .orange
        case .projects: return .purple
        case .personal: return .teal
        }
    }

    var color: Color { palette.color }

    static func from(_ rawValue: String) -> LifeArea {
        LifeArea(rawValue: rawValue) ?? .personal
    }
}
