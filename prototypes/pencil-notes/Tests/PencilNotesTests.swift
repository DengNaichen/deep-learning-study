import PencilKit
import XCTest
@testable import PencilNotes

final class SelectionGeometryTests: XCTestCase {
    private let testBounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testReverseDragUsesTopLeftOrigin() {
        let rect = SelectionGeometry.rectangle(from: CGPoint(x: 80, y: 70),
                                                to: CGPoint(x: 20, y: 30), within: testBounds)
        XCTAssertEqual(rect, CGRect(x: 20, y: 30, width: 60, height: 40))
    }

    func testDragClipsToPage() {
        let rect = SelectionGeometry.rectangle(from: CGPoint(x: -20, y: 10),
                                                to: CGPoint(x: 150, y: 80), within: testBounds)
        XCTAssertEqual(rect, CGRect(x: 0, y: 10, width: 100, height: 70))
    }

    func testRejectsTinyAndOutsideSelections() {
        let minimum = PrototypeConfiguration.Page.minimumSelectionSide
        XCTAssertNil(SelectionGeometry.validated(CGRect(x: 0, y: 0, width: minimum / 2, height: minimum)))
        XCTAssertNil(SelectionGeometry.validated(CGRect(x: 110, y: 110, width: 30, height: 30),
                                                within: testBounds))
        XCTAssertNil(SelectionGeometry.rectangle(from: .zero, to: .zero))
    }

    func testMinimumSizeIsAccepted() {
        let minimum = PrototypeConfiguration.Page.minimumSelectionSide
        let rect = CGRect(x: 0, y: 0, width: minimum, height: minimum)
        XCTAssertEqual(SelectionGeometry.validated(rect), rect)
    }

    func testRejectsNonFiniteCoordinates() {
        XCTAssertNil(SelectionGeometry.validated(CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)))
    }
}

@MainActor
final class SnapshotTests: XCTestCase {
    // Fixture values intentionally independent from page configuration.
    private let selection = CGRect(x: 80, y: 80, width: 120, height: 120)
    private let fixtureRevision = 7

    private func fixtureDrawing() -> PKDrawing {
        let positions = [CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 160)]
        let strokeSize = CGSize(width: 6, height: 6)
        let points = positions.map {
            PKStrokePoint(location: $0, timeOffset: 0, size: strokeSize, opacity: 1,
                          force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .black),
                              path: PKStrokePath(controlPoints: points, creationDate: Date()))
        return PKDrawing(strokes: [stroke])
    }

    func testSnapshotHasValidImagesCoordinatesAndRoundTripsJSON() throws {
        let notebookID = UUID()
        let snapshot = try SnapshotBuilder.make(drawing: fixtureDrawing(), notebookID: notebookID,
                                                 revision: fixtureRevision, selection: selection, prompt: "为什么？")
        XCTAssertEqual(snapshot.selection, PageRegion(selection))
        XCTAssertEqual(snapshot.notebookID, notebookID)
        XCTAssertEqual(snapshot.drawingRevision, fixtureRevision)
        XCTAssertEqual(snapshot.coordinateSpace, PrototypeConfiguration.Snapshot.coordinateSpace)
        let crop = try XCTUnwrap(snapshot.selectionImage.uiImage?.cgImage)
        XCTAssertEqual(crop.width, Int(selection.width * PrototypeConfiguration.Snapshot.selectionScale))
        XCTAssertEqual(crop.height, Int(selection.height * PrototypeConfiguration.Snapshot.selectionScale))
        let page = try XCTUnwrap(snapshot.pageImage.uiImage?.cgImage)
        XCTAssertEqual(page.width, Int(PrototypeConfiguration.Page.size.width * PrototypeConfiguration.Snapshot.contextScale))
        XCTAssertEqual(snapshot.selectionImage.mimeType, "image/png")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AssistantRequest.self, from: snapshot.jsonData())
        XCTAssertEqual(decoded.id, snapshot.id)
        XCTAssertEqual(decoded.selectionImage.base64, snapshot.selectionImage.base64)
        XCTAssertEqual(decoded.prompt, "为什么？")
    }

    func testSelectedInkAppearsInCropButInkOutsideDoesNot() throws {
        let drawing = fixtureDrawing()
        let blank = PKDrawing()
        func snapshot(_ drawing: PKDrawing, _ region: CGRect) throws -> AssistantRequest {
            try SnapshotBuilder.make(drawing: drawing, notebookID: UUID(), revision: fixtureRevision,
                                     selection: region, prompt: "测试")
        }
        XCTAssertNotEqual(try snapshot(drawing, selection).selectionImage.base64,
                          try snapshot(blank, selection).selectionImage.base64)
        let outside = CGRect(x: 400, y: 400, width: 120, height: 120)
        XCTAssertEqual(try snapshot(drawing, outside).selectionImage.base64,
                       try snapshot(blank, outside).selectionImage.base64)
    }

    func testInvalidRegionThrows() {
        XCTAssertThrowsError(try SnapshotBuilder.make(drawing: PKDrawing(), notebookID: UUID(),
                                                       revision: fixtureRevision, selection: .zero, prompt: "测试"))
    }

    func testMockExplicitlyDoesNotClaimRecognition() async throws {
        let snapshot = try SnapshotBuilder.make(drawing: fixtureDrawing(), notebookID: UUID(),
                                                 revision: fixtureRevision, selection: selection, prompt: "测试")
        let response = try await MockAssistantClient().respond(to: snapshot)
        XCTAssertTrue(response.contains("未连接模型"))
        XCTAssertTrue(response.contains("不识别笔迹"))
    }
}

@MainActor
final class NotebookPersistenceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDocumentRoundTrip() throws {
        let persistence = NotebookPersistence(url: temporaryDirectory.appending(path: "note.json"))
        XCTAssertNil(try persistence.load())
        let document = NotebookDocument(id: UUID(), revision: 3, drawingData: PKDrawing().dataRepresentation())
        try persistence.save(document)
        let restored = try XCTUnwrap(persistence.load())
        XCTAssertEqual(restored.id, document.id)
        XCTAssertEqual(restored.revision, document.revision)
        XCTAssertEqual(restored.drawingData, document.drawingData)
        XCTAssertNoThrow(try PKDrawing(data: restored.drawingData))
    }

    func testStoreRestoresIdentityAndRevision() throws {
        let url = temporaryDirectory.appending(path: "note.json")
        let store = NotebookStore(fileURL: url)
        store.updateDrawing(PKDrawing())
        store.saveNow()
        let restored = NotebookStore(fileURL: url)
        XCTAssertFalse(restored.loadFailed)
        XCTAssertEqual(restored.notebookID, store.notebookID)
        XCTAssertEqual(restored.revision, store.revision)
    }

    func testCorruptDocumentIsNotOverwritten() throws {
        let url = temporaryDirectory.appending(path: "note.json")
        let original = Data("not a notebook".utf8)
        try original.write(to: url)
        let store = NotebookStore(fileURL: url)
        XCTAssertTrue(store.loadFailed)
        store.updateDrawing(PKDrawing())
        store.saveNow()
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
