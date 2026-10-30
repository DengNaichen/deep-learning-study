import Foundation

/// A source describes what was actually acquired, not what the learner intended.
enum ContextSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case notebook
    case replayKitApp

    var id: Self { self }
    var title: String {
        switch self {
        case .notebook: return "笔记内容"
        case .replayKitApp: return "本 App 屏幕 · ReplayKit"
        }
    }
}

struct DocumentContext: Codable, Equatable, Sendable {
    let notebookID: UUID
    let revision: Int
    let coordinateSpace: String
    let page: PageRegion
    let selection: PageRegion?
    let editorMode: String
    let isUsingDrawingTool: Bool
}

struct ContextFrame: Codable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let source: ContextSource
    let image: RequestImage
    // Exact document state is only attached to synchronous PencilKit snapshots.
    // A ReplayKit frame arrives asynchronously; assigning the current revision would be misleading.
    let document: DocumentContext?
    // Only synchronous document images can have an exact journal boundary.
    // Screen frames must keep this nil: receipt time is not a document-state synchronization point.
    let eventCursor: ObservationCursor?

    init(id: UUID, capturedAt: Date, source: ContextSource, image: RequestImage,
         document: DocumentContext?, eventCursor: ObservationCursor? = nil) {
        self.id = id
        self.capturedAt = capturedAt
        self.source = source
        self.image = image
        self.document = document
        self.eventCursor = eventCursor
    }

    func linked(to cursor: ObservationCursor) -> ContextFrame {
        precondition(source == .notebook && document != nil)
        return ContextFrame(id: id, capturedAt: capturedAt, source: source,
                            image: image, document: document, eventCursor: cursor)
    }

    var retainedBase64Bytes: Int { image.base64.utf8.count }
}

struct ContextRetention: Codable, Sendable {
    let maximumFrames: Int
    let maximumBase64Bytes: Int
    let maximumAgeSeconds: TimeInterval

    static let prototype = ContextRetention(
        maximumFrames: PrototypeConfiguration.Context.maximumFrames,
        maximumBase64Bytes: PrototypeConfiguration.Context.maximumBase64Bytes,
        maximumAgeSeconds: PrototypeConfiguration.Context.maximumAgeSeconds
    )
}

/// Bounded in-memory history. The byte budget covers encoded image strings, not total process RAM.
struct ContextHistory {
    let retention: ContextRetention
    private(set) var frames: [ContextFrame] = []
    private(set) var evictedCount = 0
    private(set) var duplicateCount = 0
    private(set) var oversizedCount = 0

    var retainedBase64Bytes: Int { frames.reduce(0) { $0 + $1.retainedBase64Bytes } }

    init(retention: ContextRetention = .prototype) {
        precondition(retention.maximumFrames > 0 && retention.maximumBase64Bytes > 0
                     && retention.maximumAgeSeconds > 0)
        self.retention = retention
    }

    mutating func prune(at now: Date) {
        let cutoff = now.addingTimeInterval(-retention.maximumAgeSeconds)
        let previousCount = frames.count
        frames.removeAll { $0.capturedAt < cutoff }
        evictedCount += previousCount - frames.count
    }

    @discardableResult
    mutating func append(_ frame: ContextFrame, now: Date) -> Bool {
        prune(at: now)
        guard frame.capturedAt >= now.addingTimeInterval(-retention.maximumAgeSeconds) else {
            evictedCount += 1
            return false
        }
        guard frame.retainedBase64Bytes <= retention.maximumBase64Bytes else {
            oversizedCount += 1
            return false
        }
        if let last = frames.last, last.source == frame.source,
           last.image.base64 == frame.image.base64, last.document == frame.document {
            duplicateCount += 1
            return false
        }
        frames.append(frame)
        while frames.count > retention.maximumFrames || retainedBase64Bytes > retention.maximumBase64Bytes {
            frames.removeFirst()
            evictedCount += 1
        }
        return true
    }

    mutating func clear() {
        frames.removeAll()
        evictedCount = 0
        duplicateCount = 0
        oversizedCount = 0
    }
}

/// Provider-independent context: recent observations + an always-fresh document snapshot + question.
/// No interpretation, inferred intent, OCR, agent messages or network API format is included.
struct LearningContext: Codable, Identifiable, Sendable {
    let schemaVersion: Int
    let kind: String
    let id: UUID
    let assembledAt: Date
    let prompt: String
    let samplingIntervalSeconds: TimeInterval
    let retention: ContextRetention
    let evictedFrames: Int
    let skippedDuplicateFrames: Int
    let rejectedOversizedFrames: Int
    let history: [ContextFrame]
    let currentDocument: ContextFrame
    let observations: ObservationLogSnapshot

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
