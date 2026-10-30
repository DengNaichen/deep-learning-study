import Foundation

/// Pure projection of frozen observations into an inspectable context, independent of capture and UI.
/// Today it includes all retained entries; later policies can select a subset without rewriting the log.
enum ContextAssembler {
    static func assemble(id: UUID, history: ContextHistory, observations: ObservationLogSnapshot,
                         currentDocument: ContextFrame, prompt: String, at now: Date) -> LearningContext {
        LearningContext(
            schemaVersion: PrototypeConfiguration.Context.schemaVersion,
            kind: PrototypeConfiguration.Context.kind, id: id, assembledAt: now,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            samplingIntervalSeconds: PrototypeConfiguration.Context.samplingIntervalSeconds,
            retention: history.retention, evictedFrames: history.evictedCount,
            skippedDuplicateFrames: history.duplicateCount, rejectedOversizedFrames: history.oversizedCount,
            history: history.frames, currentDocument: currentDocument, observations: observations
        )
    }
}
