import SwiftUI
import AVFoundation
import Combine

@MainActor
final class CameraModel: ObservableObject {
    let service = CameraService()
    @Published var ready = false
    @Published var capturing = false
    /// Camera problems (permission, interruption, capture). Cleared when the camera restarts.
    @Published var errorMessage: String?
    @Published var permissionDenied = false
    /// A processed photo that is not saved yet; kept until a save succeeds.
    @Published var pending: ProcessedCapture?
    /// Why `pending` is not saved. Separate from `errorMessage` so a camera restart or
    /// interruption cannot hide the retry for an unsaved photo.
    @Published var saveErrorMessage: String?
    /// Ratio the next photo will be saved with, following the device orientation.
    @Published private(set) var captureOrientation: FrameOrientation = .portrait
    /// Rotation for the live preview connection, from the rotation coordinator.
    @Published private(set) var previewAngle: CGFloat?
    let haptic = UIImpactFeedbackGenerator(style: .rigid)
    private var generation = 0
    private var observations: Set<AnyCancellable> = []
    private var device: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []
    /// Last horizon-level capture angle. The coordinator follows the physical (gravity)
    /// orientation, so this is right even with portrait lock on. Only multiples of 90 are
    /// accepted, so a face-up/face-down phone keeps the last valid value.
    private var captureAngle: CGFloat = 90
    /// The session is stopped only after an in-flight capture, so leaving the app right after
    /// pressing the shutter does not abort the photo.
    private var stopAfterCapture = false

