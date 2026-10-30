import CoreImage
import PencilKit
import XCTest
@testable import PencilNotes

private enum ContextFixture {
    static let now = Date(timeIntervalSince1970: 1_000)
    static let maximumFrames = 3
    static let maximumBytes = 12
    static let maximumAge: TimeInterval = 10
    static let asyncTimeout: TimeInterval = 3
    static let retention = ContextRetention(maximumFrames: maximumFrames, maximumBase64Bytes: maximumBytes,
                                             maximumAgeSeconds: maximumAge)

    static func frame(_ payload: String, at date: Date = now,
                      source: ContextSource = .replayKitApp) -> ContextFrame {
        // These strings test retention accounting only; image decoding is tested separately.
        ContextFrame(id: UUID(), capturedAt: date, source: source,
                     image: RequestImage(mimeType: "image/png", widthPixels: 1, heightPixels: 1, base64: payload),
                     document: nil)
    }
}

final class ContextHistoryTests: XCTestCase {
    func testCountLimitEvictsOldest() {
        var history = ContextHistory(retention: ContextFixture.retention)
        for value in ["a", "b", "c", "d"] {
            history.append(ContextFixture.frame(value), now: ContextFixture.now)
        }
        XCTAssertEqual(history.frames.map(\.image.base64), ["b", "c", "d"])
        XCTAssertEqual(history.evictedCount, 1)
    }

    func testByteLimitEvictsOldestAndRejectsOversizedFrame() {
        var history = ContextHistory(retention: ContextFixture.retention)
        history.append(ContextFixture.frame("12345678"), now: ContextFixture.now)
        history.append(ContextFixture.frame("abcdefgh"), now: ContextFixture.now)
        XCTAssertEqual(history.frames.map(\.image.base64), ["abcdefgh"])
        let oversized = String(repeating: "x", count: ContextFixture.maximumBytes + 1)
        XCTAssertFalse(history.append(ContextFixture.frame(oversized), now: ContextFixture.now))
        XCTAssertEqual(history.oversizedCount, 1)
        XCTAssertLessThanOrEqual(history.retainedBase64Bytes, ContextFixture.maximumBytes)
    }

    func testAgeLimitAndClear() {
        var history = ContextHistory(retention: ContextFixture.retention)
        history.append(ContextFixture.frame("old"), now: ContextFixture.now)
        let expiredTime = ContextFixture.now.addingTimeInterval(ContextFixture.maximumAge + 1)
        history.prune(at: expiredTime)
        XCTAssertTrue(history.frames.isEmpty)
        XCTAssertFalse(history.append(ContextFixture.frame("late"), now: expiredTime))
        history.clear()
        XCTAssertEqual(history.evictedCount, 0)
        XCTAssertEqual(history.retainedBase64Bytes, 0)
    }

    func testOnlyConsecutiveIdenticalSourceAndStateAreDeduplicated() {
        var history = ContextHistory(retention: ContextFixture.retention)
        XCTAssertTrue(history.append(ContextFixture.frame("same"), now: ContextFixture.now))
        XCTAssertFalse(history.append(ContextFixture.frame("same"), now: ContextFixture.now))
        XCTAssertTrue(history.append(ContextFixture.frame("same", source: .notebook), now: ContextFixture.now))
        XCTAssertEqual(history.duplicateCount, 1)
    }
}

final class ScreenSamplingTests: XCTestCase {
    func testGateAdmitsFirstFrameThenOnlyAtInterval() {
        let interval = PrototypeConfiguration.Context.samplingIntervalSeconds
        var gate = SampleGate(interval: interval)
        let initialTime: TimeInterval = 100
        XCTAssertTrue(gate.accept(at: initialTime))
        XCTAssertFalse(gate.accept(at: initialTime))
        XCTAssertFalse(gate.accept(at: initialTime + interval / 2))
        XCTAssertTrue(gate.accept(at: initialTime + interval))
        XCTAssertFalse(gate.accept(at: initialTime - interval))
    }

    func testScreenEncoderNormalizesRotationAndLimitsPixelSize() throws {
        let maximumEdge = PrototypeConfiguration.Context.screenMaximumPixelEdge
        let input = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: maximumEdge * 2, height: maximumEdge))
        let encoded = try ScreenFrameEncoder.encode(input, orientation: .right, context: CIContext())
        XCTAssertEqual(encoded.mimeType, "image/jpeg")
        XCTAssertEqual(encoded.widthPixels, Int(maximumEdge / 2))
        XCTAssertEqual(encoded.heightPixels, Int(maximumEdge))
        XCTAssertNotNil(encoded.uiImage)
    }
}

