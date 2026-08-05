import Foundation

/// Reads what every fillable field on the page is asking for.
///
/// It walks the scanner's own registry, so a probe's number is always the badge
/// number the agent can see. The point of this script is that most of a long form
/// answers the question itself: a well-built field declares its purpose in the
/// `autocomplete` attribute, which is a web standard, and even a badly-built one
/// usually has a label. Both are free to read.
///
/// Password, card and one-time-code fields are flagged and their values are never
/// read — not truncated, not previewed, not returned.
nonisolated enum FieldScripts {

    /// Most fields a form has that this is willing to look at in one pass.
    static let maxFields = 60

    /// Parses the probe payload. Returns nil when the page blocked the script or
    /// the registry was never built.
    static func parse(_ raw: String) -> [FormFieldProbe]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(trimmed.utf8)),
              payload.ok else { return nil }
        return (payload.fields ?? []).map { field in
            FormFieldProbe(
                id: field.i,
                declared: normalizeDeclared(field.ac ?? ""),
                attribute: clean(field.nm ?? ""),
                label: clean(field.lb ?? ""),
                type: (field.tp ?? "").lowercased(),
                widget: FormFieldProbe.Widget(rawValue: field.wd ?? "") ?? .other,
                isRequired: field.rq ?? false,
                isEmpty: field.em ?? true,
                isSensitive: field.sn ?? false,
                options: (field.op ?? []).map { clean($0) }.filter { !$0.isEmpty }
            )
        }
    }

    /// `autocomplete` allows section and mode prefixes — `section-work shipping
    /// address-line1` is a legal way of saying `address-line1`. The meaningful
    /// token is the last one; anything else would never match.
    static func normalizeDeclared(_ raw: String) -> String {
        let lower = raw.lowercased().trimmed
        guard !lower.isEmpty, lower != "off", lower != "on" else { return "" }
        let parts = lower.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let last = parts.last else { return "" }
        return last
    }

    private static func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    nonisolated private struct Payload: Decodable {
        let ok: Bool
        let fields: [FieldPayload]?
    }

    nonisolated private struct FieldPayload: Decodable {
        let i: Int
        let ac: String?
        let nm: String?
        let lb: String?
        let tp: String?
        let wd: String?
        let rq: Bool?
        let em: Bool?
        let sn: Bool?
        let op: [String]?
    }

    // MARK: - The probe script

    static let probeScript = #"""
        (function(){
          try {
            var reg = (window.__rorkAgent && window.__rorkAgent.els) || {};
            var MAX = \#(maxFields);
            var out = [];

            function clean(s) { return (s == null ? '' : String(s)).replace(/\s+/g, ' ').trim().slice(0, 80); }

            // Anything in here is a secret the dossier is not allowed to know.
            var SECRET = /(password|passwd|pwd|cc-|card-?number|cardnum|cvc|cvv|csc|security-?code|one-?time|otp|verification-?code|sort-?code|iban|routing|ssn|social-?security|national-?insurance|tax-?id)/i;

            function widgetOf(el) {
              var tag = (el.tagName || '').toLowerCase();
              var type = (el.type || '').toLowerCase();
              if (tag === 'textarea') { return 'textarea'; }
              if (tag === 'select') { return 'select'; }
              if (el.isContentEditable) { return 'textarea'; }
              if (tag === 'input') {
                if (type === 'checkbox') { return 'checkbox'; }
                if (type === 'radio') { return 'radio'; }
                if (type === 'date' || type === 'datetime-local' || type === 'month' || type === 'week' || type === 'time') { return 'date'; }
                if (type === 'button' || type === 'submit' || type === 'reset' || type === 'image' || type === 'file' || type === 'range' || type === 'color') { return 'other'; }
                return 'text';
              }
              var role = ((el.getAttribute && el.getAttribute('role')) || '').toLowerCase();
              if (role === 'textbox' || role === 'searchbox') { return 'text'; }
              if (role === 'combobox' || role === 'listbox') { return 'select'; }
              if (role === 'checkbox' || role === 'switch') { return 'checkbox'; }
              if (role === 'radio') { return 'radio'; }
              return 'other';
            }

            // The visible words belonging to this field, in the order a person
            // would find them: its own label, then aria, then placeholder, then
            // the text immediately before it.
            function labelOf(el) {
              var n = '';
              try {
                if (el.labels && el.labels.length) {
                  for (var i = 0; i < el.labels.length && !n; i++) { n = clean(el.labels[i].innerText || el.labels[i].textContent); }
                  if (n) { return n; }
                }
              } catch (e) {}
              try {
                var lb = el.getAttribute && el.getAttribute('aria-labelledby');
                if (lb) {
                  var acc = '';
                  var ids = lb.split(/\s+/);
                  for (var j = 0; j < ids.length; j++) {
                    var ref = document.getElementById(ids[j]);
                    if (ref) { acc += ' ' + (ref.innerText || ref.textContent || ''); }
                  }
                  n = clean(acc);
                  if (n) { return n; }
                }
              } catch (e) {}
              n = clean(el.getAttribute && el.getAttribute('aria-label'));
              if (n) { return n; }
              try {
                var wrap = el.closest && el.closest('label');
                if (wrap) { n = clean(wrap.innerText); if (n) { return n; } }
              } catch (e) {}
              n = clean(el.placeholder);
              if (n) { return n; }
              // A field wrapped in its own row often has the question as the row's
              // first line — the last honest place to look.
              try {
                var box = el.closest && el.closest('div,li,fieldset,td');
                if (box) {
                  var text = clean(box.innerText);
                  if (text) { return text.split('\n')[0].slice(0, 60); }
                }
              } catch (e) {}
              return '';
            }

            function optionsOf(el) {
              var list = [];
              try {
                if (el.tagName === 'SELECT' && el.options) {
                  for (var i = 0; i < el.options.length && list.length < 14; i++) {
                    var t = clean(el.options[i].text);
                    if (t) { list.push(t); }
                  }
                }
              } catch (e) {}
              return list;
            }

            var keys = Object.keys(reg);
            for (var k = 0; k < keys.length && out.length < MAX; k++) {
              var num = parseInt(keys[k], 10);
              if (isNaN(num)) { continue; }
              var el = reg[keys[k]];
              if (!el || !el.isConnected) { continue; }

              var widget = widgetOf(el);
              if (widget === 'other') { continue; }

              var type = (el.type || '').toLowerCase();
              var name = clean((el.getAttribute && (el.getAttribute('name') || el.getAttribute('id'))) || '');
              var ac = clean((el.getAttribute && el.getAttribute('autocomplete')) || '');
              var label = labelOf(el);

              var secret = type === 'password' ||
                SECRET.test(name) || SECRET.test(ac) || SECRET.test(label) ||
                (el.getAttribute && SECRET.test(clean(el.getAttribute('data-testid') || '')));

              // A secret field's value is never read. Not previewed, not measured.
              var empty = true;
              if (!secret) {
                try {
                  if (widget === 'select') {
                    var sv = el.value == null ? '' : String(el.value);
                    var si = el.selectedIndex;
                    // A select sitting on its own placeholder counts as empty.
                    empty = !sv.trim() || si <= 0;
                  } else if (el.isContentEditable) {
                    empty = !clean(el.innerText);
                  } else {
                    empty = !String(el.value == null ? '' : el.value).trim();
                  }
                } catch (e) { empty = true; }
              }

              var required = false;
              try {
                required = el.required === true || (el.getAttribute && el.getAttribute('aria-required') === 'true');
                if (!required && label) { required = /\*\s*$|\(required\)/i.test(label); }
              } catch (e) {}

              out.push({
                i: num,
                ac: ac,
                nm: name,
                lb: label,
                tp: type,
                wd: widget,
                rq: required,
                em: empty,
                sn: !!secret,
                op: secret ? [] : optionsOf(el)
              });
            }

            return JSON.stringify({ ok: true, fields: out });
          } catch (err) {
            return JSON.stringify({ ok: false });
          }
        })()
        """#
}
