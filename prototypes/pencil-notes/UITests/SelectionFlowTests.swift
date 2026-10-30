import XCTest

final class SelectionFlowTests: XCTestCase {
    private enum Fixture {
        static let launchTimeout: TimeInterval = 15
        static let responseTimeout: TimeInterval = 5
        // Allows more than one production sampling interval without changing app behavior for tests.
        static let samplingTimeout: TimeInterval = 15
        static let dragHold: TimeInterval = 0.1
        static let strokeStart = CGVector(dx: 0.25, dy: 0.25)
        static let strokeEnd = CGVector(dx: 0.55, dy: 0.45)
        static let selectionStart = CGVector(dx: 0.15, dy: 0.15)
        static let selectionEnd = CGVector(dx: 0.7, dy: 0.6)
    }

    @MainActor
    func testPeriodicContextRecordingAndInspector() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let toggle = app.buttons["toggleContextRecording"]
        XCTAssertTrue(toggle.waitForExistence(timeout: Fixture.launchTimeout))
        toggle.tap()
        let canvas = app.descendants(matching: .any)["drawingCanvas"].firstMatch
        canvas.coordinate(withNormalizedOffset: Fixture.strokeStart)
            .press(forDuration: Fixture.dragHold,
                   thenDragTo: canvas.coordinate(withNormalizedOffset: Fixture.strokeEnd))
        let inspect = app.buttons["inspectContext"]
        let recorded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "上下文 (2)"),
                                                 object: inspect)
        XCTAssertEqual(XCTWaiter.wait(for: [recorded], timeout: Fixture.samplingTimeout), .completed)
        inspect.tap()
        let count = app.staticTexts["contextHistoryCount"]
        XCTAssertTrue(count.waitForExistence(timeout: Fixture.responseTimeout))
        XCTAssertTrue(count.label.contains("2 帧"))
        app.segmentedControls["contextSection"].buttons["事件"].tap()
        XCTAssertTrue(app.staticTexts["observationCount"].waitForExistence(timeout: Fixture.responseTimeout))
        XCTAssertTrue(app.buttons["exportObservations"].exists)
        XCTAssertTrue(app.staticTexts["observation-captureStarted"].firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Local context inspector"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["完成"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: Fixture.responseTimeout))
        XCTAssertEqual(toggle.label, "开始记录", "Inspecting must stop recording; no automatic resume")
    }

    @MainActor
    func testWriteSelectPreviewAndMockReply() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        let canvas = app.descendants(matching: .any)["drawingCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: Fixture.launchTimeout))
        canvas.coordinate(withNormalizedOffset: Fixture.strokeStart)
            .press(forDuration: Fixture.dragHold,
                   thenDragTo: canvas.coordinate(withNormalizedOffset: Fixture.strokeEnd))

        let preview = app.buttons["previewSelection"]
        XCTAssertFalse(preview.isEnabled)
        app.segmentedControls.buttons["框选"].tap()
        let overlay = app.descendants(matching: .any)["selectionOverlay"].firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: Fixture.responseTimeout))
        overlay.coordinate(withNormalizedOffset: Fixture.selectionStart)
            .press(forDuration: Fixture.dragHold,
                   thenDragTo: overlay.coordinate(withNormalizedOffset: Fixture.selectionEnd))
        XCTAssertTrue(preview.isEnabled)

        // Rotation must preserve the selected page region, not reinterpret screen coordinates.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(preview.isEnabled)
        preview.tap()
        XCTAssertTrue(app.buttons["sendToMock"].waitForExistence(timeout: Fixture.responseTimeout))
        let previewAttachment = XCTAttachment(screenshot: app.screenshot())
        previewAttachment.name = "Selection request preview"
        previewAttachment.lifetime = .keepAlways
        add(previewAttachment)
        app.buttons["sendToMock"].tap()
        let reply = app.staticTexts["assistantReply"]
        XCTAssertTrue(reply.waitForExistence(timeout: Fixture.responseTimeout))
        XCTAssertTrue(reply.label.contains("未连接模型"))
        XCTAssertFalse(reply.label.contains("修订 0"), "The handwriting gesture must produce a drawing revision")
        app.buttons["完成"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: Fixture.responseTimeout))
        XCUIDevice.shared.orientation = .portrait
    }
}
