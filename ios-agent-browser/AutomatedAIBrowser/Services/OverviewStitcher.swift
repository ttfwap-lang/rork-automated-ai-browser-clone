import UIKit

/// Joins viewport slices into one tall overview image: crops the last slice's
/// overlapping top and caps the output height so the picture stays a sane size
/// for AI transport.
enum OverviewStitcher {

    static func stitch(
        _ slices: [UIImage],
        lastSliceCropFraction: Double,
        maxOutputHeight: CGFloat = 4200
    ) -> UIImage? {
        guard let first = slices.first else { return nil }
        guard slices.count > 1 else { return first }
        let width = slices.map { $0.size.width }.min() ?? first.size.width
        guard width > 1 else { return nil }

        let crop = CGFloat(min(max(lastSliceCropFraction, 0), 0.95))
        var visibleHeights: [CGFloat] = []
        for (index, slice) in slices.enumerated() {
            let scaledHeight = slice.size.height * (width / max(slice.size.width, 1))
            let cropped = index == slices.count - 1 ? scaledHeight * crop : 0
            visibleHeights.append(max(scaledHeight - cropped, 0))
        }
        let totalHeight = visibleHeights.reduce(0, +)
        guard totalHeight > 1 else { return nil }

        let scale = min(1, maxOutputHeight / totalHeight)
        let outputSize = CGSize(
            width: (width * scale).rounded(),
            height: (totalHeight * scale).rounded()
        )
        guard outputSize.width > 1, outputSize.height > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)

        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            var y: CGFloat = 0
            for (index, slice) in slices.enumerated() {
                let drawWidth = width * scale
                let fullHeight = slice.size.height * (width / max(slice.size.width, 1)) * scale
                let visibleHeight = visibleHeights[index] * scale
                guard visibleHeight > 0.5 else { continue }
                let cropOffset = fullHeight - visibleHeight
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: y, width: drawWidth, height: visibleHeight))
                slice.draw(in: CGRect(x: 0, y: y - cropOffset, width: drawWidth, height: fullHeight))
                context.cgContext.restoreGState()
                y += visibleHeight
            }
        }
    }
}
