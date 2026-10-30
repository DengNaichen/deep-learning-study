import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .png, .plainText] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct RequestPreview: View {
    let request: AssistantRequest
    let client: any AssistantClient
    @Environment(\.dismiss) private var dismiss
    @State private var reply: String?
    @State private var isSending = false
    @State private var responseTask: Task<Void, Never>?
    @State private var exportDocument: ExportDocument?
    @State private var exportType: UTType = .json
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PrototypeConfiguration.Layout.spacing) {
                    Label("本地模拟：不会上传到模型服务", systemImage: "lock.shield")
                        .font(.headline)
                    Text("请求包含选区图片、整页图片、选区坐标和问题。导出 JSON 也包含整页内容，请确认后再分享。")
                        .font(.callout).foregroundStyle(.secondary)

                    Text("选区快照").font(.headline)
                    if let image = request.selectionImage.uiImage {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity,
                                   maxHeight: PrototypeConfiguration.Layout.previewHeight)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: PrototypeConfiguration.Layout.cornerRadius))
                            .accessibilityIdentifier("selectionPreview")
                    }
                    Text("位置（页内点）：\(Int(request.selection.x)), \(Int(request.selection.y)) · 大小：\(Int(request.selection.width)) × \(Int(request.selection.height))")
                        .font(.caption).monospacedDigit()
                    DisclosureGroup("整页上下文（蓝框仅用于预览）") {
                        if let image = request.pageImage.uiImage {
                            Image(uiImage: image).resizable().scaledToFit()
                                .overlay {
                                    GeometryReader { geometry in
                                        let scale = geometry.size.width / request.page.width
                                        Rectangle()
                                            .stroke(.blue, lineWidth: PrototypeConfiguration.Layout.selectionOutlineWidth)
                                            .frame(width: request.selection.width * scale,
                                                   height: request.selection.height * scale)
                                            .position(x: (request.selection.x + request.selection.width / 2) * scale,
                                                      y: (request.selection.y + request.selection.height / 2) * scale)
                                    }
                                }
                                .frame(maxHeight: PrototypeConfiguration.Layout.contextPreviewHeight)
                        }
                    }
                    Text("问题").font(.headline)
                    Text(request.prompt).textSelection(.enabled)
                    Text("修订 \(request.drawingRevision) · 请求 \(request.id.uuidString)")
                        .font(.caption).foregroundStyle(.secondary)

                    Button(action: send) {
                        Label(isSending ? "正在模拟…" : "发送给本地模拟助手", systemImage: "paperplane")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending)
                    .accessibilityIdentifier("sendToMock")

                    if let reply {
                        Text(reply).textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: PrototypeConfiguration.Layout.cornerRadius))
                            .accessibilityIdentifier("assistantReply")
                    }
                    HStack {
                        Button("导出请求 JSON") { prepareExport(type: .json) }
                        Button("导出选区 PNG") { prepareExport(type: .png) }
                    }
                    .buttonStyle(.bordered)
                    Text("这是点击预览时的固定快照，不会随之后的笔迹变化。关闭预览后可继续书写。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("提交前预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fileExporter(isPresented: $isExporting, document: exportDocument,
                          contentType: exportType,
                          defaultFilename: "selection-\(request.id.uuidString)") { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onDisappear { responseTask?.cancel() }
        }
    }

    private func send() {
        responseTask?.cancel()
        isSending = true
        reply = nil
        responseTask = Task { @MainActor in
            defer { isSending = false }
            do {
                let response = try await client.respond(to: request)
                try Task.checkCancellation()
                reply = response
            } catch is CancellationError {
                // Closing the preview cancels its request without displaying an error.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func prepareExport(type: UTType) {
        do {
            let data: Data
            if type == .png {
                guard let png = Data(base64Encoded: request.selectionImage.base64) else {
                    throw SnapshotError.encodingFailed
                }
                data = png
            } else {
                data = try request.jsonData()
            }
            exportDocument = ExportDocument(data: data)
            exportType = type
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
