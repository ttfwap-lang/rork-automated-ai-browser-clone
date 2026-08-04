import Foundation

/// Builds and parses the in-page element scanner (Set-of-Mark style) plus the
/// element-targeted tap/type scripts.
///
/// The scan script walks the whole DOM (including shadow roots), catalogs every
/// interactive element that a finger could actually press right now (visible,
/// rendered, not covered), numbers them in reading order, registers them on
/// `window.__rorkAgent` for later targeting, and returns a compact JSON payload
/// with element details and page vitals. It self-limits to a ~150 ms budget and
/// ~120 elements so observations stay fast on any page.
nonisolated enum PageScanner {

    // MARK: - Scan

    /// Returns nil when the page blocked the script, the payload is malformed,
    /// or the page isn't ready — callers fall back to pure-vision behavior.
    static func parse(_ raw: String) -> PageObservation? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" else { return nil }
        guard let payload = try? JSONDecoder().decode(ScanPayload.self, from: Data(trimmed.utf8)),
              payload.ok,
              let viewportWidth = payload.vw, viewportWidth > 1,
              let viewportHeight = payload.vh, viewportHeight > 1 else {
            return nil
        }
        let elements: [ScannedElement] = (payload.els ?? []).compactMap { element in
            let rect = element.r ?? []
            guard rect.count == 4 else { return nil }
            return ScannedElement(
                id: element.i,
                kind: ScannedElement.Kind(rawValue: element.k ?? "") ?? .other,
                name: element.n ?? "",
                states: element.s ?? [],
                valuePreview: (element.v?.isEmpty == false) ? element.v : nil,
                isEditable: element.e ?? false,
                x: rect[0],
                y: rect[1],
                width: rect[2],
                height: rect[3]
            )
        }
        return PageObservation(
            elements: elements,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            scrollFraction: min(max(payload.sf ?? 0, 0), 1),
            documentHeightRatio: payload.dh ?? 1,
            elementsAbove: max(payload.ab ?? 0, 0),
            elementsBelow: max(payload.be ?? 0, 0),
            unlistedVisibleCount: max(payload.more ?? 0, 0),
            overlayLikely: payload.ov ?? false,
            isPartial: payload.partial ?? false
        )
    }

    nonisolated private struct ScanPayload: Decodable {
        let ok: Bool
        let vw: Double?
        let vh: Double?
        let sf: Double?
        let dh: Double?
        let ab: Int?
        let be: Int?
        let more: Int?
        let ov: Bool?
        let partial: Bool?
        let els: [ElementPayload]?
        let why: String?
    }

    nonisolated private struct ElementPayload: Decodable {
        let i: Int
        let k: String?
        let n: String?
        let s: [String]?
        let v: String?
        let e: Bool?
        let r: [Double]?
    }

    // MARK: - Action scripts

    /// Tap catalogued element `id` through its true center with the full event
    /// sequence; re-matches by name if the page changed, reports honestly if gone.
    /// `display` is the badge number shown to the AI (differs from `id` for
    /// elements inside embedded panels, which keep their own local numbering).
    static func tapScript(id: Int, display: Int, descriptor: String, expectedName: String) -> String {
        #"""
        (function(){
          \#(rippleFunction)
          \#(findFunction)
          try {
            var id = \#(id);
            var el = __find(id, \#(jsStringLiteral(expectedName)), false);
            if (!el) { return 'element \#(display) is no longer on the page — the page changed; look again before acting'; }
            try { el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' }); } catch (e) { try { el.scrollIntoView(); } catch (e2) {} }
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
            if (el.matches && el.matches('input,textarea,select,[contenteditable="true"],[contenteditable=""]')) { try { el.focus(); } catch (e) {} }
            if (typeof el.click === 'function') { el.click(); } else { el.dispatchEvent(new MouseEvent('click', opts)); }
            var desc = \#(jsStringLiteral(descriptor));
            if (!desc) {
              var tag = (el.tagName || '?').toLowerCase();
              var txt = ((el.innerText || el.value || (el.getAttribute && el.getAttribute('aria-label')) || '') + '').replace(/\s+/g, ' ').trim().slice(0, 40);
              desc = '<' + tag + '>' + (txt ? ' "' + txt + '"' : '');
            }
            var extra = '';
            if (el.type === 'checkbox' || el.type === 'radio') { extra = el.checked ? ' — now checked' : ' — now unchecked'; }
            return 'tapped [\#(display)] ' + desc + extra;
          } catch (e) { return 'tap error: ' + e.message; }
        })()
        """#
    }

    /// Focus catalogued field `id` and type into it in one move (native value
    /// setters so React-style pages register the input), with optional submit.
    static func typeScript(id: Int, display: Int, text: String, submit: Bool, descriptor: String, expectedName: String) -> String {
        #"""
        (function(){
          \#(rippleFunction)
          \#(findFunction)
          try {
            var id = \#(id);
            var t = \#(jsStringLiteral(text));
            var doSubmit = \#(submit ? "true" : "false");
            var el = __find(id, \#(jsStringLiteral(expectedName)), true);
            if (!el) { return 'element \#(display) is no longer on the page — the page changed; look again before acting'; }
            var desc = \#(jsStringLiteral(descriptor));
            if (!desc) {
              var txt = (((el.getAttribute && el.getAttribute('aria-label')) || el.placeholder || '') + '').replace(/\s+/g, ' ').trim().slice(0, 40);
              desc = 'field' + (txt ? ' "' + txt + '"' : '');
            }
            try { el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' }); } catch (e) {}
            var r = el.getBoundingClientRect();
            __ripple(
              Math.max(1, Math.min(window.innerWidth - 1, r.left + r.width / 2)),
              Math.max(1, Math.min(window.innerHeight - 1, r.top + r.height / 2))
            );
            try { el.focus(); } catch (e) {}
            if (el.isContentEditable) {
              try { var sel = window.getSelection(); sel.selectAllChildren(el); } catch (e) {}
              document.execCommand('insertText', false, t);
            } else if (('value' in el) && el.tagName !== 'SELECT') {
              var proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
              var d = Object.getOwnPropertyDescriptor(proto, 'value');
              if (d && d.set) { d.set.call(el, t); } else { el.value = t; }
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            } else {
              return 'element \#(display) (' + desc + ') is not a typeable field';
            }
            if (doSubmit) {
              var ke = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
              el.dispatchEvent(new KeyboardEvent('keydown', ke));
              el.dispatchEvent(new KeyboardEvent('keypress', ke));
              el.dispatchEvent(new KeyboardEvent('keyup', ke));
              if (el.form) { if (el.form.requestSubmit) { el.form.requestSubmit(); } else { el.form.submit(); } }
            }
            return 'typed "' + t.slice(0, 40) + '" into [\#(display)] ' + desc + (doSubmit ? ' — submitted' : '');
          } catch (e) { return 'type error: ' + e.message; }
        })()
        """#
    }

    /// Reads back what a field actually holds after typing — the honest evidence
    /// that typing landed, since setting a value mutates no DOM node. Returns the
    /// sentinel `__rork_gone__` when the field has left the page.
    static let missingFieldSentinel = "__rork_gone__"

    static func fieldValueScript(id: Int, expectedName: String) -> String {
        #"""
        (function(){
          \#(findFunction)
          try {
            var el = __find(\#(id), \#(jsStringLiteral(expectedName)), true);
            if (!el) { return '\#(missingFieldSentinel)'; }
            if (el.isContentEditable) { return String(el.innerText || '').slice(0, 120); }
            if ('value' in el) { return String(el.value == null ? '' : el.value).slice(0, 120); }
            return '\#(missingFieldSentinel)';
          } catch (e) { return '\#(missingFieldSentinel)'; }
        })()
        """#
    }

    // MARK: - Shared JS helpers

    /// Cyan tap ripple, shared by all pointer-style actions (also embedded by
    /// FormScripts and GestureScripts).
    static let rippleFunction = #"""
        function __ripple(x, y) {
            try {
              if (!document.getElementById('__agent_css')) {
                var st = document.createElement('style'); st.id = '__agent_css';
                st.textContent = '@keyframes __agentPulse{0%{transform:translate(-50%,-50%) scale(.4);opacity:.95}100%{transform:translate(-50%,-50%) scale(2.6);opacity:0}} .__agent_ripple{position:fixed;width:44px;height:44px;border-radius:50%;border:2px solid #00E5FF;background:rgba(0,229,255,.25);box-shadow:0 0 18px #00E5FF;pointer-events:none;z-index:2147483647;animation:__agentPulse .7s ease-out forwards}';
                document.head.appendChild(st);
              }
              var rp = document.createElement('div'); rp.className = '__agent_ripple';
              rp.style.left = x + 'px'; rp.style.top = y + 'px';
              document.body.appendChild(rp);
              setTimeout(function(){ rp.remove(); }, 750);
            } catch (e) {}
        }
        """#

    /// Registry lookup with stale-element recovery: exact registry hit first,
    /// then a name re-match across interactive elements (fields only when typing).
    /// Shared with FormScripts and GestureScripts.
    static let findFunction = #"""
        function __find(id, wantName, fieldsOnly) {
            var reg = (window.__rorkAgent && window.__rorkAgent.els) || {};
            var el = reg[id];
            if (el && el.isConnected) { return el; }
            var want = (wantName || '').replace(/\s+/g, ' ').trim().toLowerCase();
            if (!want) { return null; }
            var sel = fieldsOnly
              ? 'input,textarea,[contenteditable="true"],[contenteditable=""],[role="textbox"],[role="searchbox"]'
              : 'a[href],button,input,select,textarea,summary,[role="button"],[role="link"],[role="checkbox"],[role="radio"],[role="switch"],[role="tab"],[role="menuitem"],[role="option"],[role="combobox"],[onclick],[contenteditable="true"],[contenteditable=""]';
            var all;
            try { all = document.querySelectorAll(sel); } catch (e) { return null; }
            var best = null;
            for (var i = 0; i < all.length; i++) {
              var c = all[i];
              var r = c.getBoundingClientRect();
              if (r.width < 2 || r.height < 2) { continue; }
              var t = (((c.getAttribute && c.getAttribute('aria-label')) || '') + ' ' + (c.placeholder || '') + ' ' + (c.innerText || c.value || '')).replace(/\s+/g, ' ').trim().toLowerCase();
              if (!t) { continue; }
              if (t === want) { return c; }
              if (!best && (t.indexOf(want) !== -1 || want.indexOf(t) !== -1)) { best = c; }
            }
            return best;
        }
        """#

    /// Escapes a Swift string into a safe JS string literal.
    static func jsStringLiteral(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x2028 || scalar.value == 0x2029 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    // MARK: - Embedded panels

    /// Lists visible embedded panels (iframes) in the main document with their
    /// viewport rects, so panel scans can be positioned and routed.
    static let iframeListScript = #"""
        (function(){
          try {
            var out = [];
            var vw = window.innerWidth || 0, vh = window.innerHeight || 0;
            var frames = document.querySelectorAll('iframe');
            for (var i = 0; i < frames.length && out.length < 6; i++) {
              var f = frames[i];
              var r;
              try { r = f.getBoundingClientRect(); } catch (e) { continue; }
              if (r.width < 80 || r.height < 60) { continue; }
              if (r.bottom <= 0 || r.top >= vh || r.right <= 0 || r.left >= vw) { continue; }
              var cs;
              try { cs = getComputedStyle(f); } catch (e) { continue; }
              if (cs.display === 'none' || cs.visibility === 'hidden') { continue; }
              out.push({ src: String(f.src || ''), x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) });
            }
            return JSON.stringify(out);
          } catch (e) { return '[]'; }
        })()
        """#

    // MARK: - The scan script

    /// Walks the DOM, filters to genuinely pressable elements, numbers them,
    /// registers them for targeting, and returns JSON with elements + vitals.
    static let scanScript = #"""
        (function(){
          try {
            var t0 = Date.now();
            var BUDGET = 150;
            var MAX = 120;
            var LOOP_MAX = 800;
            var vw = window.innerWidth || 0, vh = window.innerHeight || 0;
            if (!document.body || vw < 2 || vh < 2) { return JSON.stringify({ ok: false, why: 'page not ready' }); }

            var SEL = 'a[href],button,input,select,textarea,summary,' +
              '[role="button"],[role="link"],[role="checkbox"],[role="radio"],[role="switch"],[role="tab"],' +
              '[role="menuitem"],[role="menuitemcheckbox"],[role="menuitemradio"],[role="option"],[role="combobox"],' +
              '[role="listbox"],[role="slider"],[role="textbox"],[role="searchbox"],[role="spinbutton"],' +
              '[onclick],[contenteditable="true"],[contenteditable=""]';

            var timedOut = false;
            function over() {
              if (timedOut) { return true; }
              if (Date.now() - t0 > BUDGET) { timedOut = true; return true; }
              return false;
            }

            try {
              var old = document.querySelectorAll('[data-rork-agent]');
              for (var oi = 0; oi < old.length; oi++) { old[oi].removeAttribute('data-rork-agent'); }
            } catch (e) {}

            var cands = [];
            function walk(root) {
              if (over()) { return; }
              var all;
              try { all = root.querySelectorAll('*'); } catch (e) { return; }
              for (var i = 0; i < all.length; i++) {
                if ((i & 255) === 0 && over()) { return; }
                var el = all[i];
                if (el.shadowRoot) { walk(el.shadowRoot); }
                var take = false;
                try { take = el.matches(SEL); } catch (e) {}
                if (!take) {
                  var tg = el.tagName;
                  if (tg !== 'HTML' && tg !== 'BODY') {
                    try {
                      var rr = el.getBoundingClientRect();
                      if (rr.width >= 12 && rr.height >= 12 && rr.bottom > 0 && rr.top < vh && rr.right > 0 && rr.left < vw &&
                          rr.width * rr.height < vw * vh * 0.7) {
                        var cs = getComputedStyle(el);
                        if (cs.cursor === 'pointer') {
                          var par = el.parentElement;
                          var parPointer = false;
                          if (par && par.tagName !== 'BODY' && par.tagName !== 'HTML') {
                            try { parPointer = getComputedStyle(par).cursor === 'pointer'; } catch (e) {}
                          }
                          if (!parPointer && !(el.closest && el.closest(SEL))) { take = true; }
                        }
                      }
                    } catch (e) {}
                  }
                }
                if (take) { cands.push(el); }
              }
            }
            walk(document);

            function kindOf(el) {
              var tag = (el.tagName || '').toLowerCase();
              var role = ((el.getAttribute && el.getAttribute('role')) || '').toLowerCase();
              var type = (el.type || '').toLowerCase();
              if (tag === 'textarea') { return 'field'; }
              if (el.isContentEditable) { return 'field'; }
              if (tag === 'input') {
                if (type === 'checkbox' || type === 'radio') { return 'toggle'; }
                if (type === 'button' || type === 'submit' || type === 'reset' || type === 'image') { return 'button'; }
                if (type === 'range') { return 'other'; }
                return 'field';
              }
              if (tag === 'select') { return 'dropdown'; }
              if (role === 'switch' || role === 'checkbox' || role === 'radio') { return 'toggle'; }
              if (role === 'textbox' || role === 'searchbox' || role === 'spinbutton') { return 'field'; }
              if (role === 'combobox' || role === 'listbox') { return 'dropdown'; }
              if (tag === 'button' || tag === 'summary' || role === 'button' || role === 'tab' ||
                  role === 'menuitem' || role === 'menuitemcheckbox' || role === 'menuitemradio' || role === 'option') { return 'button'; }
              if (tag === 'a' || role === 'link') { return 'link'; }
              return 'other';
            }

            function clean(s) { return (s == null ? '' : String(s)).replace(/\s+/g, ' ').trim().slice(0, 60); }

            function nameOf(el, kind) {
              var n = clean(el.getAttribute && el.getAttribute('aria-label'));
              if (n) { return n; }
              try {
                var lb = el.getAttribute && el.getAttribute('aria-labelledby');
                if (lb) {
                  var acc = '';
                  var ids = lb.split(/\s+/);
                  for (var i = 0; i < ids.length; i++) {
                    var ref = document.getElementById(ids[i]);
                    if (ref) { acc += ' ' + (ref.innerText || ref.textContent || ''); }
                  }
                  n = clean(acc);
                  if (n) { return n; }
                }
              } catch (e) {}
              n = clean(el.placeholder);
              if (n) { return n; }
              try {
                if (el.labels && el.labels.length) { n = clean(el.labels[0].innerText); if (n) { return n; } }
                var wrap = el.closest && el.closest('label');
                if (wrap) { n = clean(wrap.innerText); if (n) { return n; } }
              } catch (e) {}
              var tag = (el.tagName || '').toLowerCase();
              var type = (el.type || '').toLowerCase();
              if (tag === 'input' && (type === 'submit' || type === 'button' || type === 'reset')) {
                n = clean(el.value); if (n) { return n; }
              }
              if (tag === 'select') {
                try { var opt = el.options && el.options[el.selectedIndex]; n = clean(opt && opt.text); if (n) { return n; } } catch (e) {}
              }
              if (kind !== 'field') { n = clean(el.innerText || el.textContent); if (n) { return n; } }
              try {
                var img = el.querySelector && el.querySelector('img[alt]');
                if (img) { n = clean(img.getAttribute('alt')); if (n) { return n; } }
              } catch (e) {}
              n = clean(el.getAttribute && el.getAttribute('title'));
              if (n) { return n; }
              n = clean(el.getAttribute && el.getAttribute('name'));
              if (n) { return n; }
              return '';
            }

            function statesOf(el, kind) {
              var s = [];
              try {
                if (el.disabled === true || (el.getAttribute && el.getAttribute('aria-disabled') === 'true')) { s.push('disabled'); }
                if (kind === 'toggle') {
                  var checked = (typeof el.checked === 'boolean') ? el.checked : ((el.getAttribute && el.getAttribute('aria-checked')) === 'true');
                  s.push(checked ? 'checked' : 'unchecked');
                }
                if (el.getAttribute) {
                  if (el.getAttribute('aria-expanded') === 'true') { s.push('expanded'); }
                  if (el.getAttribute('aria-selected') === 'true') { s.push('selected'); }
                  if (el.required === true || el.getAttribute('aria-required') === 'true') { s.push('required'); }
                }
                var ae = document.activeElement;
                if (ae && (ae === el || (el.contains && el.contains(ae)))) { s.push('focused'); }
                if (kind === 'field') {
                  var v = '';
                  if (typeof el.value === 'string') { v = el.value; }
                  else if (el.isContentEditable) { v = el.innerText || ''; }
                  s.push(v && v.trim() ? 'filled' : 'empty');
                }
              } catch (e) {}
              return s;
            }

            function valueOf(el, kind) {
              if (kind !== 'field') { return ''; }
              try {
                if ((el.type || '').toLowerCase() === 'password') { return ''; }
                var v = (typeof el.value === 'string') ? el.value : (el.isContentEditable ? (el.innerText || '') : '');
                return clean(v).slice(0, 30);
              } catch (e) { return ''; }
            }

            function overlapRatio(ra, rb) {
              var w = Math.min(ra.right, rb.right) - Math.max(ra.left, rb.left);
              var h = Math.min(ra.bottom, rb.bottom) - Math.max(ra.top, rb.top);
              if (w <= 0 || h <= 0) { return 0; }
              var areaA = ra.width * ra.height;
              return areaA > 0 ? (w * h) / areaA : 0;
            }

            var above = 0, below = 0;
            var vis = [];
            for (var ci = 0; ci < cands.length && ci < LOOP_MAX; ci++) {
              var cel = cands[ci];
              var r;
              try { r = cel.getBoundingClientRect(); } catch (e) { continue; }
              if (r.width < 6 || r.height < 6) { continue; }
              if (r.bottom <= 0) { above++; continue; }
              if (r.top >= vh) { below++; continue; }
              if (r.right <= 0 || r.left >= vw) { continue; }
              var visW = Math.min(r.right, vw) - Math.max(r.left, 0);
              var visH = Math.min(r.bottom, vh) - Math.max(r.top, 0);
              if (visW <= 0 || visH <= 0) { continue; }
              if (visW * visH < 0.5 * r.width * r.height) {
                if (r.top >= vh / 2) { below++; } else { above++; }
                continue;
              }
              var cs2;
              try { cs2 = getComputedStyle(cel); } catch (e) { continue; }
              if (cs2.visibility === 'hidden' || cs2.display === 'none') { continue; }
              if (parseFloat(cs2.opacity || '1') < 0.05) { continue; }
              if (cel.closest && cel.closest('[aria-hidden="true"]')) { continue; }
              if (!over()) {
                var cx = Math.max(1, Math.min(vw - 1, (Math.max(r.left, 0) + Math.min(r.right, vw)) / 2));
                var cy = Math.max(1, Math.min(vh - 1, (Math.max(r.top, 0) + Math.min(r.bottom, vh)) / 2));
                var hit = null;
                try {
                  var rn = cel.getRootNode ? cel.getRootNode() : document;
                  hit = (rn && rn.elementFromPoint) ? rn.elementFromPoint(cx, cy) : document.elementFromPoint(cx, cy);
                } catch (e) {}
                if (hit && hit !== cel && !(cel.contains && cel.contains(hit)) && !(hit.contains && hit.contains(cel)) &&
                    !(hit.shadowRoot && hit.shadowRoot.contains && hit.shadowRoot.contains(cel))) {
                  continue;
                }
              }
              vis.push({ el: cel, r: r, k: kindOf(cel) });
            }

            vis.sort(function(a, b) { return (a.r.top - b.r.top) || (a.r.left - b.r.left); });

            var moreVisible = 0;
            if (vis.length > 200) { moreVisible += vis.length - 200; vis = vis.slice(0, 200); }

            var kept = [];
            for (var i2 = 0; i2 < vis.length; i2++) {
              var a = vis[i2], drop = false;
              for (var j = 0; j < vis.length && !drop; j++) {
                if (i2 === j) { continue; }
                var b = vis[j];
                var bContainsA = false, aContainsB = false;
                try { bContainsA = b.el.contains(a.el); aContainsB = a.el.contains(b.el); } catch (e) {}
                if (bContainsA) {
                  if (a.k === b.k || a.k === 'other') { drop = true; }
                } else if (aContainsB) {
                  if (a.k === 'other' && b.k !== 'other') { drop = true; }
                  else if (a.k !== b.k && b.k !== 'other' && overlapRatio(a.r, b.r) > 0.85) { drop = true; }
                }
              }
              if (!drop) { kept.push(a); }
            }

            if (kept.length > MAX) { moreVisible += kept.length - MAX; kept = kept.slice(0, MAX); }

            window.__rorkAgent = { els: {} };
            var els = [];
            for (var n2 = 0; n2 < kept.length; n2++) {
              var it = kept[n2], num = n2 + 1;
              window.__rorkAgent.els[num] = it.el;
              try { it.el.setAttribute('data-rork-agent', String(num)); } catch (e) {}
              els.push({
                i: num,
                k: it.k,
                n: nameOf(it.el, it.k),
                s: statesOf(it.el, it.k),
                v: valueOf(it.el, it.k),
                e: it.k === 'field',
                r: [Math.round(it.r.left), Math.round(it.r.top), Math.round(it.r.width), Math.round(it.r.height)]
              });
            }

            var doc = document.documentElement;
            var scrollH = Math.max(doc ? doc.scrollHeight : 0, document.body ? document.body.scrollHeight : 0, vh);
            var sf = scrollH > vh + 2 ? Math.max(0, Math.min(1, window.scrollY / (scrollH - vh))) : 0;
            var dh = scrollH / vh;

            var overlay = false;
            try {
              var dlgs = document.querySelectorAll('dialog[open],[role="dialog"],[role="alertdialog"],[aria-modal="true"]');
              for (var di = 0; di < dlgs.length; di++) {
                var drr = dlgs[di].getBoundingClientRect();
                var dcs = getComputedStyle(dlgs[di]);
                if (dcs.display !== 'none' && dcs.visibility !== 'hidden' && drr.width * drr.height > vw * vh * 0.15) { overlay = true; break; }
              }
              if (!overlay) {
                var mid = document.elementFromPoint(vw / 2, vh / 2);
                var node = mid;
                var hops = 0;
                while (node && node !== document.body && hops < 12) {
                  var ncs = getComputedStyle(node);
                  var z = parseInt(ncs.zIndex, 10);
                  if (ncs.position === 'fixed' && !isNaN(z) && z > 10) {
                    var nr = node.getBoundingClientRect();
                    if (nr.width * nr.height > vw * vh * 0.5) { overlay = true; }
                    break;
                  }
                  node = node.parentElement;
                  hops++;
                }
              }
            } catch (e) {}

            return JSON.stringify({
              ok: true, vw: vw, vh: vh, sf: sf, dh: dh, ab: above, be: below,
              more: moreVisible, ov: overlay, partial: timedOut, els: els
            });
          } catch (err) {
            return JSON.stringify({ ok: false, why: String((err && err.message) || err) });
          }
        })()
        """#
}
