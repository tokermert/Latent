import AVFoundation
import Foundation

enum CameraFailure: LocalizedError {
    case unavailable, configuration, notRunning, emptyPhoto, permission, interrupted
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Kamera bulunamadı. Kamera ve haptic testi için gerçek bir iPhone kullan."
        case .configuration: return "Kamera hazırlanamadı. Tekrar deneyebilirsin."
        case .notRunning: return "Kamera henüz çekime hazır değil."
        case .emptyPhoto: return "Kameradan fotoğraf alınamadı."
        case .permission: return "Fotoğraf çekmek için Ayarlar’dan Latent’e kamera izni ver."
        case .interrupted: return "Kamera geçici olarak kullanılamıyor. Tekrar deneyebilirsin."
        }
    }
}

/// All mutable capture state and session operations are confined to `queue`.
final class CameraService: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.latent.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var delegates: [Int64: PhotoDelegate] = [:]

    /// 12 MP class (4032 × 3024 ≈ 12.2 MP, with a small margin). 48 MP sensors also offer
    /// 24/48 MP, but every frame is kept as three JPEG variants and decoded in memory for
    /// cropping, so 12 MP is the default.
    private static let targetPhotoPixels: Int64 = 12_600_000

    /// Returns the capture device so the UI can build a rotation coordinator for it.
    func start() async throws -> AVCaptureDevice {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVCaptureDevice, Error>) in
            queue.async { [self] in
                do {
                    if !configured { try configure() }
                    if !session.isRunning { session.startRunning() }
                    guard session.isRunning else { throw CameraFailure.notRunning }
                    guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { throw CameraFailure.configuration }
                    continuation.resume(returning: device)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CameraFailure.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw CameraFailure.configuration }
        session.addInput(input)
        guard session.canAddOutput(output) else { session.removeInput(input); throw CameraFailure.configuration }
        session.addOutput(output)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = 1
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        } catch {
            session.removeOutput(output); session.removeInput(input); throw error
        }
        output.maxPhotoQualityPrioritization = .balanced
        let pixels = { (d: CMVideoDimensions) in Int64(d.width) * Int64(d.height) }
        let supported = device.activeFormat.supportedMaxPhotoDimensions.sorted { pixels($0) < pixels($1) }
        // Largest size not above ~12 MP; if the format only offers bigger sizes, the smallest of them.
        if let dimensions = supported.last(where: { pixels($0) <= Self.targetPhotoPixels }) ?? supported.first {
            output.maxPhotoDimensions = dimensions
        }
        configured = true
    }

    func capture(rotation: CGFloat) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard session.isRunning else { continuation.resume(throwing: CameraFailure.notRunning); return }
                guard output.availablePhotoCodecTypes.contains(.jpeg) else { continuation.resume(throwing: CameraFailure.configuration); return }
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(rotation) {
                    connection.videoRotationAngle = rotation
                }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.maxPhotoDimensions = output.maxPhotoDimensions
                settings.photoQualityPrioritization = .balanced
                settings.flashMode = .off
                let id = settings.uniqueID
                let delegate = PhotoDelegate { [weak self] result in
                    self?.queue.async { self?.delegates.removeValue(forKey: id) }
                    continuation.resume(with: result)
                }
                delegates[id] = delegate
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var result: Result<Data, Error> = .failure(CameraFailure.emptyPhoto)
    private let completion: (Result<Data, Error>) -> Void
    init(completion: @escaping (Result<Data, Error>) -> Void) { self.completion = completion }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { result = .failure(error) }
        else if let data = photo.fileDataRepresentation() { result = .success(data) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completion(error.map { .failure($0) } ?? result)
    }
}
