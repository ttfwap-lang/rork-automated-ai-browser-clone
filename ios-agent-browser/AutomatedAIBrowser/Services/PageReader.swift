import Foundation

/// Builds the cleaned whole-page reading script (Readability-lite): finds the
/// main content, strips navigation/menus/clutter, keeps headings (marked with
/// `#`) and lists (as `•` bullets), and returns up to ~9,000 characters of
/// article-style text covering the ENTIRE page — not just the visible part.
/// Falls back to the raw page text when the reader finds too little.
nonisolated enum PageReader {

    /// Character budget for one reading.
    static let budget = 9_000

    static let readScript = #"""
        (function(){
          try {
            var LIMIT = 9000;
            var title = document.title || '';
            var main = document.querySelector('article') ||
                       document.querySelector('main') ||
                       document.querySelector('[role="main"]') ||
                       document.body;
            if (!main) { return 'extract error: the page has no readable body'; }

            var SKIP_TAGS = { SCRIPT:1, STYLE:1, NOSCRIPT:1, TEMPLATE:1, IFRAME:1, NAV:1, ASIDE:1, BUTTON:1, SELECT:1, OPTION:1, CANVAS:1, VIDEO:1, AUDIO:1, FORM:1, SVG:1 };
            function skippable(el) {
              var tag = el.tagName || '';
              if (SKIP_TAGS[tag]) { return true; }
              var role = (el.getAttribute && el.getAttribute('role')) || '';
              if (role === 'navigation' || role === 'banner' || role === 'contentinfo' || role === 'complementary' || role === 'menu' || role === 'menubar' || role === 'dialog' || role === 'search') { return true; }
              if (el.getAttribute && el.getAttribute('aria-hidden') === 'true') { return true; }
              if (tag === 'FOOTER' || tag === 'HEADER') {
                return !(el.closest && el.closest('article, main, [role="main"]'));
              }
              var cls = '';
              try { cls = ((el.className && el.className.baseVal !== undefined ? el.className.baseVal : el.className) || '') + ' ' + (el.id || ''); } catch (e) {}
              if (/\b(cookie|consent|advert|adsense|promo(?!tion-detail)|newsletter|paywall|breadcrumb|skip-link|sidebar|social-share)\b/i.test(cls)) { return true; }
              return false;
            }

            function clean(s) {
              return (s == null ? '' : String(s)).replace(/[ \t\u00a0]+/g, ' ').replace(/\s*\n\s*/g, '\n').trim();
            }

            var out = [];
            var used = 0;
            function push(text) {
              var t = clean(text);
              if (!t) { return true; }
              out.push(t);
              used += t.length + 1;
              return used < LIMIT + 500;
            }

            var HEADINGS = { H1: '#', H2: '##', H3: '###', H4: '####', H5: '#####', H6: '######' };
            var BLOCKS = { P: 1, PRE: 1, BLOCKQUOTE: 1, TABLE: 1, DL: 1, FIGCAPTION: 1, DD: 1, DT: 1 };
            var STRUCTURAL = 'h1,h2,h3,h4,h5,h6,p,ul,ol,table,article,section,blockquote,pre,dl,nav,aside,footer,header';

            function walk(el, depth) {
              if (used >= LIMIT + 500 || depth > 24) { return false; }
              var kids = el.children;
              if (!kids || kids.length === 0) { return push(el.innerText || ''); }
              for (var i = 0; i < kids.length; i++) {
                var c = kids[i];
                if (skippable(c)) { continue; }
                var tag = c.tagName || '';
                var h = HEADINGS[tag];
                if (h) {
                  if (!push('\n' + h + ' ' + (c.innerText || ''))) { return false; }
                  continue;
                }
                if (tag === 'UL' || tag === 'OL') {
                  var items = c.children;
                  for (var j = 0; j < items.length && j < 60; j++) {
                    if (items[j].tagName !== 'LI') { continue; }
                    if (!push('\u2022 ' + (items[j].innerText || ''))) { return false; }
                  }
                  continue;
                }
                var leaf = false;
                if (BLOCKS[tag]) { leaf = true; }
                else { try { leaf = !c.querySelector(STRUCTURAL); } catch (e) { leaf = true; } }
                if (leaf) {
                  if (!push(c.innerText || '')) { return false; }
                  continue;
                }
                if (!walk(c, depth + 1)) { return false; }
              }
              return true;
            }
            walk(main, 0);

            var joined = out.join('\n').replace(/\n{3,}/g, '\n\n');
            var totalApprox = 0;
            try { totalApprox = clean(main.innerText || '').length; } catch (e) { totalApprox = joined.length; }

            if (clean(joined).length < 200) {
              var raw = clean((title ? title + '\n\n' : '') + (document.body ? document.body.innerText : ''));
              if (raw.length > LIMIT) {
                raw = raw.slice(0, LIMIT) + '\n\u2026(the page continues \u2014 about ' + (raw.length - LIMIT) + ' more characters not shown)';
              }
              return raw || 'extract error: the page has no readable text';
            }

            var full = (title ? title + '\n\n' : '') + joined;
            if (full.length > LIMIT) {
              var more = Math.max(totalApprox - LIMIT, full.length - LIMIT);
              full = full.slice(0, LIMIT) + '\n\u2026(the page continues \u2014 about ' + more + ' more characters not shown)';
            }
            return full;
          } catch (err) { return 'extract error: ' + String((err && err.message) || err); }
        })()
        """#
}
