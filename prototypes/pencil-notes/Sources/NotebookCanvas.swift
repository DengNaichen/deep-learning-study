import PencilKit
import SwiftUI
import UIKit

struct NotebookCanvas: UIViewRepresentable {
    @ObservedObject var store: NotebookStore

    func makeUIView(context: Context) -> NotebookSurface {
        let surface = NotebookSurface()
        surface.onDrawingChanged = { [weak store] in store?.updateDrawing($0) }
        surface.onSelectionChanged = { [weak store] in store?.selection = $0 }
        surface.onToolUseChanged = { [weak store] in store?.isUsingDrawingTool = $0 }
        return surface
    }

    func updateUIView(_ surface: NotebookSurface, context: Context) {
        surface.apply(drawing: store.drawing, mode: store.mode, selection: store.selection)
    }
}

/// The page is a fixed-size coordinate space fitted into the available viewport.
/// Both PencilKit and the selection overlay share that transform, avoiding screen/page drift.
final class NotebookSurface: UIView, PKCanvasViewDelegate {
    var onDrawingChanged: ((PKDrawing) -> Void)?
    var onSelectionChanged: ((CGRect?) -> Void)?
    var onToolUseChanged: ((Bool) -> Void)?

    private let page = UIView()
    private let canvas = PKCanvasView()
    private let selectionOverlay = SelectionOverlay()
    private var isApplyingDrawing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        page.backgroundColor = .white
        page.clipsToBounds = true
        // Black ink on white paper even when the surrounding app uses dark mode.
        page.overrideUserInterfaceStyle = .light
        addSubview(page)
        page.addSubview(canvas)
        page.addSubview(selectionOverlay)

        canvas.delegate = self
        canvas.backgroundColor = .white
        canvas.drawingPolicy = .anyInput
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.contentSize = PrototypeConfiguration.Page.size
        canvas.accessibilityIdentifier = "drawingCanvas"
        canvas.accessibilityLabel = "手写笔记画布"
        selectionOverlay.onSelectionChanged = { [weak self] in self?.onSelectionChanged?($0) }
    }

    required init?(coder: NSCoder) { fatalError("Storyboard initialization is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pageSize = PrototypeConfiguration.Page.size
        let inset = PrototypeConfiguration.Layout.pageMargin
        let available = bounds.insetBy(dx: inset, dy: inset)
        guard available.width > 0, available.height > 0 else { return }
        let scale = min(available.width / pageSize.width, available.height / pageSize.height)
        page.bounds = PrototypeConfiguration.Page.bounds
        page.center = CGPoint(x: bounds.midX, y: bounds.midY)
        page.transform = CGAffineTransform(scaleX: scale, y: scale)
        canvas.frame = page.bounds
        selectionOverlay.frame = page.bounds
    }

    func apply(drawing: PKDrawing, mode: EditorMode, selection: CGRect?) {
        if canvas.drawing != drawing {
            isApplyingDrawing = true
            canvas.drawing = drawing
            isApplyingDrawing = false
        }
        switch mode {
        case .pen:
            canvas.tool = PKInkingTool(.pen, color: .black, width: PrototypeConfiguration.Ink.penWidth)
        case .eraser:
            canvas.tool = PKEraserTool(.vector)
        case .select:
            break
        }
        selectionOverlay.isHidden = mode != .select
        canvas.isUserInteractionEnabled = mode != .select
        selectionOverlay.selection = selection
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { onToolUseChanged?(true) }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { onToolUseChanged?(false) }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing else { return }
        onDrawingChanged?(canvasView.drawing)
    }
}

final class SelectionOverlay: UIView {
    var onSelectionChanged: ((CGRect?) -> Void)?
    var selection: CGRect? { didSet { updateOutline() } }

    private let outline = CAShapeLayer()
    private var dragStart: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityIdentifier = "selectionOverlay"
        accessibilityLabel = "框选区域：在页面上拖动以选择"
        outline.strokeColor = UIColor.systemBlue.cgColor
        outline.fillColor = UIColor.systemBlue
            .withAlphaComponent(PrototypeConfiguration.Layout.selectionFillOpacity).cgColor
        outline.lineWidth = PrototypeConfiguration.Layout.selectionLineWidth
        outline.lineDashPattern = PrototypeConfiguration.Layout.selectionDash
        layer.addSublayer(outline)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
    }

    required init?(coder: NSCoder) { fatalError("Storyboard initialization is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        outline.frame = bounds
        updateOutline()
    }

    private func updateOutline() {
        // No implicit animation: the outline follows the gesture immediately.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.path = selection.map { UIBezierPath(rect: $0).cgPath }
        CATransaction.commit()
    }

    @objc private func drag(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            // A pan starts after movement; subtract translation to recover the touch-down point.
            let translation = recognizer.translation(in: self)
            dragStart = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            selection = nil
            onSelectionChanged?(nil)
        case .changed, .ended:
            guard let dragStart else { return }
            selection = SelectionGeometry.rectangle(from: dragStart, to: location)
            if recognizer.state == .ended {
                self.dragStart = nil
                onSelectionChanged?(selection)
            }
        case .cancelled, .failed:
            dragStart = nil
            selection = nil
            onSelectionChanged?(nil)
        default:
            break
        }
    }
}
