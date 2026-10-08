import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onRotation: (CGFloat) -> Void
    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        view.onRotation = onRotation
        return view
    }
    func updateUIView(_ view: PreviewSurface, context: Context) {
        view.onRotation = onRotation
        view.setNeedsLayout()
    }
    final class PreviewSurface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onRotation: ((CGFloat) -> Void)?
        private var previousAngle: CGFloat?
        override func layoutSubviews() {
            super.layoutSubviews()
            let angle: CGFloat
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: angle = 180
            case .landscapeRight: angle = 0
            case .portraitUpsideDown: angle = 270
            default: angle = 90
            }
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if previousAngle != angle {
                previousAngle = angle
                DispatchQueue.main.async { [weak self] in self?.onRotation?(angle) }
            }
        }
    }
}
