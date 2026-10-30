import Combine
import Foundation

@MainActor
protocol ScreenCaptureSource: AnyObject {
    func start(onFrame: @escaping @MainActor (ContextFrame) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws
    func setAcceptingFrames(_ value: Bool)
    func stop() async throws
}

extension ReplayKitCapture: ScreenCaptureSource {}

@MainActor
final class ContextRecorder: ObservableObject {
    enum Phase { case idle, starting, recording, stopping, stopFailed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var source: ContextSource = .notebook
    @Published private(set) var history = ContextHistory()
    @Published private(set) var observationLog = ObservationLog()
    @Published private(set) var errorMessage: String?
    @Published private(set) var status = "记录关闭 · 仅本地"

    private let screenCapture: any ScreenCaptureSource
    private var timerTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var lastDocument: DocumentContext?
    private var foreground = true
    private var usingDrawingTool = false
    private var notebookSubscription: AnyCancellable?
    private weak var observedStore: NotebookStore?

    init(screenCapture: (any ScreenCaptureSource)? = nil) {
        self.screenCapture = screenCapture ?? ReplayKitCapture()
    }

    var canStart: Bool { phase == .idle }
    var isTransitioning: Bool { phase == .starting || phase == .stopping }

    func start(source: ContextSource, store: NotebookStore) {
        guard canStart, foreground, !store.loadFailed else { return }
        self.source = source
        usingDrawingTool = store.isUsingDrawingTool
        errorMessage = nil
        lastDocument = nil
        let session = UUID()
        sessionID = session
        phase = .starting
        status = "正在启动 \(source.title)…"

        switch source {
        case .notebook:
            phase = .recording
            status = "正在记录笔记变化 · 仅本地"
            beginObserving(store, session: session)
            sampleNotebook(store)
            timerTask = Task { [weak self, weak store] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(PrototypeConfiguration.Context.samplingIntervalSeconds)) }
                    catch { return }
                    guard let self, let store, self.sessionID == session else { return }
                    self.sampleNotebook(store)
                }
            }
        case .replayKitApp:
            transitionTask = Task { [weak self, weak store] in
                guard let self else { return }
                do {
                    try await self.screenCapture.start(onFrame: { [weak self] frame in
                        guard let self, self.sessionID == session, self.phase == .recording,
                              self.foreground, !self.usingDrawingTool else { return }
                        self.retain(frame, at: Date())
                    }, onFailure: { [weak self] message in
                        guard let self, self.sessionID == session else { return }
                        self.errorMessage = message
                        self.stop()
                    })
                    guard self.sessionID == session, let store else {
                        self.sessionID = nil
                        await self.finishScreenStop()
                        return
                    }
                    self.phase = .recording
                    self.status = "正在采集本 App 屏幕 · 仅本地"
                    self.beginObserving(store, session: session)
                    self.updateScreenEligibility()
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.sessionID = nil
                    self.phase = .idle
                    self.status = "屏幕采集未启动"
                }
            }
        }
    }

    func stop() {
        let previousPhase = phase
        guard previousPhase != .idle, previousPhase != .stopping else { return }
        if previousPhase == .recording, let sessionID {
            observationLog.append(kind: .captureStopped, captureID: sessionID, source: source,
                                  document: observedStore?.documentContext)
        }
        notebookSubscription?.cancel()
        notebookSubscription = nil
        observedStore = nil
        // Invalidate callbacks before awaiting any system cleanup.
        sessionID = nil
        timerTask?.cancel()
        timerTask = nil
        screenCapture.setAcceptingFrames(false)
        phase = .stopping
        status = "正在停止…"
        if source == .notebook {
            phase = .idle
            status = "记录已停止 · 历史仍在本机内存"
        } else if previousPhase == .recording || previousPhase == .stopFailed {
            transitionTask = Task { [weak self] in await self?.finishScreenStop() }
        }
        // During a permission prompt, startCapture must finish before stopCapture is called.
        // The pending start task observes the invalid session and stops rather than resuming.
    }

    private func finishScreenStop() async {
        do {
            try await screenCapture.stop()
            phase = .idle
            status = "记录已停止 · 历史仍在本机内存"
        } catch {
            errorMessage = "停止采集失败：\(error.localizedDescription)。请重试停止，或使用系统录屏控制。"
            phase = .stopFailed
            status = "不再接收帧 · 系统录制停止失败"
        }
    }

    func setForeground(_ value: Bool, enteredBackground: Bool = false) {
        foreground = value
        updateScreenEligibility()
        // Permission sheets can make a starting app inactive. Only backgrounding cancels that start.
        if !value && (phase == .recording || enteredBackground) { stop() }
    }

    func setUsingDrawingTool(_ value: Bool) {
        usingDrawingTool = value
        updateScreenEligibility()
    }

    private func beginObserving(_ store: NotebookStore, session: UUID) {
        observedStore = store
        usingDrawingTool = store.isUsingDrawingTool
        observationLog.append(kind: .captureStarted, captureID: session, source: source,
                              document: store.documentContext)
        // No scheduler hop: preserve mutation order even when many changes happen in one render pass.
        notebookSubscription = store.observations.sink { [weak self] observation in
            guard let self, self.sessionID == session, self.phase == .recording, self.foreground else { return }
            self.setUsingDrawingTool(observation.document.isUsingDrawingTool)
            self.observationLog.append(kind: observation.kind, captureID: session, source: .notebook,
                                       document: observation.document, at: observation.occurredAt)
        }
    }

    private func retain(_ frame: ContextFrame, at now: Date) {
        if history.append(frame, now: now) {
            observationLog.append(kind: .frameRetained, captureID: sessionID, source: frame.source,
                                  document: frame.document, frameID: frame.id, at: now)
        }
    }

    private func updateScreenEligibility() {
        screenCapture.setAcceptingFrames(phase == .recording && foreground && !usingDrawingTool)
    }

    /// Synchronous and independently testable; the periodic task is merely a scheduler.
    func sampleNotebook(_ store: NotebookStore, now: Date = Date()) {
        history.prune(at: now)
        observationLog.prune(at: now)
        guard phase == .recording, source == .notebook, foreground,
              !store.isUsingDrawingTool else { return }
        let state = store.documentContext
        // Selection and tool mode are context too, even when no new ink was written.
        guard state != lastDocument || history.frames.isEmpty else { return }
        do {
            let frame = try store.contextFrame(at: now).linked(to: observationLog.cursor)
            retain(frame, at: now)
            lastDocument = state
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    func clearHistory() {
        // The UI requires stopped capture so a late callback cannot refill a cleared history.
        guard phase == .idle else { return }
        history.clear()
        observationLog.clear()
        lastDocument = nil
        status = "历史已清空"
    }

    func assembleContext(from store: NotebookStore, now: Date = Date()) throws -> LearningContext {
        history.prune(at: now)
        observationLog.prune(at: now)
        let current = try store.contextFrame(at: now)
        // This is a preview request, not a submitted question or an implicit restart of observation.
        observationLog.append(kind: .contextPrepared, captureID: sessionID, source: .notebook,
                              document: current.document, frameID: current.id, at: now)
        return ContextAssembler.assemble(id: UUID(), history: history, observations: observationLog.snapshot,
                                         currentDocument: current.linked(to: observationLog.cursor),
                                         prompt: store.prompt, at: now)
    }
}
