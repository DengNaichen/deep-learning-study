import SwiftUI
import UniformTypeIdentifiers

struct ContextControls: View {
    @ObservedObject var recorder: ContextRecorder
    @ObservedObject var store: NotebookStore
    let inspect: () -> Void
    @State private var selectedSource: ContextSource = .notebook
    @State private var confirmScreenCapture = false

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeConfiguration.Layout.compactSpacing) {
            HStack {
                Picker("采集来源", selection: $selectedSource) {
                    ForEach(ContextSource.allCases) { source in Text(source.title).tag(source) }
                }
                .pickerStyle(.menu)
                .disabled(!recorder.canStart)
                .accessibilityIdentifier("contextSource")
                Spacer()
                Button(recorder.canStart ? "开始记录" : "停止记录") {
                    if !recorder.canStart { recorder.stop() }
                    else if selectedSource == .replayKitApp { confirmScreenCapture = true }
                    else { recorder.start(source: selectedSource, store: store) }
                }
                .disabled(store.loadFailed || recorder.phase == .stopping)
                .accessibilityIdentifier("toggleContextRecording")
                Button("上下文 (\(recorder.history.frames.count))", action: inspect)
                    .disabled(store.loadFailed || recorder.isTransitioning)
                    .accessibilityIdentifier("inspectContext")
            }
            Text("\(recorder.status) · \(recorder.observationLog.entries.count) 条事件")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("contextStatus")
            if let error = recorder.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, PrototypeConfiguration.Layout.compactSpacing)
        .confirmationDialog("允许记录本 App 的屏幕画面？", isPresented: $confirmScreenCapture,
                            titleVisibility: .visible) {
            Button("开始本地屏幕采集") { recorder.start(source: .replayKitApp, store: store) }
        } message: {
            Text("会保留本 App 屏幕的定时截图，可能包括问题输入和工具栏。不开启麦克风或摄像头，不保存音频，不上传。可以随时停止并清空。之后还可能出现系统录屏确认。")
        }
    }
}

struct ContextInspector: View {
    private enum Section: String, CaseIterable { case images = "图像", events = "事件" }

