import Foundation

/// The result of one page scan: every pressable element on screen plus page
/// vitals (scroll position, off-screen counts, overlay detection).
nonisolated struct PageObservation {
    let elements: [ScannedElement]
    /// Viewport size in CSS pixels — the coordinate space of every element rect.
    let viewportWidth: Double
    let viewportHeight: Double
    /// 0 = top of the page, 1 = bottom.
    let scrollFraction: Double
    /// Full document height divided by viewport height (1 ≈ nothing to scroll).
    let documentHeightRatio: Double
    let elementsAbove: Int
    let elementsBelow: Int
    /// Visible interactive elements beyond the catalog cap (not listed or badged).
    let unlistedVisibleCount: Int
    let overlayLikely: Bool
    /// True when the scan hit its time budget and the list may be incomplete.
    let isPartial: Bool
    /// Visible embedded panels (iframes) that could not be scanned this look.
    var blockedPanelCount: Int = 0

    func element(withID id: Int) -> ScannedElement? {
        elements.first { $0.id == id }
    }

    /// Copy of this observation with a merged element list (main page + panels)
    /// and the count of panels that resisted scanning.
    func replacingElements(_ newElements: [ScannedElement], blockedPanelCount: Int) -> PageObservation {
        PageObservation(
            elements: newElements,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            scrollFraction: scrollFraction,
            documentHeightRatio: documentHeightRatio,
            elementsAbove: elementsAbove,
            elementsBelow: elementsBelow,
            unlistedVisibleCount: unlistedVisibleCount,
            overlayLikely: overlayLikely,
            isPartial: isPartial,
            blockedPanelCount: blockedPanelCount
        )
    }

    private var wholePageVisible: Bool {
        documentHeightRatio <= 1.05
    }

    /// The written briefing the AI receives next to the badged screenshot.
    var mapText: String {
        var lines: [String] = []
        if elements.isEmpty {
            lines.append("ELEMENTS ON SCREEN: none detected — the page may still be loading, or it draws fully custom controls. Use the coordinate \"tap\" tool if you must interact.")
        } else {
            lines.append("ELEMENTS ON SCREEN (numbers match the badges drawn on the screenshot):")
            for element in elements {
                lines.append(element.mapLine)
            }
            if unlistedVisibleCount > 0 {
                lines.append("(+\(unlistedVisibleCount) more interactive elements on screen, not listed)")
            }
            if elements.contains(where: { $0.panelLabel != nil }) {
                lines.append("Elements marked (in embedded panel: …) sit inside embedded widgets — tap_element, type_into, and the other element moves work on them normally.")
            }
        }
        lines.append(vitalsLine)
        if overlayLikely {
            lines.append("NOTE: a dialog or overlay appears to be blocking the page — deal with it first (look for a close, accept, or dismiss button in the list).")
        }
        if isPartial {
            lines.append("NOTE: the page scan hit its time budget — the element list may be incomplete.")
        }
        if blockedPanelCount > 0 {
            lines.append("NOTE: \(blockedPanelCount) embedded panel\(blockedPanelCount == 1 ? "" : "s") on screen couldn't be scanned — each is a single region; use the coordinate tap if you must press inside one.")
        }
        return lines.joined(separator: "\n")
    }

    private var vitalsLine: String {
        var line: String
        if wholePageVisible {
            line = "VIEW: the whole page fits on screen"
        } else {
            let phrase: String
            switch scrollFraction {
            case ..<0.02: phrase = "at the very top of the page"
            case ..<0.25: phrase = "near the top of the page"
            case ..<0.6: phrase = "around the middle of the page"
            case ..<0.92: phrase = "in the lower part of the page"
            default: phrase = "at the bottom of the page"
            }
            line = "VIEW: \(phrase)"
        }
        let belowWord = elementsBelow == 1 ? "element" : "elements"
        line += " — \(elementsBelow) interactive \(belowWord) below the visible area, \(elementsAbove) above."
        return line
    }
}
