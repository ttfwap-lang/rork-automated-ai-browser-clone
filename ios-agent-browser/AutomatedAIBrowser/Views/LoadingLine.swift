import SwiftUI

/// Indeterminate cyan sweep shown under the toolbar while a page loads.
struct LoadingLine: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { geo in
                let width = geo.size.width
                let t = context.date.timeIntervalSinceReferenceDate
                let progress = t.truncatingRemainder(dividingBy: 1.2) / 1.2
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Theme.cyan, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.35)
                    .offset(x: -0.35 * width + progress * (1.35 * width))
            }
        }
        .frame(height: 2)
        .clipped()
    }
}
