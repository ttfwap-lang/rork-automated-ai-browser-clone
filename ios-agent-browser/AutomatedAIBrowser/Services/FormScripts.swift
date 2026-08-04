import Foundation

/// JS builders for the precision form hands: choose a dropdown option, set a
/// toggle state-aware, and set a slider to a target percent. All target the
/// numbered elements from Pair 1's registry, with stale re-matching and honest
/// failure messages. `display` is the badge number shown to the AI (it can
/// differ from the lookup id for elements inside embedded panels).
nonisolated enum FormScripts {

    /// Real `<select>` menus are set natively (with framework-visible events);
    /// custom dropdowns are opened so their options appear on the next look.
    static func selectScript(id: Int, display: Int, option: String, expectedName: String) -> String {
        #"""
        (function(){
          \#(PageScanner.rippleFunction)
          \#(PageScanner.findFunction)
          try {
            var el = __find(\#(id), \#(PageScanner.jsStringLiteral(expectedName)), false);
            if (!el) { return 'element \#(display) is no longer on the page — the page changed; look again before acting'; }
            var want = \#(PageScanner.jsStringLiteral(option));
            var wantLow = want.replace(/\s+/g, ' ').trim().toLowerCase();
            try { el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' }); } catch (e) {}
            var r = el.getBoundingClientRect();
            var cx = Math.max(1, Math.min(window.innerWidth - 1, r.left + r.width / 2));
            var cy = Math.max(1, Math.min(window.innerHeight - 1, r.top + r.height / 2));
            __ripple(cx, cy);
            if (el.tagName === 'SELECT') {
              var exact = -1, partial = -1, texts = [];
              for (var i = 0; i < el.options.length; i++) {
                var ot = (el.options[i].text || '').replace(/\s+/g, ' ').trim();
                var ov = (el.options[i].value || '').replace(/\s+/g, ' ').trim();
                if (texts.length < 10 && ot) { texts.push('"' + ot.slice(0, 24) + '"'); }
                var otl = ot.toLowerCase(), ovl = ov.toLowerCase();
                if (otl === wantLow || ovl === wantLow) { exact = i; break; }
                if (partial < 0 && otl && wantLow && (otl.indexOf(wantLow) !== -1 || wantLow.indexOf(otl) !== -1)) { partial = i; }
              }
              var idx = exact >= 0 ? exact : partial;
              if (idx < 0) { return 'no option matching "' + want.slice(0, 30) + '" in [\#(display)] — available: ' + texts.join(', '); }
              var d = Object.getOwnPropertyDescriptor(window.HTMLSelectElement.prototype, 'value');
              if (d && d.set) { d.set.call(el, el.options[idx].value); } else { el.selectedIndex = idx; }
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
              return 'selected "' + (el.options[idx].text || '').replace(/\s+/g, ' ').trim().slice(0, 40) + '" in [\#(display)]';
            }
            var opts = { bubbles: true, cancelable: true, view: window, clientX: cx, clientY: cy };
            try {
              el.dispatchEvent(new PointerEvent('pointerdown', opts));
              el.dispatchEvent(new MouseEvent('mousedown', opts));
              el.dispatchEvent(new PointerEvent('pointerup', opts));
              el.dispatchEvent(new MouseEvent('mouseup', opts));
            } catch (e) {}
            if (typeof el.click === 'function') { el.click(); } else { el.dispatchEvent(new MouseEvent('click', opts)); }
            return 'opened [\#(display)] — a custom dropdown; its options should appear as numbered elements on the next look, then tap the one you want';
          } catch (e) { return 'select error: ' + e.message; }
        })()
        """#
    }

    /// State-aware toggle: checks the current state first, only presses when
    /// needed, and reports the state after pressing — honestly.
    static func toggleScript(id: Int, display: Int, on: Bool, expectedName: String) -> String {
        #"""
        (function(){
          \#(PageScanner.rippleFunction)
          \#(PageScanner.findFunction)
          try {
            var el = __find(\#(id), \#(PageScanner.jsStringLiteral(expectedName)), false);
            if (!el) { return 'element \#(display) is no longer on the page — the page changed; look again before acting'; }
            var want = \#(on ? "true" : "false");
            function state(t) {
              if (typeof t.checked === 'boolean') { return t.checked; }
              if (!t.getAttribute) { return null; }
              var a = t.getAttribute('aria-checked');
              if (a === 'true') { return true; }
              if (a === 'false') { return false; }
              var p = t.getAttribute('aria-pressed');
              if (p === 'true') { return true; }
              if (p === 'false') { return false; }
              return null;
            }
            var before = state(el);
            if (before === want) { return '[\#(display)] is already ' + (want ? 'ON' : 'OFF') + ' — no action taken'; }
            try { el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' }); } catch (e) {}
            var r = el.getBoundingClientRect();
            var x = Math.max(1, Math.min(window.innerWidth - 1, r.left + r.width / 2));
            var y = Math.max(1, Math.min(window.innerHeight - 1, r.top + r.height / 2));
            __ripple(x, y);
            var opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
            try {
              el.dispatchEvent(new PointerEvent('pointerdown', opts));
              el.dispatchEvent(new MouseEvent('mousedown', opts));
              el.dispatchEvent(new PointerEvent('pointerup', opts));
              el.dispatchEvent(new MouseEvent('mouseup', opts));
            } catch (e) {}
            if (typeof el.click === 'function') { el.click(); } else { el.dispatchEvent(new MouseEvent('click', opts)); }
            var after = state(el);
            if (after === want) { return 'set [\#(display)] to ' + (want ? 'ON' : 'OFF'); }
            if (after === before && before !== null) { return 'pressed [\#(display)] but its state did not change (still ' + (before ? 'ON' : 'OFF') + ') — the site may use a custom control; look again'; }
            return 'pressed [\#(display)] — state now unclear (custom control); check the next look';
          } catch (e) { return 'toggle error: ' + e.message; }
        })()
        """#
    }

    /// Standard sliders are set directly (percent of range, step-aligned);
    /// custom ARIA sliders are nudged with keyboard arrows toward the target.
    static func sliderScript(id: Int, display: Int, percent: Double, expectedName: String) -> String {
        let clamped = min(max(percent, 0), 100)
        return #"""
        (function(){
          \#(PageScanner.rippleFunction)
          \#(PageScanner.findFunction)
          try {
            var p = \#(String(format: "%.1f", clamped));
            var el = __find(\#(id), \#(PageScanner.jsStringLiteral(expectedName)), false);
            if (!el) { return 'element \#(display) is no longer on the page — the page changed; look again before acting'; }
            var isRange = el.tagName === 'INPUT' && (el.type || '').toLowerCase() === 'range';
            var isAria = el.getAttribute && (el.getAttribute('role') === 'slider' || el.getAttribute('aria-valuenow') != null);
            if (!isRange && !isAria && el.querySelector) {
              var inner = el.querySelector('input[type="range"],[role="slider"]');
              if (inner) {
                el = inner;
                isRange = el.tagName === 'INPUT' && (el.type || '').toLowerCase() === 'range';
                isAria = !isRange;
              }
            }
            try { el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' }); } catch (e) {}
            var r = el.getBoundingClientRect();
            __ripple(
              Math.max(1, Math.min(window.innerWidth - 1, r.left + r.width / 2)),
              Math.max(1, Math.min(window.innerHeight - 1, r.top + r.height / 2))
            );
            if (isRange) {
              var min = parseFloat(el.min !== '' ? el.min : '0');
              var max = parseFloat(el.max !== '' ? el.max : '100');
              if (!(max > min)) { min = 0; max = 100; }
              var step = parseFloat(el.step !== '' ? el.step : '1');
              if (!(step > 0)) { step = 1; }
              var target = min + (max - min) * p / 100;
              target = Math.round((target - min) / step) * step + min;
              target = Math.max(min, Math.min(max, target));
              var d = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
              if (d && d.set) { d.set.call(el, String(target)); } else { el.value = String(target); }
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
              return 'set slider [\#(display)] to ' + el.value + ' (' + Math.round(p) + '% of ' + min + '\u2013' + max + ')';
            }
            if (isAria) {
              var vmin = parseFloat(el.getAttribute('aria-valuemin') || '0');
              var vmax = parseFloat(el.getAttribute('aria-valuemax') || '100');
              if (!(vmax > vmin)) { vmin = 0; vmax = 100; }
              var goal = vmin + (vmax - vmin) * p / 100;
              try { el.focus(); } catch (e) {}
              var tol = (vmax - vmin) * 0.02 + 1e-6;
              var moved = false;
              for (var i = 0; i < 60; i++) {
                var now = parseFloat(el.getAttribute('aria-valuenow') || 'NaN');
                if (isNaN(now)) { break; }
                var diff = goal - now;
                if (Math.abs(diff) <= tol) { break; }
                var key = diff > 0 ? 'ArrowRight' : 'ArrowLeft';
                var kd = { key: key, code: key, bubbles: true, cancelable: true };
                el.dispatchEvent(new KeyboardEvent('keydown', kd));
                el.dispatchEvent(new KeyboardEvent('keyup', kd));
                var next = parseFloat(el.getAttribute('aria-valuenow') || 'NaN');
                if (next === now || isNaN(next)) { break; }
                moved = true;
              }
              var finalNow = el.getAttribute('aria-valuenow');
              if (finalNow != null && moved) { return 'nudged slider [\#(display)] to ' + finalNow + ' (target was ' + Math.round(p) + '%)'; }
              if (finalNow != null) { return 'slider [\#(display)] did not respond to keyboard nudges (still at ' + finalNow + ') — try drag instead'; }
              return 'slider [\#(display)] reports no value — try drag instead';
            }
            return '[\#(display)] is not a recognizable slider — try drag or tap_element';
          } catch (e) { return 'slider error: ' + e.message; }
        })()
        """#
    }
}
