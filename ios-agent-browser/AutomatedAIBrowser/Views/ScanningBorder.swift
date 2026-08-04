import SwiftUI

/// A cyan shimmer that sweeps around the browser edge while the AI is observing/thinking.
struct ScanningBorder: View {
    let active: Bool
    var cornerRadius: CGFloat = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(t.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360)
            let gradient = AngularGradient(
                gradient: Gradient(colors: [
                    .clear, .clear, .clear,
                    Theme.cyan.opacity(0.15),
                    Theme.cyan,
                    Theme.cyan.opacity(0.15),
                    .clear, .clear, .clear,
                ]),
                center: .center,
                angle: angle
            )
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(gradient, lineWidth: 3)
                    .blur(radius: 5)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(gradient, lineWidth: 1.5)
            }
        }
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: active)
        .allowsHitTesting(false)
    }
}
