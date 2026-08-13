import SwiftUI

/// The app's Liquid Glass vocabulary.
///
/// Agent Browser is a cockpit floating over live web content, which is exactly
/// what this material was designed for: the page shows through and refracts, so
/// you never lose sight of what the agent is looking at.
///
/// Glass goes on the **navigation layer only** — the header cluster, the telemetry
/// strip, the command bar, the floating controls. It is deliberately kept off step
/// cards, screenshots, page maps and lists: those are content, and translucency
/// there fights the very thing it is meant to present.
///
/// The app's minimum is iOS 26, so none of this needs an availability guard or a
/// material fallback.
extension View {
    /// A chrome plate — the strips and bars that frame the page.
    ///
    /// Tinted toward the app's own charcoal so cyan telemetry text keeps its
    /// contrast over a bright web page instead of washing out.
    func hudGlass<S: Shape>(_ shape: S) -> some View {
        // A deeper charcoal scrim: over a bright white page the light cockpit
        // text keeps its contrast instead of washing out in the refraction.
        glassEffect(.regular.tint(Theme.bg.opacity(0.66)), in: shape)
    }

    /// An interactive control that responds to touch.
    ///
    /// `tint` is for the one control in a cluster that matters most; tinting
    /// everything would flatten the hierarchy it exists to create.
    @ViewBuilder
    func controlGlass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if let tint {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            glassEffect(.regular.interactive(), in: shape)
        }
    }
}
