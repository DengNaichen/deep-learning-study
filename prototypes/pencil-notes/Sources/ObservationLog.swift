import Foundation

/// Observed application transitions, never interpretations of intent or mathematical correctness.
enum ObservationKind: String, Codable, Sendable {
    case captureStarted
    case captureStopped
    case toolUseBegan
    case toolUseEnded
    case toolUseInterrupted
    case drawingChanged
    case selectionChanged
    case editorModeChanged
    case frameRetained
    case contextPrepared

    var title: String {
        switch self {
        case .captureStarted: return "开始观察"
        case .captureStopped: return "停止接收观察"
        case .toolUseBegan: return "开始使用笔迹工具"
        case .toolUseEnded: return "结束使用笔迹工具"
        case .toolUseInterrupted: return "工具使用被中断"
        case .drawingChanged: return "收到笔迹修改回调"
        case .selectionChanged: return "选区改变"
        case .editorModeChanged: return "编辑模式改变"
        case .frameRetained: return "保留图像快照"
        case .contextPrepared: return "用户请求预览上下文"
        }
    }
}

/// Emitted synchronously at the state mutation, rather than from coalesced SwiftUI renders.
struct NotebookObservation {
    let kind: ObservationKind
    let occurredAt: Date
    let document: DocumentContext
}

struct ObservationCursor: Codable, Equatable, Sendable {
    let journalID: UUID
    let throughSequence: Int
}

struct ObservationEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let sequence: Int
    let occurredAt: Date
    let kind: ObservationKind
    let captureID: UUID?
    let source: ContextSource
    let document: DocumentContext?
    let frameID: UUID?
}

/// An immutable view of retained raw entries. Gaps at the beginning are explicit, not hidden.
struct ObservationLogSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let journalID: UUID
    let maximumEntries: Int
    let maximumAgeSeconds: TimeInterval
    let evictedEntries: Int
    let lastSequence: Int
    let entries: [ObservationEntry]

    /// Standalone diagnostic export, not Pi's session file format and not a model prompt.
    /// Header followed by one event per line. No image bytes or question text are included.
    func jsonlData() throws -> Data {
        struct Header: Encodable {
            let type = "observation_log"
            let schemaVersion: Int
            let journalID: UUID
            let maximumEntries: Int
            let maximumAgeSeconds: TimeInterval
            let evictedEntries: Int
            let lastSequence: Int
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let header = Header(schemaVersion: schemaVersion, journalID: journalID,
                            maximumEntries: maximumEntries, maximumAgeSeconds: maximumAgeSeconds,
                            evictedEntries: evictedEntries, lastSequence: lastSequence)
        var data = try encoder.encode(header)
        data.append(contentsOf: "\n".utf8)
        for entry in entries {
            data.append(try encoder.encode(entry))
            data.append(contentsOf: "\n".utf8)
        }
        return data
    }
}

/// Append-only within a bounded in-memory retention window, NOT a durable event-sourced document.
/// Clearing starts a new journal identity. Entries never contain ink geometry or screenshot bytes.
struct ObservationLog {
    private(set) var journalID = UUID()
    private(set) var entries: [ObservationEntry] = []
    private(set) var lastSequence = 0
    private(set) var evictedEntries = 0
    let maximumEntries: Int
    let maximumAgeSeconds: TimeInterval

    init(maximumEntries: Int = PrototypeConfiguration.Context.maximumObservationEntries,
         maximumAgeSeconds: TimeInterval = PrototypeConfiguration.Context.maximumAgeSeconds) {
        precondition(maximumEntries > 0 && maximumAgeSeconds > 0)
        self.maximumEntries = maximumEntries
        self.maximumAgeSeconds = maximumAgeSeconds
    }

    var cursor: ObservationCursor {
        ObservationCursor(journalID: journalID, throughSequence: lastSequence)
    }

    var snapshot: ObservationLogSnapshot {
        ObservationLogSnapshot(schemaVersion: PrototypeConfiguration.Context.observationSchemaVersion,
                               journalID: journalID, maximumEntries: maximumEntries,
                               maximumAgeSeconds: maximumAgeSeconds, evictedEntries: evictedEntries,
                               lastSequence: lastSequence, entries: entries)
    }

    @discardableResult
    mutating func append(kind: ObservationKind, captureID: UUID?, source: ContextSource,
                         document: DocumentContext? = nil, frameID: UUID? = nil,
                         at now: Date = Date()) -> ObservationEntry {
        prune(at: now)
        lastSequence += 1
        let entry = ObservationEntry(id: UUID(), sequence: lastSequence, occurredAt: now,
                                     kind: kind, captureID: captureID, source: source,
                                     document: document, frameID: frameID)
        entries.append(entry)
        if entries.count > maximumEntries {
            let excess = entries.count - maximumEntries
            entries.removeFirst(excess)
            evictedEntries += excess
        }
        return entry
    }

    mutating func prune(at now: Date) {
        let cutoff = now.addingTimeInterval(-maximumAgeSeconds)
        let previousCount = entries.count
        entries.removeAll { $0.occurredAt < cutoff }
        evictedEntries += previousCount - entries.count
    }

    mutating func clear() {
        journalID = UUID()
        entries.removeAll()
        lastSequence = 0
        evictedEntries = 0
    }
}
