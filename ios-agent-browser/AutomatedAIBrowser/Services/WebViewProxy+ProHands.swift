import WebKit
import UIKit

/// Pair 2's pro hands: precision form moves, gestures, whole-page sight, the
/// reaction watcher, and embedded-panel scanning/routing. Every method fails
/// soft with a readable result line — a mission can never crash from these.
extension WebViewProxy {

    // MARK: - Embedded panels (scan + merge)

    nonisolated struct IframeBox: Decodable {
        let src: String
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }

    /// Scans up to 2 visible embedded panels and merges their elements into the
    /// main observation with global numbering, offset rects, and action routes.
    /// Panels that resist scanning are counted and reported in the map.
    func mergingPanelElements(into observation: PageObservation) async -> PageObservation {
        let listRaw = await runJS(PageScanner.iframeListScript)
        guard let data = listRaw.data(using: .utf8),
              let iframes = try? JSONDecoder().decode([IframeBox].self, from: data),
              !iframes.isEmpty else {
            return observation
        }

        var elements = observation.elements
        var nextID = (elements.map(\.id).max() ?? 0) + 1
        var blocked = 0
        var scanned = 0
        var usedPanels = Set<String>()

        for box in iframes {
            guard scanned < 2 else {
                blocked += 1
                continue
            }
            guard let panel = frameRegistry.match(src: box.src, excluding: usedPanels) else {
                blocked += 1
                continue
            }
            usedPanels.insert(panel.urlString)
            let frameRaw = await runJS(PageScanner.scanScript, in: panel.frame)
            guard let frameObservation = PageScanner.parse(frameRaw) else {
                blocked += 1
                continue
            }
            scanned += 1
            for element in frameObservation.elements.prefix(40) {
                let globalX = element.x + box.x
                let globalY = element.y + box.y
                let centerX = globalX + element.width / 2
                let centerY = globalY + element.height / 2
                guard centerX > 0, centerX < observation.viewportWidth,
                      centerY > 0, centerY < observation.viewportHeight,
                      centerX >= box.x, centerX <= box.x + box.w,
                      centerY >= box.y, centerY <= box.y + box.h else { continue }
                var merged = ScannedElement(
                    id: nextID,
                    kind: element.kind,
                    name: element.name,
                    states: element.states,
                    valuePreview: element.valuePreview,
                    isEditable: element.isEditable,
                    x: globalX,
                    y: globalY,
                    width: element.width,
                    height: element.height
                )
                merged.panelLabel = panel.host
                elements.append(merged)
                panelRoutes[nextID] = PanelRoute(
                    frame: panel.frame,
                    localID: element.id,
                    host: panel.host,
                    originX: box.x,
                    originY: box.y
                )
                nextID += 1
            }
        }

        guard blocked > 0 || elements.count != observation.elements.count else { return observation }
        return observation.replacingElements(elements, blockedPanelCount: blocked)
    }

    // MARK: - Reaction watcher (the honesty layer)

    /// Starts the change-watcher in the frame that owns `targetID` (or the main
    /// frame). Call before executing a gesture or form move.
    func beginReactionWatch(targetID: Int?) async {
        reactionWatchFrame = targetID.flatMap { panelRoutes[$0]?.frame }
        reactionWatchURL = currentURLString
        _ = await runJS(ReactionWatch.startScript, in: reactionWatchFrame)
    }

    /// Stops the watcher and returns the plain-language verdict.
    func endReactionWatch() async -> String {
        let raw = await runJS(ReactionWatch.endScript, in: reactionWatchFrame)
        reactionWatchFrame = nil
        let navigated = currentURLString != reactionWatchURL
        return ReactionWatch.verdict(fromRaw: raw, pageNavigated: navigated).text
    }

    /// Reads back what a field holds right now — the honest evidence that typing
    /// landed. nil means the field is no longer reachable on the page.
    func fieldValue(id: Int, expectedName: String) async -> String? {
        let route = panelRoutes[id]
        let raw = await runJS(
            PageScanner.fieldValueScript(id: route?.localID ?? id, expectedName: expectedName),
            in: route?.frame
        )
        if raw == PageScanner.missingFieldSentinel || raw.hasPrefix("js error:") { return nil }
        return raw
    }

