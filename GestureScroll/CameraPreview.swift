import SwiftUI
import AVFoundation

/// Live camera preview, mirrored to match the user's mental model.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        if let conn = v.previewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
        return v
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.session = session
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(previewLayer)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }
}