@MainActor
private final class FakeScreenCapture: ScreenCaptureSource {
    var frameHandler: (@MainActor (ContextFrame) -> Void)?
    var failureHandler: (@MainActor (String) -> Void)?
    var startContinuation: CheckedContinuation<Void, Error>?
    var started: XCTestExpectation?
    var stopped: XCTestExpectation?
    var delayStart = false
    var failStart = false
    var failStop = false
    var stopCalls = 0
    var accepting = false

    func start(onFrame: @escaping @MainActor (ContextFrame) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        frameHandler = onFrame
        failureHandler = onFailure
        started?.fulfill()
        if failStart { throw ReplayCaptureError.unavailable }
        if delayStart {
            try await withCheckedThrowingContinuation { startContinuation = $0 }
        }
    }

    func setAcceptingFrames(_ value: Bool) { accepting = value }
    func stop() async throws {
        stopCalls += 1
        stopped?.fulfill()
        if failStop { throw ReplayCaptureError.unavailable }
    }
}

@MainActor
final class ContextRecorderTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var stores: [NotebookStore] = []
    private var recorders: [ContextRecorder] = []

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for recorder in recorders { recorder.stop() }
        for store in stores { store.saveNow() }
        recorders.removeAll()
        stores.removeAll()
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func makeStore() -> NotebookStore {
        let store = NotebookStore(fileURL: temporaryDirectory.appending(path: "\(UUID()).json"))
        stores.append(store)
        return store
    }

    private func makeRecorder(_ source: FakeScreenCapture? = nil) -> ContextRecorder {
        let recorder = ContextRecorder(screenCapture: source ?? FakeScreenCapture())
        recorders.append(recorder)
        return recorder
    }

    func testNotebookSkipsUnchangedAndActiveStrokeButRecordsErasureRevision() {
        let store = makeStore()
        let recorder = makeRecorder()
        recorder.start(source: .notebook, store: store)
        XCTAssertEqual(recorder.history.frames.count, 1)
        recorder.sampleNotebook(store)
        XCTAssertEqual(recorder.history.frames.count, 1)
        store.isUsingDrawingTool = true
        store.updateDrawing(PKDrawing())
        recorder.sampleNotebook(store)
        XCTAssertEqual(recorder.history.frames.count, 1)
        store.isUsingDrawingTool = false
        recorder.sampleNotebook(store)
        XCTAssertEqual(recorder.history.frames.count, 2, "A revision change matters even for identical blank images")
        XCTAssertEqual(recorder.history.frames.last?.document?.revision, store.revision)
    }

    func testSelectionIsContextEvenWithoutNewInk() {
        let store = makeStore()
        let recorder = makeRecorder()
        recorder.start(source: .notebook, store: store)
        store.selection = CGRect(x: 50, y: 50, width: 100, height: 100)
        recorder.sampleNotebook(store)
        XCTAssertEqual(recorder.history.frames.count, 2)
        XCTAssertEqual(recorder.history.frames.last?.document?.selection, store.selection.map(PageRegion.init))
    }

    func testAssemblyAlwaysIncludesFreshCurrentDocumentAndRoundTrips() throws {
        let store = makeStore()
        let recorder = makeRecorder()
        recorder.start(source: .notebook, store: store)
        recorder.stop()
        store.updateDrawing(PKDrawing())
        store.prompt = "我的问题"
        let context = try recorder.assembleContext(from: store)
        XCTAssertEqual(context.history.count, 1)
        XCTAssertEqual(context.history.first?.document?.revision, 0)
        XCTAssertEqual(context.currentDocument.document?.revision, store.revision)
        XCTAssertEqual(context.prompt, store.prompt)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LearningContext.self, from: context.jsonData())
        XCTAssertEqual(decoded.currentDocument.image.base64, context.currentDocument.image.base64)
        XCTAssertEqual(decoded.history.count, context.history.count)
        XCTAssertEqual(decoded.kind, PrototypeConfiguration.Context.kind)
    }

    func testLeavingForegroundStopsWithoutAutomaticResume() {
        let recorder = makeRecorder()
        let store = makeStore()
        recorder.start(source: .notebook, store: store)
        recorder.setForeground(false)
        XCTAssertEqual(recorder.phase, .idle)
        recorder.setForeground(true)
        XCTAssertEqual(recorder.phase, .idle)
        recorder.clearHistory()
        recorder.sampleNotebook(store)
        XCTAssertTrue(recorder.history.frames.isEmpty)
    }

    func testLateScreenFrameCannotRefillClearedHistory() async {
        let source = FakeScreenCapture()
        source.started = expectation(description: "started")
        source.stopped = expectation(description: "stopped")
        let recorder = makeRecorder(source)
        let store = makeStore()
        recorder.start(source: .replayKitApp, store: store)
        await fulfillment(of: [source.started!], timeout: ContextFixture.asyncTimeout)
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertTrue(source.accepting)
        store.isUsingDrawingTool = true
        XCTAssertFalse(source.accepting, "Eligibility updates synchronously, without a SwiftUI render")
        source.frameHandler?(ContextFixture.frame("in-flight while drawing", at: Date()))
        XCTAssertTrue(recorder.history.frames.isEmpty)
        store.isUsingDrawingTool = false
        XCTAssertTrue(source.accepting)
        source.frameHandler?(ContextFixture.frame("image", at: Date()))
        XCTAssertEqual(recorder.history.frames.count, 1)
        XCTAssertNil(recorder.history.frames.last?.eventCursor)
        XCTAssertNil(recorder.history.frames.last?.document)
        XCTAssertEqual(recorder.observationLog.entries.last?.kind, .frameRetained)
        XCTAssertNil(recorder.observationLog.entries.last?.document)
        recorder.stop()
        source.frameHandler?(ContextFixture.frame("late", at: Date()))
        await fulfillment(of: [source.stopped!], timeout: ContextFixture.asyncTimeout)
        recorder.clearHistory()
        source.frameHandler?(ContextFixture.frame("later", at: Date()))
        XCTAssertTrue(recorder.history.frames.isEmpty)
        XCTAssertFalse(source.accepting)
    }

    func testStopWhilePermissionPendingDoesNotResumeCapture() async {
        let source = FakeScreenCapture()
        source.delayStart = true
        source.started = expectation(description: "permission requested")
        source.stopped = expectation(description: "late start stopped")
        let recorder = makeRecorder(source)
        recorder.start(source: .replayKitApp, store: makeStore())
        await fulfillment(of: [source.started!], timeout: ContextFixture.asyncTimeout)
        recorder.setForeground(false) // System permission sheet is allowed while starting.
        XCTAssertEqual(recorder.phase, .starting)
        recorder.setForeground(false, enteredBackground: true)
        XCTAssertEqual(recorder.phase, .stopping)
        source.startContinuation?.resume()
        source.startContinuation = nil
        await fulfillment(of: [source.stopped!], timeout: ContextFixture.asyncTimeout)
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertFalse(source.accepting)
        XCTAssertTrue(recorder.history.frames.isEmpty)
    }

    func testUnavailableSourceDoesNotPretendToBeRecording() async {
        let source = FakeScreenCapture()
        source.failStart = true
        source.started = expectation(description: "failed start attempted")
        let recorder = makeRecorder(source)
        recorder.start(source: .replayKitApp, store: makeStore())
        await fulfillment(of: [source.started!], timeout: ContextFixture.asyncTimeout)
        XCTAssertEqual(recorder.phase, .idle)
        XCTAssertNotNil(recorder.errorMessage)
    }

    func testStopFailureRequiresRetryInsteadOfClaimingSuccess() async {
        let source = FakeScreenCapture()
        source.failStop = true
        source.started = expectation(description: "start")
        source.stopped = expectation(description: "first stop")
        let recorder = makeRecorder(source)
        recorder.start(source: .replayKitApp, store: makeStore())
        await fulfillment(of: [source.started!], timeout: ContextFixture.asyncTimeout)
        recorder.stop()
        await fulfillment(of: [source.stopped!], timeout: ContextFixture.asyncTimeout)
        XCTAssertEqual(recorder.phase, .stopFailed)
        XCTAssertFalse(recorder.canStart)
        source.failStop = false
        source.stopped = expectation(description: "retry stop")
        recorder.stop()
        await fulfillment(of: [source.stopped!], timeout: ContextFixture.asyncTimeout)
        XCTAssertEqual(recorder.phase, .idle)
    }
}
