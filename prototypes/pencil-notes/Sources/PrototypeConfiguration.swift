import CoreGraphics
import Foundation

/// Tunable prototype defaults. Page points are document coordinates, not device pixels.
enum PrototypeConfiguration {
    enum Page {
        // A fixed 3:4 document keeps selection coordinates stable across device rotation.
        static let size = CGSize(width: 768, height: 1024)
        static let bounds = CGRect(origin: .zero, size: size)
        static let minimumSelectionSide: CGFloat = 12
    }

    enum Ink {
        static let penWidth: CGFloat = 3
    }

    enum Snapshot {
        // Higher resolution for the selected detail; smaller full-page context to limit payload size.
        static let selectionScale: CGFloat = 2
        static let contextScale: CGFloat = 1
        static let schemaVersion = 1
        static let coordinateSpace = "page_points_top_left_x_right_y_down"
    }

    enum Context {
        // Check the document / accept at most one ReplayKit video sample per interval.
        static let samplingIntervalSeconds: TimeInterval = 5
        static let maximumFrames = 12
        // Budget counts base64 bytes; transient rendering/export allocations are additional.
        static let maximumBase64Bytes = 16 * 1_024 * 1_024 // 16 MiB
        static let maximumAgeSeconds: TimeInterval = 600 // Keep at most ten minutes.
        static let screenMaximumPixelEdge: CGFloat = 1024
        static let screenJPEGQuality: CGFloat = 0.75
        // Context v2 adds the observation journal and document-frame event cursors.
        static let schemaVersion = 2
        static let observationSchemaVersion = 1
        static let maximumObservationEntries = 256
        static let kind = "learning_context"
    }

    enum Timing {
        static let saveDebounce: Duration = .milliseconds(400)
        static let mockResponseDelay: Duration = .milliseconds(400)
    }

    enum Layout {
        static let spacing: CGFloat = 16
        static let compactSpacing: CGFloat = 8
        static let pageMargin: CGFloat = 16
        static let cornerRadius: CGFloat = 12
        static let selectionLineWidth: CGFloat = 2
        static let selectionDash: [NSNumber] = [8, 4]
        static let selectionFillOpacity: CGFloat = 0.08
        static let previewHeight: CGFloat = 240
        static let contextPreviewHeight: CGFloat = 300
        static let selectionOutlineWidth: CGFloat = 2
        static let minimumEditorHeight: CGFloat = 360
    }
}
