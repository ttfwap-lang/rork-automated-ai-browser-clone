import Foundation

/// Slice math and helper scripts for the stitched whole-page overview: which
/// scroll offsets to photograph, how much of the last slice overlaps the one
/// before it, and what the coverage note should say. Pure and unit-testable.
nonisolated enum OverviewPlanner {

    /// Hard cap on how many screens one overview may photograph.
    static let maxSlices = 6

    nonisolated struct Plan: Equatable {
        /// Scroll offsets (CSS px) to photograph, in order.
        let offsets: [Double]
        /// Fraction (0–1) of the LAST slice's height that duplicates the
        /// previous slice and must be cropped from its top when stitching.
        let lastSliceCropFraction: Double
        /// Total screens the document spans (rounded up).
        let totalScreens: Int
        /// Fraction (0–1) of the document the overview covers.
        let coveredFraction: Double

        var coverageNote: String {
            if coveredFraction >= 0.999 {
                return totalScreens <= 2
                    ? "covers the whole page"
                    : "covers the whole page (~\(totalScreens) screens)"
            }
            let percent = Int((coveredFraction * 100).rounded())
            return "covers the first \(offsets.count) of ~\(totalScreens) screens (about \(percent)% of the page)"
        }
    }

    /// Page metrics reported by `metricsScript`.
    nonisolated struct Metrics: Decodable {
        let sy: Double
        let vh: Double
        let dh: Double
    }

    /// Returns nil when the page fits in one screen (no overview needed).
    static func plan(documentHeight: Double, viewportHeight: Double, maxSlices: Int = OverviewPlanner.maxSlices) -> Plan? {
        guard viewportHeight > 1, documentHeight > viewportHeight * 1.05, maxSlices > 1 else { return nil }
        let totalScreens = Int(ceil(documentHeight / viewportHeight - 0.02))
        let sliceCount = min(max(totalScreens, 2), maxSlices)
        let maxScroll = documentHeight - viewportHeight
        var offsets: [Double] = []
        for index in 0..<sliceCount {
            offsets.append(min(Double(index) * viewportHeight, maxScroll))
        }
        guard let last = offsets.last, offsets.count > 1 else { return nil }
        let overlap = max(Double(sliceCount - 1) * viewportHeight - last, 0)
        let covered = min(last + viewportHeight, documentHeight)
        return Plan(
            offsets: offsets,
            lastSliceCropFraction: min(overlap / viewportHeight, 0.95),
            totalScreens: totalScreens,
            coveredFraction: min(covered / documentHeight, 1)
        )
    }

    // MARK: - Capture helper scripts

    static let metricsScript = #"""
        (function(){
          try {
            var d = document.documentElement;
            var b = document.body;
            var dh = Math.max(d ? d.scrollHeight : 0, b ? b.scrollHeight : 0);
            return JSON.stringify({ sy: window.scrollY || 0, vh: window.innerHeight || 0, dh: dh });
          } catch (e) { return '{}'; }
        })()
        """#

    /// Temporarily hides fixed/sticky bars (marked for exact restoration) so
    /// they don't repeat on every slice of the stitched overview.
    static let hideStickyScript = #"""
        (function(){
          try {
            var hidden = 0;
            var all = document.body ? document.body.querySelectorAll('*') : [];
            var limit = Math.min(all.length, 1600);
            for (var i = 0; i < limit && hidden < 40; i++) {
              var el = all[i];
              var cs;
              try { cs = getComputedStyle(el); } catch (e) { continue; }
              if (cs.position !== 'fixed' && cs.position !== 'sticky') { continue; }
              if (cs.visibility === 'hidden' || cs.display === 'none') { continue; }
              var r = el.getBoundingClientRect();
              if (r.width < 8 || r.height < 8) { continue; }
              el.setAttribute('data-rork-hidden', el.style.visibility || '__none__');
              el.style.setProperty('visibility', 'hidden', 'important');
              hidden++;
            }
            return 'hid ' + hidden;
          } catch (e) { return 'hide error'; }
        })()
        """#

    static let restoreStickyScript = #"""
        (function(){
          try {
            var els = document.querySelectorAll('[data-rork-hidden]');
            for (var i = 0; i < els.length; i++) {
              var old = els[i].getAttribute('data-rork-hidden');
              if (old && old !== '__none__') { els[i].style.visibility = old; }
              else { els[i].style.removeProperty('visibility'); }
              els[i].removeAttribute('data-rork-hidden');
            }
            return 'restored ' + els.length;
          } catch (e) { return 'restore error'; }
        })()
        """#
}
