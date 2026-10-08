import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Angle from `AVCaptureDevice.RotationCoordinator`; nil until the coordinator exists.
    let rotationAngle: CGFloat?
    /// Called with the preview layer so the owner can build a rotation coordinator for it.
    let onLayer: (AVCaptureVideoPreviewLayer) -> Void
    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        view.rotationAngle = rotationAngle
        let layer = view.preview
        DispatchQueue.main.async { onLayer(layer) }
        return view
    }
    func updateUIView(_ view: PreviewSurface, context: Context) {
        view.rotationAngle = rotationAngle
    }
    final class PreviewSurface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var rotationAngle: CGFloat? { didSet { if rotationAngle != oldValue { applyRotation() } } }
        override func layoutSubviews() {
            super.layoutSubviews()
            // The connection may appear only after the session gains its input.
            applyRotation()
        }
        private func applyRotation() {
            guard let angle = rotationAngle ?? interfaceAngle, let connection = preview.connection,
                  connection.videoRotationAngle != angle, connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
        /// Fallback while the coordinator is not ready (back camera, landscape-native sensor).
        private var interfaceAngle: CGFloat? {
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: return 180
            case .landscapeRight: return 0
            case .portraitUpsideDown: return 270
            case .portrait: return 90
            default: return nil
            }
        }
    }
}
