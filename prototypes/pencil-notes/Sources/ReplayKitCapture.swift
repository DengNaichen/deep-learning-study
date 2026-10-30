import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ReplayKit
import UniformTypeIdentifiers

/// Monotonic gate: skipped frames are never queued for later processing.
struct SampleGate {
    let interval: TimeInterval
    private var lastAcceptedTime: TimeInterval?

    init(interval: TimeInterval) { self.interval = interval }

    mutating func accept(at time: TimeInterval) -> Bool {
        if let lastAcceptedTime, time - lastAcceptedTime < interval { return false }
        lastAcceptedTime = time
        return true
    }
}

enum ScreenFrameEncoder {
    static func encode(_ image: CIImage, orientation: CGImagePropertyOrientation,
                       context: CIContext) throws -> RequestImage {
        let oriented = image.oriented(orientation)
        let longestEdge = max(oriented.extent.width, oriented.extent.height)
        guard longestEdge.isFinite, longestEdge > 0 else { throw SnapshotError.encodingFailed }
        // Normalize orientation into the pixels; exported JPEGs require no EXIF rotation handling.
        let scale = min(1, PrototypeConfiguration.Context.screenMaximumPixelEdge / longestEdge)
        let normalized = oriented.transformed(by: CGAffineTransform(
            translationX: -oriented.extent.minX, y: -oriented.extent.minY
        )).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(normalized, from: normalized.extent.integral) else {
            throw SnapshotError.encodingFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw SnapshotError.encodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: PrototypeConfiguration.Context.screenJPEGQuality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw SnapshotError.encodingFailed }
        return RequestImage(mimeType: "image/jpeg", widthPixels: cgImage.width, heightPixels: cgImage.height,
                            base64: (output as Data).base64EncodedString())
    }
}

/// ReplayKit callbacks need not arrive on the main thread. The lock protects all mutable state,
/// admits only one conversion at a time, and prevents unbounded frame/task queues.
final class ScreenSampleProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var enabled = true
    private var acceptingFrames = false
    private var gate = SampleGate(interval: PrototypeConfiguration.Context.samplingIntervalSeconds)

    func setAcceptingFrames(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        acceptingFrames = value
    }

    func disable() {
        lock.lock()
        defer { lock.unlock() }
        enabled = false
    }

    func consume(_ sample: CMSampleBuffer) throws -> ContextFrame? {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, acceptingFrames, CMSampleBufferIsValid(sample),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sample),
              gate.accept(at: ProcessInfo.processInfo.systemUptime) else { return nil }
        let capturedAt = Date()
        let value = CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString,
                                    attachmentModeOut: nil) as? NSNumber
        let orientation = value.flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
        let image = try ScreenFrameEncoder.encode(CIImage(cvPixelBuffer: pixelBuffer),
                                                   orientation: orientation, context: context)
        return ContextFrame(id: UUID(), capturedAt: capturedAt, source: .replayKitApp,
                            image: image, document: nil)
    }
}

enum ReplayCaptureError: LocalizedError {
    case unavailable
    case alreadyRecording

    var errorDescription: String? {
        switch self {
        case .unavailable: return "此环境的 ReplayKit 当前不可用。请在真机上测试，或改用“笔记内容”。"
        case .alreadyRecording: return "设备已有录制会话；请先结束它，再开始本 App 的采集。"
        }
    }
}

/// App-local capture only. A cross-app broadcast would require a different extension architecture.
/// Kept behind one adapter: Xcode 27 SDK marks ReplayKit deprecated in favor of ScreenCaptureKit.
@MainActor
final class ReplayKitCapture: NSObject, RPScreenRecorderDelegate {
    private let recorder = RPScreenRecorder.shared()
    private var processor: ScreenSampleProcessor?
    private var failureHandler: ((String) -> Void)?

    func start(onFrame: @escaping @MainActor (ContextFrame) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        guard recorder.isAvailable else { throw ReplayCaptureError.unavailable }
        guard !recorder.isRecording else { throw ReplayCaptureError.alreadyRecording }
        let processor = ScreenSampleProcessor()
        self.processor = processor
        failureHandler = onFailure
        recorder.delegate = self
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                recorder.startCapture(handler: { sample, type, error in
                    if let error {
                        processor.disable()
                        Task { @MainActor in onFailure(error.localizedDescription) }
                        return
                    }
                    // App audio samples can still be supplied; never process, store or export them.
                    guard type == .video else { return }
                    do {
                        if let frame = try processor.consume(sample) {
                            Task { @MainActor in onFrame(frame) }
                        }
                    } catch {
                        processor.disable()
                        Task { @MainActor in onFailure(error.localizedDescription) }
                    }
                }, completionHandler: { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
        } catch {
            processor.disable()
            self.processor = nil
            recorder.delegate = nil
            failureHandler = nil
            throw error
        }
    }

    func setAcceptingFrames(_ value: Bool) { processor?.setAcceptingFrames(value) }

    func stop() async throws {
        processor?.disable()
        processor = nil
        failureHandler = nil
        defer { recorder.delegate = nil }
        guard recorder.isRecording else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.stopCapture { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    nonisolated func screenRecorder(_ screenRecorder: RPScreenRecorder,
                                   didStopRecordingWith previewViewController: RPPreviewViewController?,
                                   error: Error?) {
        Task { @MainActor [weak self] in
            self?.failureHandler?(error?.localizedDescription ?? "系统已结束屏幕采集。")
        }
    }

    nonisolated func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        Task { @MainActor [weak self] in
            guard let self, !self.recorder.isAvailable else { return }
            self.failureHandler?("ReplayKit 已变为不可用，采集已停止。")
        }
    }
}
