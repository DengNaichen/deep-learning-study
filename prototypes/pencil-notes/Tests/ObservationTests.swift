import Combine
import PencilKit
import XCTest
@testable import PencilNotes

final class ObservationLogTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 2_000)
    private let entryLimit = 3
    private let ageLimit: TimeInterval = 10

    func testAppendOrderDoesNotDependOnWallClockOrder() {
        var log = ObservationLog()
        let capture = UUID()
        let first = log.append(kind: .captureStarted, captureID: capture, source: .notebook, at: epoch)
        let second = log.append(kind: .drawingChanged, captureID: capture, source: .notebook,
                                at: epoch.addingTimeInterval(-1))
        XCTAssertEqual(log.entries.map(\.sequence), [1, 2])
        XCTAssertEqual(log.entries.first?.id, first.id)
        XCTAssertEqual(log.entries.last?.id, second.id)
        XCTAssertEqual(log.cursor.throughSequence, second.sequence)
    }

    func testCountEvictionKeepsOriginalIDsAndSequenceNumbers() {
        var log = ObservationLog(maximumEntries: entryLimit, maximumAgeSeconds: ageLimit)
        let original = log.append(kind: .drawingChanged, captureID: nil, source: .notebook, at: epoch)
        for _ in 0..<entryLimit {
            log.append(kind: .drawingChanged, captureID: nil, source: .notebook, at: epoch)
        }
        XCTAssertEqual(log.entries.count, entryLimit)
        XCTAssertEqual(log.evictedEntries, 1)
        XCTAssertFalse(log.entries.contains { $0.id == original.id })
        XCTAssertEqual(log.entries.map(\.sequence), [2, 3, 4])
    }

    func testExpiryAndClearHaveExplicitDifferentSemantics() {
        var log = ObservationLog(maximumEntries: entryLimit, maximumAgeSeconds: ageLimit)
        log.append(kind: .captureStarted, captureID: nil, source: .notebook, at: epoch)
        let oldCursor = log.cursor
        log.prune(at: epoch.addingTimeInterval(ageLimit + 1))
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertEqual(log.evictedEntries, 1)
        XCTAssertEqual(log.cursor, oldCursor)
        log.clear()
        XCTAssertNotEqual(log.journalID, oldCursor.journalID)
        XCTAssertEqual(log.lastSequence, 0)
        XCTAssertEqual(log.evictedEntries, 0)
    }

    func testJSONLHasHeaderAndIndividuallyDecodableEntries() throws {
        var log = ObservationLog()
        log.append(kind: .captureStarted, captureID: UUID(), source: .notebook, at: epoch)
        log.append(kind: .captureStopped, captureID: nil, source: .notebook, at: epoch)
        let bytes = try log.snapshot.jsonlData()
        let lines = try XCTUnwrap(String(data: bytes, encoding: .utf8)).split(separator: "\n")
        XCTAssertEqual(lines.count, log.entries.count + 1)
        let header = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(header["type"] as? String, "observation_log")
        XCTAssertEqual(header["journalID"] as? String, log.journalID.uuidString)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try lines.dropFirst().map { try decoder.decode(ObservationEntry.self, from: Data($0.utf8)) }
        XCTAssertEqual(decoded.map(\.id), log.entries.map(\.id))
        XCTAssertEqual(decoded.map(\.kind), log.entries.map(\.kind))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("base64"))
    }
}

