import Combine
import Foundation
import PencilKit

struct NotebookDocument: Codable {
    let id: UUID
    let revision: Int
    let drawingData: Data
}

struct NotebookPersistence {
    let url: URL

    func load() throws -> NotebookDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(NotebookDocument.self, from: Data(contentsOf: url))
    }

    func save(_ document: NotebookDocument) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
    }
}

enum EditorMode: String, CaseIterable, Identifiable {
    case pen = "书写"
    case eraser = "橡皮"
    case select = "框选"
    var id: Self { self }
}

@MainActor
final class NotebookStore: ObservableObject {
    @Published private(set) var drawing = PKDrawing()
    @Published private(set) var revision = 0
    @Published var selection: CGRect? {
        didSet {
            if selection != oldValue && !isUpdatingDrawing { emit(.selectionChanged) }
        }
    }
    @Published var mode: EditorMode = .pen {
        didSet { if mode != oldValue { emit(.editorModeChanged) } }
    }
    @Published var isUsingDrawingTool = false {
        didSet {
            guard isUsingDrawingTool != oldValue, !isInterruptingTool else { return }
            emit(isUsingDrawingTool ? .toolUseBegan : .toolUseEnded)
        }
    }
    @Published var prompt = "请解释我框选的这一步，先不要给出完整答案。"
    @Published var snapshot: AssistantRequest?
    @Published var errorMessage: String?
    @Published private(set) var saveStatus = "尚无笔迹"
    @Published private(set) var loadFailed = false

    private(set) var notebookID = UUID()
    private let persistence: NotebookPersistence
    private var saveTask: Task<Void, Never>?
    private var isUpdatingDrawing = false
    private var isInterruptingTool = false
    private let observationSubject = PassthroughSubject<NotebookObservation, Never>()

    var observations: AnyPublisher<NotebookObservation, Never> { observationSubject.eraseToAnyPublisher() }

    private func emit(_ kind: ObservationKind) {
        guard !loadFailed else { return }
        observationSubject.send(NotebookObservation(kind: kind, occurredAt: Date(), document: documentContext))
    }

    func interruptDrawingTool() {
        guard isUsingDrawingTool else { return }
        isInterruptingTool = true
        isUsingDrawingTool = false
        isInterruptingTool = false
        emit(.toolUseInterrupted)
    }

    init(fileURL: URL? = nil) {
        let defaultURL = URL.documentsDirectory
            .appending(path: "PencilNotes", directoryHint: .isDirectory)
            .appending(path: "notebook.json")
        persistence = NotebookPersistence(url: fileURL ?? defaultURL)
        do {
            if let document = try persistence.load() {
                drawing = try PKDrawing(data: document.drawingData)
                revision = document.revision
                notebookID = document.id
                saveStatus = "已恢复本地笔记"
            }
        } catch {
            // Do not silently replace an unreadable document with a blank drawing.
            loadFailed = true
            saveStatus = "读取失败 · 已禁止编辑，保留原文件"
            errorMessage = "无法读取本地笔记：\(error.localizedDescription)"
        }
    }

    func updateDrawing(_ value: PKDrawing) {
        guard !loadFailed else { return }
        let hadSelection = selection != nil
        isUpdatingDrawing = true
        drawing = value
        revision += 1
        selection = nil
        isUpdatingDrawing = false
        // Publish coherent final state; automatic selection clearing is a separate observed transition.
        emit(.drawingChanged)
        if hadSelection { emit(.selectionChanged) }
        saveStatus = "正在保存…"
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: PrototypeConfiguration.Timing.saveDebounce) }
            catch { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard !loadFailed else { return }
        saveTask?.cancel()
        do {
            try persistence.save(NotebookDocument(id: notebookID, revision: revision,
                                                   drawingData: drawing.dataRepresentation()))
            saveStatus = "已保存到本机"
        } catch {
            saveStatus = "保存失败"
            errorMessage = "无法保存笔记：\(error.localizedDescription)"
        }
    }

    var documentContext: DocumentContext {
        DocumentContext(notebookID: notebookID, revision: revision,
                        coordinateSpace: PrototypeConfiguration.Snapshot.coordinateSpace,
                        page: PageRegion(PrototypeConfiguration.Page.bounds),
                        selection: selection.map(PageRegion.init), editorMode: mode.rawValue,
                        isUsingDrawingTool: isUsingDrawingTool)
    }

    func contextFrame(at date: Date = Date()) throws -> ContextFrame {
        // Runs synchronously on the main actor: metadata and pixels describe the same revision.
        ContextFrame(id: UUID(), capturedAt: date, source: .notebook,
                     image: try SnapshotBuilder.documentImage(drawing: drawing), document: documentContext)
    }

    func makeSnapshot() {
        guard let selection else { return }
        do {
            snapshot = try SnapshotBuilder.make(drawing: drawing, notebookID: notebookID,
                                                 revision: revision, selection: selection,
                                                 prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
