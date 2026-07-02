import AVFoundation
import Vision
import CoreGraphics
import Combine

/// Captures camera frames and runs a Vision hand-pose request on each one,
/// publishing the most recent set of normalized joint points.
final class HandPoseCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // Published, normalized to 0...1 with (0,0) at top-left of the *mirrored* preview.
    @Published var indexTip: CGPoint?
    @Published var wrist: CGPoint?
    @Published var handDetected: Bool = false
    @Published var fingerExtension: FingerExtension = .init()
    @Published var running: Bool = false
    @Published var availableCameras: [AVCaptureDevice] = []

    struct FingerExtension {
        var thumb = false, index = false, middle = false, ring = false, little = false
        var pinch = false   // thumb tip + index tip pressed together (🤏)
        var extendedCount: Int { [thumb, index, middle, ring, little].filter { $0 }.count }
    }

    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "hand.video.queue")
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()
    private var currentInput: AVCaptureDeviceInput?

    // Temporal majority voting over recent frames, so a single mis-read frame
    // can't flip the detected pose. Accessed only on `videoQueue`.
    private var extHistory: [FingerExtension] = []
    private let voteWindow = 5

    var previewSession: AVCaptureSession { session }

    override init() {
        super.init()
        refreshCameras()
    }

    func refreshCameras() {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.external)
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        DispatchQueue.main.async { self.availableCameras = discovery.devices }
    }

    func start(device: AVCaptureDevice?) {
        videoQueue.async {
            self.session.beginConfiguration()
            // Hand-pose inference doesn't need HD input; 640×480 keeps Vision fast
            // enough to process (near) every frame, which directly smooths scrolling.
            self.session.sessionPreset = self.session.canSetSessionPreset(.vga640x480)
                ? .vga640x480 : .high

            // Swap input if needed.
            if let existing = self.currentInput {
                self.session.removeInput(existing)
                self.currentInput = nil
            }
            let cam = device ?? AVCaptureDevice.default(for: .video)
            guard let cam, let input = try? AVCaptureDeviceInput(device: cam),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.currentInput = input

            // Output (add once).
            if self.session.outputs.isEmpty {
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.videoQueue)
                if self.session.canAddOutput(output) { self.session.addOutput(output) }
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.running = true }
        }
    }

    func stop() {
        videoQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.running = false
                self.handDetected = false
                self.indexTip = nil
            }
        }
    }

    // MARK: - Frame processing

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            guard let obs = request.results?.first else {
                extHistory.removeAll()   // reset voting once the hand is gone
                DispatchQueue.main.async {
                    self.handDetected = false
                    self.indexTip = nil
                }
                return
            }
            try process(obs)
        } catch {
            // Silently ignore per-frame failures.
        }
    }

    private func process(_ obs: VNHumanHandPoseObservation) throws {
        func pt(_ name: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let p = try? obs.recognizedPoint(name), p.confidence > 0.4 else { return nil }
            // Vision: origin bottom-left. Flip Y so up is up. Mirror X for selfie-style feel.
            return CGPoint(x: 1 - p.location.x, y: 1 - p.location.y)
        }

        let tip = pt(.indexTip)
        let wristPt = pt(.wrist)

        // A finger is "extended" only when its tip is clearly beyond the knuckle
        // (MCP) measured from the wrist, AND not folded back past its PIP joint.
        // The MCP reference + margin is far more robust than a bare tip-vs-PIP
        // ratio, which flagged half-curled fingers.
        func extended(tip tName: VNHumanHandPoseObservation.JointName,
                      pip pName: VNHumanHandPoseObservation.JointName,
                      mcp mName: VNHumanHandPoseObservation.JointName) -> Bool {
            guard let w = wristPt,
                  let t = pt(tName),
                  let m = pt(mName) else { return false }
            let knuckle = dist(m, w)
            guard knuckle > 0.01 else { return false }
            if let p = pt(pName), dist(t, w) < dist(p, w) { return false } // curled
            return dist(t, w) > knuckle * 1.2
        }

        var ext = FingerExtension()
        ext.index  = extended(tip: .indexTip,  pip: .indexPIP,  mcp: .indexMCP)
        ext.middle = extended(tip: .middleTip, pip: .middlePIP, mcp: .middleMCP)
        ext.ring   = extended(tip: .ringTip,   pip: .ringPIP,   mcp: .ringMCP)
        ext.little = extended(tip: .littleTip, pip: .littlePIP, mcp: .littleMCP)
        // Thumb is the least reliable joint and is intentionally NOT used by the
        // gesture recognizer; left false to avoid polluting the finger count.

        // Pinch: thumb tip and index tip close together, measured relative to the
        // palm size so it works regardless of distance from the camera.
        if let thumbT = pt(.thumbTip), let idxT = tip, let idxMCP = pt(.indexMCP), let w = wristPt {
            let palm = dist(w, idxMCP)
            ext.pinch = palm > 0.01 && dist(thumbT, idxT) < palm * 0.6
        }

        // Majority-vote each finger over the last few frames.
        extHistory.append(ext)
        if extHistory.count > voteWindow { extHistory.removeFirst() }
        let history = extHistory
        func vote(_ key: (FingerExtension) -> Bool) -> Bool {
            history.filter(key).count * 2 > history.count
        }
        var smoothed = FingerExtension()
        smoothed.index  = vote { $0.index }
        smoothed.middle = vote { $0.middle }
        smoothed.ring   = vote { $0.ring }
        smoothed.little = vote { $0.little }
        smoothed.pinch  = vote { $0.pinch }

        DispatchQueue.main.async {
            self.handDetected = true
            self.indexTip = tip
            self.wrist = wristPt
            self.fingerExtension = smoothed
        }
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