    let context: LearningContext
    @ObservedObject var recorder: ContextRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: ExportDocument?
    @State private var exportType: UTType = .json
    @State private var exportFilename = "context"
    @State private var section: Section = .images
    @State private var isExporting = false
    @State private var confirmClear = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PrototypeConfiguration.Layout.spacing) {
                    Label("已停止接收新帧 · 没有模型或网络请求", systemImage: "lock.shield")
                        .font(.headline)
                    if recorder.phase == .stopFailed {
                        Text(recorder.errorMessage ?? "系统录制停止失败，请检查录屏指示器。")
                            .foregroundStyle(.red)
                        Button("重试停止系统采集") { recorder.stop() }
                    }
                    Text("这是打开检查器时拼装的固定上下文：近期观察 + 最新笔记 + 问题。关闭后不会自动恢复采集。")
                        .foregroundStyle(.secondary)
                    Text("问题").font(.headline)
                    Text(context.prompt.isEmpty ? "（尚未填写）" : context.prompt).textSelection(.enabled)
                    Picker("检查内容", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("contextSection")
                    if section == .images {
                        Text("最新笔记（拼装时重新生成）").font(.headline)
                        frameView(context.currentDocument)
                        Text("历史记录：\(context.history.count) 帧，按采集顺序排列")
                            .font(.headline).accessibilityIdentifier("contextHistoryCount")
                        Text("采样间隔 \(context.samplingIntervalSeconds.formatted()) 秒；保留上限 \(context.retention.maximumFrames) 帧。已淘汰 \(context.evictedFrames) 帧，跳过重复图像 \(context.skippedDuplicateFrames) 帧，拒绝超预算 \(context.rejectedOversizedFrames) 帧。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(context.history) { frame in frameView(frame) }
                    } else {
                        eventTimeline
                    }
                    Text("注意：离散截图可能漏掉两次采样之间的书写或擦除，不是完整操作录像。屏幕截图不具有笔记页内坐标映射，也不代表已经理解你的意图。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("导出上下文 JSON") {
                        do {
                            exportDocument = ExportDocument(data: try context.jsonData())
                            exportType = .json
                            exportFilename = "context-\(context.id.uuidString)"
                            isExporting = true
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("exportContext")
                    Text("完整 JSON 含最新整页、全部保留图片及事件。切换图像／事件视图不改变导出范围。原始事件 JSONL 不含图片和问题正文。历史仅在内存保留，重启不恢复。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("清空历史并关闭", role: .destructive) { confirmClear = true }
                        .disabled(!recorder.canStart)
                        .accessibilityIdentifier("clearContext")
                }
                .padding()
            }
            .navigationTitle("上下文检查器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("清空本机内存中的全部观察历史？", isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("清空历史", role: .destructive) {
                    recorder.clearHistory()
                    dismiss()
                }
            } message: { Text("清空图像和事件，并重置日志身份；不删除原始笔记或已导出的文件副本。") }
            .fileExporter(isPresented: $isExporting, document: exportDocument, contentType: exportType,
                          defaultFilename: exportFilename) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .alert("上下文导出失败", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("知道了", role: .cancel) { errorMessage = nil } }
            message: { Text(errorMessage ?? "") }
        }
    }

    @ViewBuilder
    private var eventTimeline: some View {
        Text("观察事件：\(context.observations.entries.count) 条")
            .font(.headline).accessibilityIdentifier("observationCount")
        Text("按追加序号排列，不推测学习意图。只保留最近 \(context.observations.maximumEntries) 条，已淘汰 \(context.observations.evictedEntries) 条；不是完整笔画日志，不能重建被擦掉的公式。")
            .font(.caption).foregroundStyle(.secondary)
        Button("导出原始事件 JSONL") {
            do {
                exportDocument = ExportDocument(data: try context.observations.jsonlData())
                exportType = UTType(filenameExtension: "jsonl", conformingTo: .plainText) ?? .plainText
                exportFilename = "observations-\(context.observations.journalID.uuidString).jsonl"
                isExporting = true
            } catch { errorMessage = error.localizedDescription }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("exportObservations")
        ForEach(context.observations.entries) { entry in
            VStack(alignment: .leading, spacing: PrototypeConfiguration.Layout.compactSpacing) {
                Text("#\(entry.sequence) · \(entry.kind.title)").font(.subheadline)
                    .accessibilityIdentifier("observation-\(entry.kind.rawValue)")
                Text("\(entry.occurredAt.formatted(date: .omitted, time: .standard)) · \(entry.source.title)")
                    .font(.caption).foregroundStyle(.secondary)
                if let document = entry.document {
                    Text("修订 \(document.revision) · \(document.editorMode) · \(document.isUsingDrawingTool ? "工具使用中" : "工具未使用")")
                        .font(.caption)
                }
                if let id = entry.frameID {
                    let retained = context.currentDocument.id == id || context.history.contains { $0.id == id }
                    Text("图像 \(id.uuidString)\(retained ? "" : "（当前包未包含）")")
                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Divider()
        }
    }

    private func frameView(_ frame: ContextFrame) -> some View {
        VStack(alignment: .leading, spacing: PrototypeConfiguration.Layout.compactSpacing) {
            Text("\(frame.capturedAt.formatted(date: .omitted, time: .standard)) · \(frame.source.title)")
                .font(.subheadline)
            if let document = frame.document {
                Text("修订 \(document.revision) · \(document.editorMode) · \(document.selection == nil ? "无选区" : "有选区")")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("屏幕图像坐标，不附加可能错位的文档修订信息。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("图像 \(frame.id.uuidString)").font(.caption2).foregroundStyle(.secondary)
            if let cursor = frame.eventCursor {
                let retained = cursor.journalID == context.observations.journalID
                    && context.observations.entries.contains { $0.sequence == cursor.throughSequence }
                Text("文档状态截至事件 #\(cursor.throughSequence)\(retained ? "" : "（边界事件未保留）")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let image = frame.image.uiImage {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: PrototypeConfiguration.Layout.contextPreviewHeight)
                    .frame(maxWidth: .infinity)
                    .background(.white)
            }
        }
    }
}
