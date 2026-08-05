import SwiftUI

/// Reveals text a few characters at a time, so a thought reads as if it is
/// arriving rather than appearing fully formed.
///
/// The reveal is cosmetic only: the full string is laid out invisibly underneath
/// so the panel never resizes mid-sentence, which would make the whole cockpit
/// jitter every time the agent thought something slightly longer.
struct TypewriterText: View {
    let text: String
    var font: Font = .system(size: 12.5, design: .monospaced)
    var color: Color = Theme.textPrimary
    /// Characters revealed per second.
    var speed: Double = 90
    var lineLimit: Int = 3

    @State private var revealed = 0

    var body: some View {
        Text(String(text.prefix(revealed)))
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(alignment: .topLeading) {
                // Reserves the final height up front so nothing jumps.
                Text(text)
                    .font(font)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
            }
            .task(id: text) {
                revealed = 0
                let total = text.count
                guard total > 0 else { return }
                let tick = UInt64((1_000_000_000 / max(speed, 1)).rounded())
                while revealed < total {
                    try? await Task.sleep(nanoseconds: tick)
                    guard !Task.isCancelled else { return }
                    revealed = min(revealed + 2, total)
                }
            }
    }
}