    init() {
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            NotificationCenter.default.publisher(for: name, object: service.session).sink { [weak self] _ in
                Task { @MainActor in self?.ready = false; self?.errorMessage = CameraFailure.interrupted.localizedDescription }
            }.store(in: &observations)
        }
        NotificationCenter.default.publisher(for: AVCaptureSession.interruptionEndedNotification, object: service.session).sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.ready = self.service.session.isRunning
                // Clear the interruption notice; an unsaved photo keeps its own message.
                if self.ready { self.errorMessage = nil }
            }
        }.store(in: &observations)
        // Nothing large is cached on the camera side except an unsaved photo, so the best
        // relief is getting it onto disk.
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification).sink { [weak self] _ in
            Task { @MainActor in await self?.retryPendingSave() }
        }.store(in: &observations)
    }

    func start() async {
        generation += 1
        let token = generation
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard token == generation else { return }
        guard authorized else { permissionDenied = true; errorMessage = CameraFailure.permission.localizedDescription; return }
        permissionDenied = false; errorMessage = nil; stopAfterCapture = false
        do {
            let device = try await service.start()
            guard token == generation else { return }
            if device !== self.device { self.device = device; makeRotationCoordinator() }
            ready = true; haptic.prepare()
        } catch { if token == generation { errorMessage = error.localizedDescription; ready = false } }
    }

    func stop() {
        generation += 1; ready = false
        if capturing { stopAfterCapture = true } else { service.stop() }
    }

    /// Called when the scene goes to the background: one more save attempt for an unsaved
    /// photo, with background time so it can finish. A failure stays visible on return.
    func enteredBackground() {
        guard pending != nil else { return }
        Task { await retryPendingSave() }
    }

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        guard previewLayer !== self.previewLayer else { return }
        self.previewLayer = previewLayer
        makeRotationCoordinator()
    }

    /// Needs both the device and the on-screen preview layer. The layer normally lives as long
    /// as the camera screen; if SwiftUI ever recreates it, the coordinator is rebuilt.
    private func makeRotationCoordinator() {
        rotationObservations = []
        rotationCoordinator = nil
        previewAngle = nil
        guard let device, let previewLayer else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        // AVFoundation delivers these KVO changes on the main queue.
        rotationObservations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                Task { @MainActor in
                    guard let self, coordinator === self.rotationCoordinator, let angle = Self.quarterTurn(angle) else { return }
                    self.captureAngle = angle
                    let orientation = self.frameOrientation(for: angle)
                    if orientation != self.captureOrientation { self.captureOrientation = orientation }
                }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                Task { @MainActor in
                    guard let self, coordinator === self.rotationCoordinator, let angle = Self.quarterTurn(angle) else { return }
                    self.previewAngle = angle
                }
            }
        ]
    }

    /// Normalizes to 0/90/180/270; anything else is ignored.
    nonisolated private static func quarterTurn(_ angle: CGFloat) -> CGFloat? {
        guard angle.isFinite else { return nil }
        let turns = (angle / 90).rounded()
        guard abs(angle - turns * 90) < 1 else { return nil }
        return CGFloat((Int(turns) % 4 + 4) % 4) * 90
    }

    /// Crop ratio of the saved photo. A quarter turn swaps the sensor's native axes, so
    /// the result follows the device orientation rather than the interface layout.
    private func frameOrientation(for angle: CGFloat) -> FrameOrientation {
        var sensorIsLandscape = true
        if let device {
            let native = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            sensorIsLandscape = native.width >= native.height
        }
        let quarterTurned = angle == 90 || angle == 270
        return sensorIsLandscape != quarterTurned ? .landscape : .portrait
    }

    func capture(library: LibraryModel, rollID: UUID) async {
        guard ready, !capturing, pending == nil else { return }
        capturing = true; errorMessage = nil
        haptic.impactOccurred(intensity: 0.85)
        let backgroundTime = BackgroundTime("Latent.capture")
        defer { backgroundTime.end() }
        // Read at the moment of the press so turning the phone afterwards does not matter.
        let rotation = captureAngle
        let orientation = frameOrientation(for: rotation)
        saveTarget = (library, rollID)
        do {
            let data = try await service.capture(rotation: rotation)
            pending = try await Task.detached(priority: .userInitiated) {
                try PhotoProcessor.process(data: data, orientation: orientation)
            }.value
        } catch { errorMessage = error.localizedDescription }
        if pending != nil { await persist() }
        capturing = false
        if stopAfterCapture { stopAfterCapture = false; service.stop() } else { haptic.prepare() }
    }

    func retrySave() async {
        guard !capturing else { return }
        capturing = true
        await persist()
        capturing = false
        if stopAfterCapture { stopAfterCapture = false; service.stop() }
    }

    private func retryPendingSave() async {
        guard pending != nil else { return }
        let backgroundTime = BackgroundTime("Latent.save")
        defer { backgroundTime.end() }
        await retrySave()
    }

    /// Library and roll of the photo in `pending`; set at capture time.
    private var saveTarget: (library: LibraryModel, rollID: UUID)?
    private func persist() async {
        guard let pending, let saveTarget else { return }
        do {
            try await saveTarget.library.save(pending, to: saveTarget.rollID)
            self.pending = nil; saveErrorMessage = nil
        } catch { saveErrorMessage = error.localizedDescription }
    }
}