    /// Reads back what the focused field holds — the type_text counterpart.
    func focusedFieldValue() async -> String? {
        let raw = await runJS(#"""
            (function(){
              try {
                var el = document.activeElement;
                if (!el || el === document.body) { return '\#(PageScanner.missingFieldSentinel)'; }
                if (el.isContentEditable) { return String(el.innerText || '').slice(0, 120); }
                if ('value' in el) { return String(el.value == null ? '' : el.value).slice(0, 120); }
                return '\#(PageScanner.missingFieldSentinel)';
              } catch (e) { return '\#(PageScanner.missingFieldSentinel)'; }
            })()
            """#)
        if raw == PageScanner.missingFieldSentinel || raw.hasPrefix("js error:") { return nil }
        return raw
    }

    // MARK: - Precision form hands

    func selectOption(id: Int, option: String, expectedName: String) async -> String {
        let route = panelRoutes[id]
        return await runJS(
            FormScripts.selectScript(id: route?.localID ?? id, display: id, option: option, expectedName: expectedName),
            in: route?.frame
        )
    }

    func setToggle(id: Int, on: Bool, expectedName: String) async -> String {
        let route = panelRoutes[id]
        return await runJS(
            FormScripts.toggleScript(id: route?.localID ?? id, display: id, on: on, expectedName: expectedName),
            in: route?.frame
        )
    }

    func setSlider(id: Int, percent: Double, expectedName: String) async -> String {
        let route = panelRoutes[id]
        return await runJS(
            FormScripts.sliderScript(id: route?.localID ?? id, display: id, percent: percent, expectedName: expectedName),
            in: route?.frame
        )
    }

    /// Fills several fields in order with the same reliable typing used by
    /// type_into (stale re-match included), submitting on the last field when
    /// asked. Reports per-field success.
    func fillForm(_ entries: [(id: Int, text: String, expectedName: String)], submit: Bool) async -> String {
        guard !entries.isEmpty else { return "fill_form had no fields" }
        var filled = 0
        var failures: [String] = []
        for (index, entry) in entries.enumerated() {
            let route = panelRoutes[entry.id]
            let isLast = index == entries.count - 1
            let raw = await runJS(
                PageScanner.typeScript(
                    id: route?.localID ?? entry.id,
                    display: entry.id,
                    text: entry.text,
                    submit: submit && isLast,
                    descriptor: "",
                    expectedName: entry.expectedName
                ),
                in: route?.frame
            )
            if raw.hasPrefix("typed") {
                filled += 1
            } else {
                failures.append("[\(entry.id)]: \(String(raw.prefix(80)))")
            }
            try? await Task.sleep(for: .milliseconds(220))
        }
        var message = "filled \(filled) of \(entries.count) field\(entries.count == 1 ? "" : "s")"
        if submit { message += filled == entries.count ? " and submitted" : " (submit attempted on the last field)" }
        if !failures.isEmpty { message += " — " + failures.joined(separator: "; ") }
        return String(message.prefix(320))
    }

    // MARK: - Gesture hands

    /// Drag between two numbered elements (or normalized 0–1000 coordinate
    /// fallbacks). HTML5 drag-and-drop completes in one phase; pointer drags
    /// run in two phases with a real-time pause for believable timing.
    func drag(
        fromID: Int?, toID: Int?,
        fromNormX: Double?, fromNormY: Double?,
        toNormX: Double?, toNormY: Double?,
        fromName: String, toName: String
    ) async -> String {
        let fromRoute = fromID.flatMap { panelRoutes[$0] }
        let toRoute = toID.flatMap { panelRoutes[$0] }
        if fromID != nil, toID != nil, fromRoute?.frame !== toRoute?.frame {
            return "drag endpoints live in different embedded panels — not supported; try another approach"
        }
        let route = fromRoute ?? toRoute
        let bounds = webView.bounds

        func pixels(_ norm: Double?, along axis: CGFloat, origin: Double) -> Double? {
            guard let norm else { return nil }
            let mainPixels = min(max(norm, 0), 1000) / 1000.0 * Double(axis)
            return route == nil ? mainPixels : mainPixels - origin
        }

        let phase1 = await runJS(
            GestureScripts.dragPhase1(
                fromID: fromRoute?.localID ?? fromID,
                fromName: fromName,
                fromX: pixels(fromNormX, along: bounds.width, origin: route?.originX ?? 0),
                fromY: pixels(fromNormY, along: bounds.height, origin: route?.originY ?? 0),
                toID: toRoute?.localID ?? toID,
                toName: toName,
                toX: pixels(toNormX, along: bounds.width, origin: route?.originX ?? 0),
                toY: pixels(toNormY, along: bounds.height, origin: route?.originY ?? 0),
                fromDisplay: fromID.map { "[\($0)]" } ?? "the start point",
                toDisplay: toID.map { "[\($0)]" } ?? "the end point"
            ),
            in: route?.frame
        )
        guard phase1 == "staged" else { return phase1 }
        try? await Task.sleep(for: .milliseconds(180))
        return await runJS(GestureScripts.dragPhase2, in: route?.frame)
    }

    /// Press and hold (~0.65s) — triggers hold-actions the site itself defines.
    func longPress(id: Int, expectedName: String) async -> String {
        let route = panelRoutes[id]
        let phase1 = await runJS(
            GestureScripts.longPressPhase1(id: route?.localID ?? id, display: id, expectedName: expectedName),
            in: route?.frame
        )
        guard phase1 == "staged" else { return phase1 }
        try? await Task.sleep(for: .milliseconds(650))
        return await runJS(GestureScripts.longPressPhase2, in: route?.frame)
    }

    /// Hover signals to wake desktop-style hover menus.
    func hover(id: Int, expectedName: String) async -> String {
        let route = panelRoutes[id]
        return await runJS(
            GestureScripts.hoverScript(id: route?.localID ?? id, display: id, expectedName: expectedName),
            in: route?.frame
        )
    }

    /// Swipes a carousel/strip: slides the scrollable strip itself when one
    /// exists (and measures the movement), else a synthetic finger swipe.
    func swipe(direction: String, elementID: Int?, expectedName: String) async -> String {
        let route = elementID.flatMap { panelRoutes[$0] }
        let display = elementID.map { "[\($0)]" } ?? "the visible area"
        let phase1 = await runJS(
            GestureScripts.swipePhase1(
                direction: direction,
                id: route?.localID ?? elementID,
                display: display,
                expectedName: expectedName
            ),
            in: route?.frame
        )
        guard phase1 == "staged" else { return phase1 }
        try? await Task.sleep(for: .milliseconds(700))
        let phase2 = await runJS(GestureScripts.swipePhase2, in: route?.frame)
        return phase2.isEmpty ? "slid the strip — movement not measurable" : phase2
    }

    // MARK: - Whole-page overview capture

    enum OverviewCapture {
        case captured(image: UIImage, note: String)
        case singleScreen
        case failed(String)
    }

    /// Photographs the page screen by screen (sticky bars hidden after the
    /// first slice), stitches the slices into one tall picture, and restores
    /// the scroll position — even when interrupted mid-way.
    func capturePageOverview() async -> OverviewCapture {
        let metricsRaw = await runJS(OverviewPlanner.metricsScript)
        guard let data = metricsRaw.data(using: .utf8),
              let metrics = try? JSONDecoder().decode(OverviewPlanner.Metrics.self, from: data),
              metrics.vh > 1 else {
            return .failed("the page didn't report its size")
        }
        guard let plan = OverviewPlanner.plan(documentHeight: metrics.dh, viewportHeight: metrics.vh) else {
            return .singleScreen
        }

        var slices: [UIImage] = []
        var hidSticky = false
        for (index, offset) in plan.offsets.enumerated() {
            _ = await runJS("(function(){ window.scrollTo({ top: \(Int(offset)), left: 0, behavior: 'instant' }); return 'ok'; })()")
            if index > 0 && !hidSticky {
                _ = await runJS(OverviewPlanner.hideStickyScript)
                hidSticky = true
            }
            try? await Task.sleep(for: .milliseconds(index == 0 ? 220 : 340))
            guard let slice = await snapshot(width: 500) else { break }
            slices.append(slice)
        }

        if hidSticky {
            _ = await runJS(OverviewPlanner.restoreStickyScript)
        }
        _ = await runJS("(function(){ window.scrollTo({ top: \(Int(metrics.sy)), left: 0, behavior: 'instant' }); return 'ok'; })()")

        guard slices.count == plan.offsets.count,
              let stitched = OverviewStitcher.stitch(slices, lastSliceCropFraction: plan.lastSliceCropFraction) else {
            return .failed("couldn't photograph every screen")
        }
        return .captured(image: stitched, note: plan.coverageNote)
    }
}
