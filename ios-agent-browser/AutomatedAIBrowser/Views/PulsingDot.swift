import SwiftUI

/// Small breathing indicator dot used in the status strip and mission log.
struct PulsingDot: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 4)
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Circle()
                    .stroke(color.opacity(0.6 * (1 - pulse)), lineWidth: 1.5)
                    .frame(width: 7, height: 7)
                    .scaleEffect(1 + pulse * 1.2)
            }
        }
        .frame(width: 16, height: 16)
    }
}