@MainActor
final class NotebookObservationTests: XCTestCase {
    private var directory: URL!
    private var store: NotebookStore!
    private var recorder: ContextRecorder!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        store = NotebookStore(fileURL: directory.appending(path: "notebook.json"))
        recorder = ContextRecorder()
    }

    override func tearDownWithError() throws {
        recorder.stop()
        store.saveNow()
        try FileManager.default.removeItem(at: directory)
        recorder = nil
        store = nil
    }

    private func drawingFixture() -> PKDrawing {
        let points = [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)].map {
            PKStrokePoint(location: $0, timeOffset: 0, size: CGSize(width: 4, height: 4),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
                                            path: PKStrokePath(controlPoints: points, creationDate: Date()))])
    }

    func testChangesInOneRunLoopAreNotCoalescedAndNoOpAssignmentsAreIgnored() {
        var observed: [NotebookObservation] = []
        let subscription = store.observations.sink { observed.append($0) }
        defer { subscription.cancel() }
        store.mode = .eraser
        store.mode = .pen
        store.mode = .pen
        store.selection = CGRect(x: 10, y: 10, width: 100, height: 100)
        store.selection = nil
        store.selection = nil
        XCTAssertEqual(observed.map(\.kind), [.editorModeChanged, .editorModeChanged,
                                              .selectionChanged, .selectionChanged])
        XCTAssertEqual(observed.first?.document.editorMode, EditorMode.eraser.rawValue)
        XCTAssertNotNil(observed[2].document.selection)
        XCTAssertNil(observed.last?.document.selection)
    }

    func testDrawingAndAutomaticSelectionClearPublishCoherentFinalState() {
        store.selection = CGRect(x: 10, y: 10, width: 100, height: 100)
        var observed: [NotebookObservation] = []
        let subscription = store.observations.sink { observed.append($0) }
        defer { subscription.cancel() }
        store.updateDrawing(drawingFixture())
        XCTAssertEqual(observed.map(\.kind), [.drawingChanged, .selectionChanged])
        XCTAssertTrue(observed.allSatisfy { $0.document.revision == store.revision && $0.document.selection == nil })
    }

    func testWriteThenEraseBetweenSamplesStillLeavesFactualEvents() {
        recorder.start(source: .notebook, store: store)
        let baseline = recorder.history.frames[0]
        store.isUsingDrawingTool = true
        store.updateDrawing(drawingFixture())
        store.isUsingDrawingTool = false
        store.mode = .eraser
        store.isUsingDrawingTool = true
        store.updateDrawing(PKDrawing())
        store.isUsingDrawingTool = false
        // No timer tick occurred between writing and erasing.
        XCTAssertEqual(recorder.history.frames.count, 1)
        recorder.sampleNotebook(store)
        let entries = recorder.observationLog.entries
        XCTAssertEqual(entries.filter { $0.kind == .drawingChanged }.map { $0.document?.revision }, [1, 2])
        XCTAssertEqual(entries.filter { $0.kind == .toolUseBegan }.count, 2)
        XCTAssertEqual(entries.filter { $0.kind == .toolUseEnded }.count, 2)
        XCTAssertEqual(recorder.history.frames.last?.image.base64, baseline.image.base64)
        XCTAssertEqual(recorder.history.frames.last?.document?.revision, 2)
        // We know a revision occurred, but do NOT claim that the erased formula can be reconstructed.
    }

    func testDocumentFrameLinksToJournalBoundaryAndReceiptEvent() throws {
        recorder.start(source: .notebook, store: store)
        store.updateDrawing(drawingFixture())
        recorder.sampleNotebook(store)
        let frame = try XCTUnwrap(recorder.history.frames.last)
        let cursor = try XCTUnwrap(frame.eventCursor)
        XCTAssertEqual(cursor.journalID, recorder.observationLog.journalID)
        let boundary = try XCTUnwrap(recorder.observationLog.entries.first { $0.sequence == cursor.throughSequence })
        XCTAssertEqual(boundary.kind, .drawingChanged)
        XCTAssertEqual(boundary.document, frame.document)
        let receipt = try XCTUnwrap(recorder.observationLog.entries.last)
        XCTAssertEqual(receipt.kind, .frameRetained)
        XCTAssertEqual(receipt.frameID, frame.id)
        XCTAssertGreaterThan(receipt.sequence, cursor.throughSequence)
    }

    func testInterruptionIsNotFabricatedAsNormalToolEnd() {
        recorder.start(source: .notebook, store: store)
        store.isUsingDrawingTool = true
        store.interruptDrawingTool()
        store.isUsingDrawingTool = false // Late end callback must not duplicate the transition.
        XCTAssertEqual(recorder.observationLog.entries.suffix(2).map(\.kind), [.toolUseBegan, .toolUseInterrupted])
        XCTAssertFalse(store.isUsingDrawingTool)
    }

    func testStoppingDoesNotInventToolEndAndDoesNotObservePrivateEdits() {
        recorder.start(source: .notebook, store: store)
        store.isUsingDrawingTool = true
        recorder.stop()
        let stopped = recorder.observationLog.snapshot
        XCTAssertEqual(stopped.entries.last?.kind, .captureStopped)
        XCTAssertEqual(stopped.entries.last?.document?.isUsingDrawingTool, true)
        store.updateDrawing(drawingFixture())
        store.isUsingDrawingTool = false
        store.mode = .select
        XCTAssertEqual(recorder.observationLog.entries.map(\.id), stopped.entries.map(\.id))
        recorder.start(source: .notebook, store: store)
        let starts = recorder.observationLog.entries.filter { $0.kind == .captureStarted }
        XCTAssertEqual(starts.count, 2)
        XCTAssertNotEqual(starts.first?.captureID, starts.last?.captureID)
        XCTAssertEqual(starts.last?.document?.revision, store.revision)
        XCTAssertFalse(recorder.observationLog.entries.contains { $0.kind == .drawingChanged })
    }

    func testAssemblyIsImmutableAndPureProjectionDoesNotRewriteRawLog() throws {
        recorder.start(source: .notebook, store: store)
        recorder.stop()
        let context = try recorder.assembleContext(from: store)
        XCTAssertEqual(context.observations.entries.last?.kind, .contextPrepared)
        XCTAssertEqual(context.observations.entries.last?.frameID, context.currentDocument.id)
        XCTAssertEqual(context.currentDocument.eventCursor, recorder.observationLog.cursor)
        let raw = try context.observations.jsonlData()
        let projected = ContextAssembler.assemble(id: context.id, history: recorder.history,
                                                  observations: context.observations,
                                                  currentDocument: context.currentDocument,
                                                  prompt: context.prompt, at: context.assembledAt)
        XCTAssertEqual(try context.jsonData(), try projected.jsonData())
        XCTAssertEqual(raw, try recorder.observationLog.snapshot.jsonlData())
        recorder.clearHistory()
        XCTAssertTrue(recorder.observationLog.entries.isEmpty)
        XCTAssertNotEqual(recorder.observationLog.journalID, context.observations.journalID)
        XCTAssertEqual(raw, try context.observations.jsonlData())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LearningContext.self, from: context.jsonData())
        XCTAssertEqual(decoded.observations.entries.map(\.id), context.observations.entries.map(\.id))
        XCTAssertEqual(decoded.currentDocument.eventCursor, context.currentDocument.eventCursor)
    }

    func testPreviewWithoutRecordingDoesNotStartPassiveObservation() throws {
        _ = try recorder.assembleContext(from: store)
        XCTAssertEqual(recorder.observationLog.entries.map(\.kind), [.contextPrepared])
        store.mode = .eraser
        store.updateDrawing(drawingFixture())
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertEqual(recorder.observationLog.entries.count, 1)
        XCTAssertTrue(recorder.history.frames.isEmpty)
    }
}
