import Foundation

/// How the dossier is grouped in the editor, ordered the way a person actually
/// fills a long application: who you are, how to reach you, where you live, then
/// the things only real applications ask for.
nonisolated enum DossierCategory: String, CaseIterable, Identifiable, Codable {
    case identity
    case contact
    case address
    case work
    case education
    case links
    case extras

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identity: "Who you are"
        case .contact: "How to reach you"
        case .address: "Where you live"
        case .work: "Work"
        case .education: "Education"
        case .links: "Links"
        case .extras: "The extras applications ask for"
        }
    }

    var icon: String {
        switch self {
        case .identity: "person.fill"
        case .contact: "envelope.fill"
        case .address: "house.fill"
        case .work: "briefcase.fill"
        case .education: "graduationcap.fill"
        case .links: "link"
        case .extras: "text.badge.plus"
        }
    }

    var caption: String {
        switch self {
        case .identity: "The name a form puts at the top."
        case .contact: "Almost every form wants these two."
        case .address: "Filled as one block, in the order sites expect."
        case .work: "What a job application asks about your current role."
        case .education: "Degree, subject, school, year."
        case .links: "Pasted into \u{201C}portfolio\u{201D} and \u{201C}profile\u{201D} fields."
        case .extras: "Notice period, salary, right to work — the questions that stall an application."
        }
    }
}