struct CameraView: View {
    let rollID: UUID
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraModel()
    private var roll: FilmRoll? { library.roll(rollID) }
    private var busy: Bool { camera.capturing || camera.pending != nil }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            // Viewfinder shape on screen. The sensor's long side always runs along the phone's
            // long side, so a 2:3 box in a portrait UI also matches a 3:2 photo taken with
            // portrait lock on. The saved ratio itself comes from CameraModel's capture angle.
            let orientation: FrameOrientation = landscape ? .landscape : .portrait
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: { Label(roll?.title ?? "Arşiv", systemImage: "chevron.left").font(.headline) }
                        .disabled(busy)
                        .accessibilityHint("Arşive döner")
                    Spacer()
                    MicroLabel(text: roll?.counterText ?? "")
                        .accessibilityLabel(roll.map { "\($0.exposuresUsed) / \(FilmRoll.capacity) kare çekildi" } ?? "")
                }.padding(.horizontal, 24)
                // One hierarchy for both layouts: switching branches would recreate the preview
                // view, its layer (a new session connection) and the rotation coordinator on
                // every turn, which stalls the main thread mid-rotation.
                let layout = landscape ? AnyLayout(HStackLayout(spacing: 30)) : AnyLayout(VStackLayout(spacing: 16))
                layout {
                    viewfinder(orientation: orientation)
                        .frame(maxWidth: landscape ? .infinity : nil, maxHeight: landscape ? nil : max(140, geometry.size.height - 245))
                        .padding(.horizontal, landscape ? 0 : 24)
                    if !landscape {
                        HStack { MicroLabel(text: "1× · SABİT KADRAJ"); Spacer(); MicroLabel(text: roll?.filmShortName ?? "") }.padding(.horizontal, 28)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Sabit 1x kadraj, \(roll?.filmShortName ?? "")")
                    }
                    controls().frame(width: landscape ? 120 : nil)
                }.padding(.horizontal, landscape ? 24 : 0)
                if camera.pending != nil, !camera.capturing, let message = camera.saveErrorMessage {
                    Text("Son fotoğraf henüz kaydedilmedi. \(message)").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    Button("Kaydı yeniden dene") { Task { await camera.retrySave() } }
                }
                if let message = camera.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    if camera.permissionDenied {
                        Button("Ayarları aç") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    } else { Button("Tekrar dene") { Task { await camera.start() } } }
                }
                Spacer(minLength: 0)
            }.padding(.top, 15).padding(.bottom, 8)
        }
        .background(LatentTheme.paper).foregroundStyle(LatentTheme.ink)
        .interactiveDismissDisabled(busy)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await camera.start() } } else { camera.stop() }
            if phase == .background { camera.enteredBackground() }
        }
    }

    private func viewfinder(orientation: FrameOrientation) -> some View {
        GeometryReader { geometry in
            // The *inside* of the frame, rather than the frame including its border,
            // must have the same aspect ratio as the saved crop.
            let width = max(1, min(geometry.size.width - 37, (geometry.size.height - 39) * orientation.aspectRatio))
            FilmBorder(number: min(FilmRoll.capacity, roll?.nextFrameNumber ?? 1), film: roll?.film ?? "LATENT COLOR 400", date: Date()) {
                CameraPreview(session: camera.service.session, rotationAngle: camera.previewAngle) { camera.attach(previewLayer: $0) }
                    .frame(width: width, height: width / orientation.aspectRatio)
                    .dateStamp(Date())
                    .overlay { if !camera.ready { Color.black.opacity(0.4); if camera.errorMessage == nil { ProgressView().tint(.white) } } }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        // The edge print and preview are one element; the ratio follows how the phone is held.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vizör")
        .accessibilityValue(viewfinderDescription)
    }

    private var viewfinderDescription: String {
        let ratio = camera.captureOrientation == .portrait ? "2:3 dikey kadraj" : "3:2 yatay kadraj"
        guard let roll, !roll.isFinished else { return ratio }
        return "\(ratio), sıradaki kare \(roll.nextFrameNumber)"
    }

    private func controls() -> some View {
        VStack(spacing: 15) {
            Circle().fill(LatentTheme.orange).frame(width: 6, height: 6).accessibilityHidden(true)
            Button {
                Task { await camera.capture(library: library, rollID: rollID) }
            } label: { if camera.capturing { ProgressView().tint(.black) } else { Color.clear } }
                .buttonStyle(TactileShutterStyle())
                .disabled(!camera.ready || busy || (roll?.isFinished ?? true))
                .accessibilityLabel("Fotoğraf çek")
                .accessibilityHint("Aktif ruloya bir kare ekler")
            if roll?.isFinished == true { Text("Rulo tamamlandı").font(.caption) }
            else if let last = roll?.frames.last {
                HStack(spacing: 8) {
                    StoredPhoto(url: library.url(last), aspectRatio: last.orientation.aspectRatio).frame(width: 24, height: 30).clipped()
                    MicroLabel(text: "\(last.number). KARE KAYDEDİLDİ")
                }.accessibilityElement(children: .ignore)
                .accessibilityLabel("Son kare: \(last.number). kare kaydedildi")
            }
        }
    }
}

/// Keeps the app running briefly if it is backgrounded while a photo is processed or saved.
@MainActor
private final class BackgroundTime {
    private var id = UIBackgroundTaskIdentifier.invalid
    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // UIKit calls the expiration handler on the main thread.
            MainActor.assumeIsolated { self?.end() }
        }
    }
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
