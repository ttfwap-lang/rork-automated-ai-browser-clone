import Foundation

/// JS builders for the gesture hands: drag, long-press, hover, and swipe.
/// Gestures are synthetic signal sequences (pointer + mouse + touch); a
/// minority of sites only respond to real fingers — which is why every gesture
/// runs inside the reaction watcher and reports honestly. Two-phase gestures
/// stage state on `window` so real time can pass between down and up.
nonisolated enum GestureScripts {

    private static func jsInt(_ value: Int?) -> String {
        value.map(String.init) ?? "null"
    }

    private static func jsNumber(_ value: Double?) -> String {
        guard let value else { return "null" }
        return String(format: "%.1f", value)
    }

    /// Shared event-firing helper embedded into gesture scripts.
    private static let fireFunction = #"""
        function __fire(Ctor, type, target, x, y) {
          try {
            target.dispatchEvent(new Ctor(type, { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, buttons: 1, pointerId: 7, isPrimary: true, pointerType: 'touch' }));
          } catch (e) {}
        }
        function __touch(type, target, x, y, ended) {
          try {
            var t = new Touch({ identifier: 7, target: target, clientX: x, clientY: y });
            target.dispatchEvent(new TouchEvent(type, { touches: ended ? [] : [t], targetTouches: ended ? [] : [t], changedTouches: [t], bubbles: true, cancelable: true }));
          } catch (e) {}
        }
        """#

    // MARK: - Drag (two-phase)

    /// Phase 1: resolves both endpoints. If the source is an HTML5 draggable,
    /// the full drag-and-drop sequence completes here. Otherwise it presses
    /// down and moves partway, staging state for phase 2. Returns 'staged'
    /// when phase 2 must run.
    static func dragPhase1(
        fromID: Int?, fromName: String, fromX: Double?, fromY: Double?,
        toID: Int?, toName: String, toX: Double?, toY: Double?,
        fromDisplay: String, toDisplay: String
    ) -> String {
        #"""
        (function(){
          \#(PageScanner.rippleFunction)
          \#(PageScanner.findFunction)
          \#(fireFunction)
          try {
            var fromID = \#(jsInt(fromID)), toID = \#(jsInt(toID));
            var srcEl = fromID != null ? __find(fromID, \#(PageScanner.jsStringLiteral(fromName)), false) : null;
            var dstEl = toID != null ? __find(toID, \#(PageScanner.jsStringLiteral(toName)), false) : null;
            if (fromID != null && !srcEl) { return 'drag source \#(fromDisplay) is no longer on the page — look again before acting'; }
            if (toID != null && !dstEl) { return 'drag target \#(toDisplay) is no longer on the page — look again before acting'; }
            function center(el) {
              var r = el.getBoundingClientRect();
              return {
                x: Math.max(1, Math.min(window.innerWidth - 1, r.left + r.width / 2)),
                y: Math.max(1, Math.min(window.innerHeight - 1, r.top + r.height / 2))
              };
            }
            var fx = \#(jsNumber(fromX)), fy = \#(jsNumber(fromY)), tx = \#(jsNumber(toX)), ty = \#(jsNumber(toY));
            if (srcEl) { try { srcEl.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' }); } catch (e) {} var c = center(srcEl); fx = c.x; fy = c.y; }
            if (dstEl) { var c2 = center(dstEl); tx = c2.x; ty = c2.y; }
            if (fx == null || fy == null) { return 'drag needs a source — give a from element number or from_x/from_y'; }
            if (tx == null || ty == null) { return 'drag needs a target — give a to element number or to_x/to_y'; }
            var srcHit = srcEl || document.elementFromPoint(fx, fy);
            if (!srcHit) { return 'nothing at the drag start point'; }
            var dstHit = dstEl || document.elementFromPoint(tx, ty) || document.body;
            __ripple(fx, fy);
            var d5 = srcHit.closest ? srcHit.closest('[draggable="true"]') : null;
            if (d5) {
              try {
                var dt = new DataTransfer();
                function fireDrag(type, target, x, y) {
                  var ev = new DragEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, dataTransfer: dt });
                  target.dispatchEvent(ev);
                }
                fireDrag('dragstart', d5, fx, fy);
                fireDrag('dragenter', dstHit, tx, ty);
                fireDrag('dragover', dstHit, tx, ty);
                fireDrag('drop', dstHit, tx, ty);
                fireDrag('dragend', d5, tx, ty);
                __ripple(tx, ty);
                window.__rorkDrag = null;
                return 'dragged \#(fromDisplay) to \#(toDisplay) via drag-and-drop';
              } catch (e) {}
            }
            __fire(PointerEvent, 'pointerdown', srcHit, fx, fy);
            __fire(MouseEvent, 'mousedown', srcHit, fx, fy);
            __touch('touchstart', srcHit, fx, fy, false);
            for (var i = 1; i <= 3; i++) {
              var mx = fx + (tx - fx) * i * 0.15, my = fy + (ty - fy) * i * 0.15;
              var over = document.elementFromPoint(mx, my) || srcHit;
              __fire(PointerEvent, 'pointermove', over, mx, my);
              __fire(MouseEvent, 'mousemove', over, mx, my);
              __touch('touchmove', over, mx, my, false);
            }
            window.__rorkDrag = { sx: fx, sy: fy, tx: tx, ty: ty, src: srcHit, dst: dstHit };
            return 'staged';
          } catch (e) { return 'drag error: ' + e.message; }
        })()
        """#
    }

    /// Phase 2: finishes the pointer path (remaining moves + release) after a
    /// real-time pause, so drag libraries see believable timing.
    static let dragPhase2 = #"""
        (function(){
          \#(rippleFunctionRef)
          \#(fireFunction)
          try {
            var d = window.__rorkDrag;
            if (!d || !d.src) { return 'drag lost its state — the page may have reloaded; look again'; }
            window.__rorkDrag = null;
            for (var i = 1; i <= 5; i++) {
              var f = 0.45 + i * 0.11;
              var mx = d.sx + (d.tx - d.sx) * f, my = d.sy + (d.ty - d.sy) * f;
              var over = document.elementFromPoint(mx, my) || d.dst;
              __fire(PointerEvent, 'pointermove', over, mx, my);
              __fire(MouseEvent, 'mousemove', over, mx, my);
              __touch('touchmove', over, mx, my, false);
            }
            var up = document.elementFromPoint(d.tx, d.ty) || d.dst;
            __fire(PointerEvent, 'pointerup', up, d.tx, d.ty);
            __fire(MouseEvent, 'mouseup', up, d.tx, d.ty);
            __touch('touchend', up, d.tx, d.ty, true);
            __ripple(d.tx, d.ty);
            return 'dragged from (' + Math.round(d.sx) + ', ' + Math.round(d.sy) + ') to (' + Math.round(d.tx) + ', ' + Math.round(d.ty) + ') with pointer signals';
          } catch (e) { return 'drag error: ' + e.message; }
        })()
        """#

    // MARK: - Long-press (two-phase)

    /// Phase 1: press down on the element and stage the hold.
    static func longPressPhase1(id: Int, display: Int, expectedName: String) -> String {
        #"""
        (function(){
          \#(PageScanner.rippleFunction)
          \#(PageScanner.findFunction)
          \#(fireFunction)
          try {
            var el = __find(\#(id), \#(PageScanner.jsStringLiteral(expectedName)), false);
            if (!el) { return 'element \#(display) is no longer on the page — the page changed; look again before acting'; }
            try { el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' }); } catch (e) {}
            var r = el.getBoundingClientRect();
            var x = Math.max(1, Math.min(window.innerWidth - 1, r.left + r.width / 2));
            var y = Math.max(1, Math.min(window.innerHeight - 1, r.top + r.height / 2));
            __ripple(x, y);
            __fire(PointerEvent, 'pointerdown', el, x, y);
            __fire(MouseEvent, 'mousedown', el, x, y);
            __touch('touchstart', el, x, y, false);
            window.__rorkHold = { el: el, x: x, y: y, label: '\#(display)' };
            return 'staged';
          } catch (e) { return 'long-press error: ' + e.message; }
        })()
        """#
    }

    /// Phase 2: release after the real-time hold and fire the context-menu
    /// signal sites listen for.
    static let longPressPhase2 = #"""
        (function(){
          \#(fireFunction)
          try {
            var h = window.__rorkHold;
            if (!h || !h.el) { return 'long-press lost its state — the page may have reloaded; look again'; }
            window.__rorkHold = null;
            __fire(PointerEvent, 'pointerup', h.el, h.x, h.y);
            __fire(MouseEvent, 'mouseup', h.el, h.x, h.y);
            __touch('touchend', h.el, h.x, h.y, true);
            try { h.el.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, view: window, clientX: h.x, clientY: h.y })); } catch (e) {}
            return 'held [' + h.label + '] for ~0.65s — any hold-action the site defines should have fired';
          } catch (e) { return 'long-press error: ' + e.message; }
        })()
        """#

    // MARK: - Hover (single-phase)

    /// Wakes hover menus: over/enter/move signals on the element and its
    /// ancestors. New elements are reported by the reaction watcher.
    static func hoverScript(id: Int, display: Int, expectedName: String) -> String {
        #"""
        (function(){
          \#(PageScanner.rippleFunction)
          \#(PageScanner.findFunction)
          try {
            var el = __find(\#(id), \#(PageScanner.jsStringLiteral(expectedName)), false);
            if (!el) { return 'element \#(display) is no longer on the page — the page changed; look again before acting'; }
            try { el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' }); } catch (e) {}
            var r = el.getBoundingClientRect();
            var x = Math.max(1, Math.min(window.innerWidth - 1, r.left + r.width / 2));
            var y = Math.max(1, Math.min(window.innerHeight - 1, r.top + r.height / 2));
            __ripple(x, y);
            var opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
            try { el.dispatchEvent(new PointerEvent('pointerover', opts)); } catch (e) {}
            el.dispatchEvent(new MouseEvent('mouseover', opts));
            el.dispatchEvent(new MouseEvent('mousemove', opts));
            var node = el, hops = 0;
            while (node && node.nodeType === 1 && hops < 5) {
              try { node.dispatchEvent(new PointerEvent('pointerenter', { bubbles: false, view: window, clientX: x, clientY: y })); } catch (e) {}
              try { node.dispatchEvent(new MouseEvent('mouseenter', { bubbles: false, view: window, clientX: x, clientY: y })); } catch (e) {}
              node = node.parentElement;
              hops++;
            }
            return 'hovered over [\#(display)]';
          } catch (e) { return 'hover error: ' + e.message; }
        })()
        """#
    }

    // MARK: - Swipe (two-phase)

    /// Phase 1: prefers sliding the scrollable strip itself (reliable), staging
    /// a measurement for phase 2; falls back to a synthetic finger swipe.
    static func swipePhase1(direction: String, id: Int?, display: String, expectedName: String) -> String {
        let isLeft = direction.lowercased() != "right"
        return #"""
        (function(){
          \#(PageScanner.rippleFunction)
          \#(PageScanner.findFunction)
          \#(fireFunction)
          try {
            var dirLeft = \#(isLeft ? "true" : "false");
            var id = \#(jsInt(id));
            var start = id != null ? __find(id, \#(PageScanner.jsStringLiteral(expectedName)), false) : null;
            if (id != null && !start) { return 'element \#(display) is no longer on the page — look again before acting'; }
            if (!start) { start = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2) || document.body; }
            function scrollableX(n) {
              var hops = 0;
              while (n && n !== document.body && n.nodeType === 1 && hops < 20) {
                try {
                  var cs = getComputedStyle(n);
                  if ((cs.overflowX === 'auto' || cs.overflowX === 'scroll') && n.scrollWidth > n.clientWidth + 10) { return n; }
                } catch (e) {}
                n = n.parentElement;
                hops++;
              }
              return null;
            }
            var strip = scrollableX(start);
            var box = (strip || start).getBoundingClientRect();
            var midY = Math.max(1, Math.min(window.innerHeight - 1, box.top + box.height / 2));
            if (strip) {
              var before = strip.scrollLeft;
              __ripple(Math.max(1, Math.min(window.innerWidth - 1, box.left + box.width / 2)), midY);
              strip.scrollBy({ left: strip.clientWidth * 0.85 * (dirLeft ? 1 : -1), behavior: 'smooth' });
              window.__rorkSwipe = { el: strip, before: before };
              return 'staged';
            }
            var fromX = dirLeft ? window.innerWidth * 0.8 : window.innerWidth * 0.2;
            var toX = dirLeft ? window.innerWidth * 0.2 : window.innerWidth * 0.8;
            __ripple(fromX, midY);
            __fire(PointerEvent, 'pointerdown', start, fromX, midY);
            __touch('touchstart', start, fromX, midY, false);
            for (var i = 1; i <= 6; i++) {
              var x = fromX + (toX - fromX) * i / 6;
              __fire(PointerEvent, 'pointermove', start, x, midY);
              __touch('touchmove', start, x, midY, false);
            }
            __fire(PointerEvent, 'pointerup', start, toX, midY);
            __touch('touchend', start, toX, midY, true);
            __ripple(toX, midY);
            window.__rorkSwipe = null;
            return 'swiped ' + (dirLeft ? 'left' : 'right') + ' across \#(display) with touch signals';
          } catch (e) { return 'swipe error: ' + e.message; }
        })()
        """#
    }

    /// Phase 2: measures how far the strip actually moved. Returns '' when
    /// phase 1 already produced the final message (touch fallback path).
    static let swipePhase2 = #"""
        (function(){
          try {
            var s = window.__rorkSwipe;
            if (!s || !s.el) { return ''; }
            window.__rorkSwipe = null;
            var delta = Math.round(s.el.scrollLeft - s.before);
            if (delta === 0) { return 'the strip did not move — try tap_element on an arrow or dot control instead'; }
            return 'slid the strip ' + Math.abs(delta) + 'px — now showing content further ' + (delta > 0 ? 'right' : 'left');
          } catch (e) { return ''; }
        })()
        """#

    /// Reference to the shared ripple so static scripts can embed it.
    private static let rippleFunctionRef = PageScanner.rippleFunction
}
