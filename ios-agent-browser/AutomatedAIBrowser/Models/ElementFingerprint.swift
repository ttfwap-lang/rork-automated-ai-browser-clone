import Foundation

/// How an element is described so it can be found again on a page that may have
/// shifted since — by name, kind, neighbourhood and rough position, never by
/// position alone.
///
/// Badge numbers are useless across visits: they are assigned per scan, so
/// element 4 today is something else tomorrow. This is what a remembered route
/// stores instead.
nonisolated struct ElementFingerprint: Codable, Hashable, Sendable {
    /// The visible name — the primary test, and the one that must match.
    let name: String
    let kind: ScannedElement.Kind
    /// Names of the nearest few other elements, used to tell look-alikes apart.
    let neighbourhood: [String]
    /// Position on screen as a fraction of the viewport, 0-1. A tie-breaker only.
    let approxX: Double
    let approxY: Double

    /// How many neighbours are worth remembering.
    private static let neighbourCount = 3

    static func make(for element: ScannedElement, in observation: PageObservation) -> ElementFingerprint {
        let centerX = element.x + element.width / 2
        let centerY = element.y + element.height / 2
        let width = max(observation.viewportWidth, 1)
        let height = max(observation.viewportHeight, 1)

        let neighbours = observation.elements
            .filter { $0.id != element.id && !$0.name.trimmed.isEmpty }
            .map { other -> (String, Double) in
                let dx = (other.x + other.width / 2) - centerX
                let dy = (other.y + other.height / 2) - centerY
                return (other.name.trimmed, (dx * dx + dy * dy).squareRoot())
            }
            .sorted { $0.1 < $1.1 }
            .prefix(neighbourCount)
            .map { $0.0 }

        return ElementFingerprint(
            name: element.name.trimmed,
            kind: element.kind,
            neighbourhood: Array(neighbours),
            approxX: min(max(centerX / width, 0), 1),
            approxY: min(max(centerY / height, 0), 1)
        )
    }

    /// How well a live element matches this fingerprint, 0 when it cannot be the
    /// same thing at all.
    ///
    /// The name and kind are requirements, not hints: a route that "sort of"
    /// recognises a button is exactly how replay goes wrong.
    func score(against element: ScannedElement, in observation: PageObservation) -> Double {
        guard element.kind == kind else { return 0 }
        let liveName = element.name.trimmed
        guard !liveName.isEmpty, !name.isEmpty else { return 0 }
        guard liveName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else {
            return 0
        }

        var score = 1.0

        let liveNeighbours = Set(
            observation.elements
                .filter { $0.id != element.id && !$0.name.trimmed.isEmpty }
                .map { $0.name.trimmed.lowercased() }
        )
        let remembered = Set(neighbourhood.map { $0.lowercased() })
        if !remembered.isEmpty {
            let overlap = Double(remembered.intersection(liveNeighbours).count) / Double(remembered.count)
            score += overlap
        }

        let width = max(observation.viewportWidth, 1)
        let height = max(observation.viewportHeight, 1)
        let liveX = (element.x + element.width / 2) / width
        let liveY = (element.y + element.height / 2) / height
        let drift = ((liveX - approxX) * (liveX - approxX) + (liveY - approxY) * (liveY - approxY)).squareRoot()
        score += max(0, 1 - drift)

        return score
    }
}
