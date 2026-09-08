// Why: the EDL JSON document is the versioned contract that lets the decision side and the
// rendering side evolve independently. `schema_version` is checked before anything else is
// decoded; an unknown version is an error, never a guess. See docs/EDL_SCHEMA.md.

import Foundation

public enum EDLDocumentError: Error, Equatable, Sendable {
    case missingSchemaVersion
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case invalidJSON(String)
}

/// Where the transcript came from and how long it was; enough for a renderer to sanity-check bounds.
public struct EDLTranscriptInfo: Codable, Equatable, Sendable {
    public let cueCount: Int
    public let startSec: Double
    public let endSec: Double

    public init(cueCount: Int, startSec: Double, endSec: Double) {
        self.cueCount = cueCount
        self.startSec = startSec
        self.endSec = endSec
    }
}

public struct EDLDocument: Codable, Equatable, Sendable {
    /// Bump per docs/EDL_SCHEMA.md. Decoders refuse anything else.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: String
    public let strategy: SlicingStrategy
    public let clipCountPolicy: ClipCountPolicy
    public let transcript: EDLTranscriptInfo
    public let clips: [EDLClip]
    /// Optional since schema 1 (added without a bump): documents produced before it decode with `nil`.
    public let llm: LLMUsage?

    public init(
        generatedAt: Date, strategy: SlicingStrategy, clipCountPolicy: ClipCountPolicy,
        transcript: EDLTranscriptInfo, clips: [EDLClip], llm: LLMUsage?
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt.ISO8601Format()
        self.strategy = strategy
        self.clipCountPolicy = clipCountPolicy
        self.transcript = transcript
        self.clips = clips
        self.llm = llm
    }

    private init(copying other: EDLDocument, clips: [EDLClip]) {
        schemaVersion = other.schemaVersion
        generatedAt = other.generatedAt
        strategy = other.strategy
        clipCountPolicy = other.clipCountPolicy
        transcript = other.transcript
        self.clips = clips
        llm = other.llm
    }

    /// The same document with clip ids renumbered by `EDLClip.uniqueIDs`. Documents written before
    /// that rule could hold two clips with one id; content is untouched, only the labels change.
    /// Returns `self` unchanged when the ids already follow the rule.
    public func withUniqueClipIDs() throws -> EDLDocument {
        let ids = EDLClip.uniqueIDs(frameworkIDs: clips.map(\.frameworkId))
        guard ids != clips.map(\.id) else { return self }
        return EDLDocument(copying: self, clips: try zip(clips, ids).map { try $0.withID($1) })
    }

    /// Deterministic, diff-friendly JSON (sorted keys, snake_case, pretty printed).
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Decodes an EDL, refusing documents without a `schema_version` or with a version this build does not know.
    public static func decode(_ data: Data) throws -> EDLDocument {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let probe: SchemaVersionProbe
        do {
            probe = try decoder.decode(SchemaVersionProbe.self, from: data)
        } catch let error as DecodingError {
            throw EDLDocumentError.invalidJSON(String(describing: error))
        }
        guard let version = probe.schemaVersion else { throw EDLDocumentError.missingSchemaVersion }
        guard version == currentSchemaVersion else {
            throw EDLDocumentError.unsupportedSchemaVersion(found: version, supported: currentSchemaVersion)
        }
        let document: EDLDocument
        do {
            document = try decoder.decode(EDLDocument.self, from: data)
        } catch let error as DecodingError {
            throw EDLDocumentError.invalidJSON(String(describing: error))
        }
        for clip in document.clips {
            try clip.validateInvariants()
        }
        return document
    }

    private struct SchemaVersionProbe: Decodable {
        let schemaVersion: Int?
    }
}
