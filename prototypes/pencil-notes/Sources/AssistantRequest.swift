import Foundation
import PencilKit
import UIKit

struct PageRegion: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = Double(rect.minX)
        y = Double(rect.minY)
        width = Double(rect.width)
        height = Double(rect.height)
    }
}

struct RequestImage: Codable, Sendable {
    let mimeType: String
    let widthPixels: Int
    let heightPixels: Int
    let base64: String

    var uiImage: UIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}

/// Immutable snapshot: both images, coordinates and revision refer to the same drawing.
/// Contains the whole page as context. Never send it without showing that scope to the user.
struct AssistantRequest: Codable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let notebookID: UUID
    let drawingRevision: Int
    let createdAt: Date
    let prompt: String
    let coordinateSpace: String
    let page: PageRegion
    let selection: PageRegion
    let selectionImage: RequestImage
    let pageImage: RequestImage

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

enum SnapshotError: LocalizedError {
    case invalidSelection
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidSelection:
            let minimum = Int(PrototypeConfiguration.Page.minimumSelectionSide)
            return "请在页面内框选至少 \(minimum) × \(minimum) 点的区域。"
        case .encodingFailed: return "无法生成选区图片。"
        }
    }
}

@MainActor
enum SnapshotBuilder {
    static func make(drawing: PKDrawing, notebookID: UUID, revision: Int,
                     selection: CGRect, prompt: String) throws -> AssistantRequest {
        guard let region = SelectionGeometry.validated(selection) else {
            throw SnapshotError.invalidSelection
        }
        return AssistantRequest(
            schemaVersion: PrototypeConfiguration.Snapshot.schemaVersion, id: UUID(), notebookID: notebookID,
            drawingRevision: revision, createdAt: Date(), prompt: prompt,
            coordinateSpace: PrototypeConfiguration.Snapshot.coordinateSpace,
            page: PageRegion(PrototypeConfiguration.Page.bounds), selection: PageRegion(region),
            selectionImage: try render(drawing: drawing, rect: region,
                                       scale: PrototypeConfiguration.Snapshot.selectionScale),
            pageImage: try render(drawing: drawing, rect: PrototypeConfiguration.Page.bounds,
                                  scale: PrototypeConfiguration.Snapshot.contextScale)
        )
    }

    static func documentImage(drawing: PKDrawing) throws -> RequestImage {
        try render(drawing: drawing, rect: PrototypeConfiguration.Page.bounds,
                   scale: PrototypeConfiguration.Snapshot.contextScale)
    }

    private static func render(drawing: PKDrawing, rect: CGRect, scale: CGFloat) throws -> RequestImage {
        // Render the document, not the device screen: no selection border, toolbar or keyboard.
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let ink = drawing.image(from: rect, scale: scale)
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            ink.draw(in: CGRect(origin: .zero, size: rect.size))
        }
        guard let data = image.pngData(), let cgImage = image.cgImage else {
            throw SnapshotError.encodingFailed
        }
        return RequestImage(mimeType: "image/png", widthPixels: cgImage.width,
                            heightPixels: cgImage.height, base64: data.base64EncodedString())
    }
}

/// Replace this implementation later with a backend adapter. No API keys belong in the app.
protocol AssistantClient: Sendable {
    func respond(to request: AssistantRequest) async throws -> String
}

struct MockAssistantClient: AssistantClient {
    func respond(to request: AssistantRequest) async throws -> String {
        try await Task.sleep(for: PrototypeConfiguration.Timing.mockResponseDelay)
        return """
        【本地模拟回执 · 未连接模型】
        收到笔记修订 \(request.drawingRevision) 的快照。
        选区：x=\(Int(request.selection.x)), y=\(Int(request.selection.y)), \(Int(request.selection.width)) × \(Int(request.selection.height)) 点。
        选区 PNG：\(request.selectionImage.widthPixels) × \(request.selectionImage.heightPixels) 像素。
        同时收到整页 PNG 和你的问题：“\(request.prompt)”

        此回执只验证数据链路，不识别笔迹，也不判断推导。没有发生网络请求。
        """
    }
}
