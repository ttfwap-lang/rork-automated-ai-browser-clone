import Foundation

/// Metadata for an artifact fetched from an optional external plugin. Bytes live
/// in the app's Documents directory; no API key or provider response is encoded
/// in this record.
nonisolated struct PluginArtifactRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let plugin: String
    let operation: String
    let fileName: String
    let mimeType: String
    let byteCount: Int
    let createdAt: Date
}
