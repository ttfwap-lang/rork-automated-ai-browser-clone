import UIKit

/// Draws Set-of-Mark badges onto a captured snapshot: a thin outline around each
/// catalogued element plus a small numbered chip, color-coded by kind. Badges are
/// drawn on the image only — the live page stays clean.
enum SnapshotAnnotator {

    /// Returns the annotated snapshot; the original image is returned untouched
    /// when the observation is empty or its viewport is unusable.
    static func annotate(_ image: UIImage, with observation: PageObservation) -> UIImage {
        guard !observation.elements.isEmpty,
              observation.viewportWidth > 1,
              observation.viewportHeight > 1,
              image.size.width > 1,
              image.size.height > 1 else {
            return image
        }

        let scaleX = image.size.width / observation.viewportWidth
        let scaleY = image.size.height / observation.viewportHeight
        let bounds = CGRect(origin: .zero, size: image.size)
        let font = UIFont.systemFont(ofSize: 11, weight: .bold)

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        var placedChips: [CGRect] = []

        return renderer.image { context in
            image.draw(in: bounds)
            let cgContext = context.cgContext

            for element in observation.elements {
                let rect = CGRect(
                    x: element.x * scaleX,
                    y: element.y * scaleY,
                    width: element.width * scaleX,
                    height: element.height * scaleY
                ).intersection(bounds)
                guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }

                let color = badgeColor(for: element.kind)

                cgContext.setStrokeColor(color.withAlphaComponent(0.6).cgColor)
                cgContext.setLineWidth(1.2)
                cgContext.stroke(rect.insetBy(dx: 0.6, dy: 0.6))

                let label = "\(element.id)" as NSString
                let textSize = label.size(withAttributes: [.font: font])
                let chipSize = CGSize(width: max(textSize.width + 8, 16), height: 15)
                let preferred = CGRect(
                    x: rect.minX - 4,
                    y: rect.minY - chipSize.height + 4,
                    width: chipSize.width,
                    height: chipSize.height
                )
                let chip = place(preferred, avoiding: placedChips, near: rect, within: bounds)
                placedChips.append(chip)

                color.setFill()
                UIBezierPath(roundedRect: chip, cornerRadius: 4).fill()

                label.draw(
                    at: CGPoint(x: chip.midX - textSize.width / 2, y: chip.midY - textSize.height / 2),
                    withAttributes: [.font: font, .foregroundColor: UIColor.black.withAlphaComponent(0.9)]
                )
            }
        }
    }

    /// Kind palette: buttons cyan, links blue, fields amber, toggles pink,
    /// dropdowns green, everything else gray.
    private static func badgeColor(for kind: ScannedElement.Kind) -> UIColor {
        switch kind {
        case .button: UIColor(red: 0.0, green: 0.898, blue: 1.0, alpha: 1)
        case .link: UIColor(red: 0.36, green: 0.64, blue: 1.0, alpha: 1)
        case .field: UIColor(red: 1.0, green: 0.706, blue: 0.329, alpha: 1)
        case .toggle: UIColor(red: 1.0, green: 0.42, blue: 0.71, alpha: 1)
        case .dropdown: UIColor(red: 0.24, green: 0.863, blue: 0.592, alpha: 1)
        case .other: UIColor(red: 0.73, green: 0.77, blue: 0.82, alpha: 1)
        }
    }

    /// Nudges a chip so it stays inside the image and never covers another chip:
    /// tries the outer corner, then inside/right/below alternatives, then gives up
    /// gracefully on the clamped preferred spot.
    private static func place(
        _ preferred: CGRect,
        avoiding placed: [CGRect],
        near target: CGRect,
        within bounds: CGRect
    ) -> CGRect {
        let candidates: [CGRect] = [
            preferred,
            CGRect(x: target.minX + 2, y: target.minY + 2, width: preferred.width, height: preferred.height),
            CGRect(x: target.maxX - preferred.width + 4, y: target.minY - preferred.height + 4, width: preferred.width, height: preferred.height),
            CGRect(x: target.minX - 4, y: target.maxY - 4, width: preferred.width, height: preferred.height),
            preferred.offsetBy(dx: 0, dy: preferred.height + 2),
            preferred.offsetBy(dx: preferred.width + 4, dy: 0),
            CGRect(x: target.midX - preferred.width / 2, y: target.minY + 2, width: preferred.width, height: preferred.height),
        ]

        for candidate in candidates {
            let clamped = clamp(candidate, within: bounds)
            if !placed.contains(where: { $0.intersects(clamped.insetBy(dx: -1, dy: -1)) }) {
                return clamped
            }
        }
        return clamp(preferred, within: bounds)
    }

    private static func clamp(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        var clamped = rect
        clamped.origin.x = min(max(clamped.origin.x, bounds.minX), max(bounds.maxX - clamped.width, 0))
        clamped.origin.y = min(max(clamped.origin.y, bounds.minY), max(bounds.maxY - clamped.height, 0))
        return clamped
    }
}
