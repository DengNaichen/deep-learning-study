import SwiftUI

@main
struct PencilNotesApp: App {
    @StateObject private var store: NotebookStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // UI tests get a fresh sandbox document; never reset the user's notebook.
        let testURL = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            ? FileManager.default.temporaryDirectory.appending(path: "ui-test-\(UUID()).json")
            : nil
        _store = StateObject(wrappedValue: NotebookStore(fileURL: testURL))
    }

    var body: some Scene {
        WindowGroup {
            NotebookView(store: store)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { store.saveNow() }
                }
        }
    }
}

struct NotebookView: View {
    @ObservedObject var store: NotebookStore
    @StateObject private var recorder = ContextRecorder()
    @State private var assembledContext: LearningContext?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("编辑模式", selection: $store.mode) {
                    ForEach(EditorMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .padding()
                .disabled(store.loadFailed)

                ContextControls(recorder: recorder, store: store, inspect: inspectContext)

                NotebookCanvas(store: store)
                    .frame(minHeight: PrototypeConfiguration.Layout.minimumEditorHeight)
                    .allowsHitTesting(!store.loadFailed)

                VStack(alignment: .leading, spacing: PrototypeConfiguration.Layout.compactSpacing) {
                    HStack {
                        Text(instruction).font(.caption)
                        Spacer()
                        Text(store.saveStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("想问助手什么？", text: $store.prompt)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("questionField")
                    HStack {
                        Label("仅本地模拟 · 不上传", systemImage: "lock.shield")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("预览选区请求", systemImage: "viewfinder") {
                            recorder.stop()
                            store.makeSnapshot()
                        }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("previewSelection")
                            .disabled(store.loadFailed || store.mode != .select || store.selection == nil
                                      || store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
            }
            .navigationTitle("Pencil Notes · 原型")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $store.snapshot) { request in
                RequestPreview(request: request, client: MockAssistantClient())
            }
            .sheet(item: $assembledContext) { context in
                ContextInspector(context: context, recorder: recorder)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase != .active { store.interruptDrawingTool() }
                recorder.setForeground(phase == .active, enteredBackground: phase == .background)
            }
            .onDisappear { recorder.stop() }
            .alert("笔记错误", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }

    private func inspectContext() {
        // Stop before presenting the inspector so ReplayKit cannot record its own history previews.
        recorder.stop()
        do { assembledContext = try recorder.assembleContext(from: store) }
        catch { store.errorMessage = error.localizedDescription }
    }

    private var instruction: String {
        switch store.mode {
        case .pen: return "用 Apple Pencil 或手指书写。"
        case .eraser: return "划过笔迹以擦除整条笔画。"
        case .select:
            return store.selection == nil ? "在纸上拖出一个矩形选区。" : "已框选；可重新拖动，或预览请求。"
        }
    }
}
