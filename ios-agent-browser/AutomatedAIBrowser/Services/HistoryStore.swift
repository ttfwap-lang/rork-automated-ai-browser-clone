import UIKit
import Observation

/// Persists finished runs (and small step thumbnails) to the app's Documents directory.
@Observable
final class HistoryStore {
    private(set) var runs: [AgentRun] = []

    private let fileURL: URL
    private let thumbsDirURL: URL
    private let maxRuns = 60

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("agent_runs.json")
        thumbsDirURL = docs.appendingPathComponent("run_thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbsDirURL, withIntermediateDirectories: true)
        load()
    }

    func add(_ run: AgentRun) {
        runs.insert(run, at: 0)
        if runs.count > maxRuns {
            runs.suffix(from: maxRuns).forEach(removeThumbnails)
            runs = Array(runs.prefix(maxRuns))
        }
        save()
    }

    func delete(at offsets: IndexSet) {
        offsets.compactMap { runs.indices.contains($0) ? runs[$0] : nil }.forEach(removeThumbnails)
        for index in offsets.sorted(by: >) where runs.indices.contains(index) {
            runs.remove(at: index)
        }
        save()
    }

    func clearAll() {
        runs.forEach(removeThumbnails)
        runs = []
        save()
    }

    /// Downscales and stores a step snapshot; returns the stored file name.
    func saveThumbnail(_ image: UIImage) -> String? {
        let targetWidth: CGFloat = 260
        let scale = targetWidth / max(image.size.width, 1)
        let size = CGSize(width: targetWidth, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let small = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = small.jpegData(compressionQuality: 0.6) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: thumbsDirURL.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func thumbnail(named name: String) -> UIImage? {
        UIImage(contentsOfFile: thumbsDirURL.appendingPathComponent(name).path)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        runs = (try? JSONDecoder().decode([AgentRun].self, from: data)) ?? []
    }

    private func save() {
        // NOTE: These disk writes are currently synchronous on the main actor
        // (finding LAT-06, scheduled for Stage 2.6). Observe latency here, do not fix it.
        let start = Date()
        let data: Data
        do {
            data = try JSONEncoder().encode(runs)
        } catch {
            AppLog.persistence.error("Failed to encode history runs: error=\(error.localizedDescription, privacy: .private)")
            return
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            let elapsed = Date().timeIntervalSince(start)
            AppLog.persistence.info("Saved runs to disk: count=\(self.runs.count, privacy: .public), elapsed=\(String(format: "%.4fs", elapsed), privacy: .public)")
        } catch {
            AppLog.persistence.error("Failed to write history runs to disk: error=\(error.localizedDescription, privacy: .private)")
        }
    }

    private func removeThumbnails(_ run: AgentRun) {
        for step in run.steps {
            if let file = step.thumbnailFile {
                try? FileManager.default.removeItem(at: thumbsDirURL.appendingPathComponent(file))
            }
        }
    }
}
