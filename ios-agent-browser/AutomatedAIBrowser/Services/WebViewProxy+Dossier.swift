import WebKit

/// Pair 7's dossier hands: read what a form is asking for, then write the matched
/// facts into it.
///
/// Values arrive here from the dossier and go straight into the page. They are
/// never returned, never logged and never put into a result line — the honest
/// report talks about field names and counts only.
extension WebViewProxy {

    /// Reads every fillable field on the page, using the badge numbers the agent
    /// can already see. Empty when the page blocked the script or the scan never
    /// ran.
    func probeFormFields() async -> [FormFieldProbe] {
        let raw = await runJS(FieldScripts.probeScript)
        guard let probes = FieldScripts.parse(raw) else { return [] }
        return probes
    }

    /// One matched field and the value about to go into it.
    nonisolated struct DossierEntry {
        let id: Int
        let value: String
        let expectedName: String
        let isSelect: Bool
    }

    /// The honest outcome of a fill: how many landed, and which did not.
    nonisolated struct FillOutcome {
        let filled: Int
        /// Field descriptors that did not take the value, with the page's reason.
        let failures: [String]
    }

    /// Writes the matched facts into the page. Dropdowns are set by option text,
    /// everything else is typed with the same reliable path as `type_into`
    /// (native setters, so framework-driven forms notice).
    ///
    /// Submitting is a separate decision and is only ever done on the last field.
    func fillFromDossier(_ entries: [DossierEntry], submit: Bool) async -> FillOutcome {
        guard !entries.isEmpty else { return FillOutcome(filled: 0, failures: []) }

        var filled = 0
        var failures: [String] = []

        for (index, entry) in entries.enumerated() {
            let route = panelRoutes[entry.id]
            let isLast = index == entries.count - 1

            let raw: String
            if entry.isSelect {
                raw = await runJS(
                    FormScripts.selectScript(
                        id: route?.localID ?? entry.id,
                        display: entry.id,
                        option: entry.value,
                        expectedName: entry.expectedName
                    ),
                    in: route?.frame
                )
            } else {
                raw = await runJS(
                    PageScanner.typeScript(
                        id: route?.localID ?? entry.id,
                        display: entry.id,
                        text: entry.value,
                        submit: submit && isLast,
                        descriptor: "",
                        expectedName: entry.expectedName
                    ),
                    in: route?.frame
                )
            }

            if raw.hasPrefix("typed") || raw.hasPrefix("selected") {
                filled += 1
            } else {
                // The page's own words, but never the value we tried to write.
                failures.append("[\(entry.id)]: \(String(raw.prefix(90)))")
            }
            try? await Task.sleep(for: .milliseconds(200))
        }

        return FillOutcome(filled: filled, failures: failures)
    }
}
