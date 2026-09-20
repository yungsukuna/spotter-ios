import SwiftUI
import AVFoundation
import UIKit

/// `AVCaptureMetadataOutput`-based barcode scanner — the fallback path for
/// hardware that cannot run ``DataScannerRepresentable``: pre-A12 devices, or
/// anything where VisionKit reports `DataScannerViewController.isAvailable
/// == false` (notably the Simulator, which has no camera at all, so this
/// path simply shows a black preview there rather than a crash).
///
/// Uses the classic `AVCaptureSession` + `AVCaptureMetadataOutput` API that
/// has existed since iOS 7, so it needs no availability check of its own.
struct MetadataCaptureScannerRepresentable: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> MetadataScannerViewController {
        let controller = MetadataScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: MetadataScannerViewController, context: Context) {
        uiViewController.onScan = onScan
    }
}

/// Hosts the capture session. Kept as a plain `UIViewController` rather than
/// built with SwiftUI directly because `AVCaptureVideoPreviewLayer` needs a
/// real `CALayer`-backed view to size itself against, and because starting
/// and stopping the session needs explicit `viewDidAppear`/`viewDidDisappear`
/// hooks rather than SwiftUI's view lifecycle.
final class MetadataScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    /// `nonisolated(unsafe)` because `startRunning()` and `stopRunning()` block
    /// and must not run on the main thread, so the session is captured by the
    /// background queue below. `AVCaptureSession` is not Sendable-audited, but
    /// it is documented as safe to start and stop off the main thread, and
    /// every other access here is main-actor confined.
    nonisolated(unsafe) private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    /// Debounce state: the delegate fires on every frame a code is visible
    /// in, so without this a single barcode held in view for a couple of
    /// seconds would report the same payload dozens of times.
    private var lastEmittedPayload: String?
    private var lastEmittedAt = Date.distantPast
    private let debounceInterval: TimeInterval = 2

    private static let symbologies: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    /// No-ops safely (leaving a black screen) when there is no capture
    /// device at all, which is the Simulator's situation — this fallback
    /// exists for real unsupported hardware, not for a device with no camera
    /// whatsoever, but it must not crash either way.
    private func configureSession() {
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // Must be set after the output is added to the session, and must be
        // a subset of what the output actually supports.
        output.metadataObjectTypes = Self.symbologies.filter { output.availableMetadataObjectTypes.contains($0) }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    /// - Note: `nonisolated` is required. `UIViewController` is `@MainActor`,
    ///   but `AVCaptureMetadataOutputObjectsDelegate` declares this method
    ///   without isolation, and under Swift 6 a main-actor method cannot
    ///   satisfy a nonisolated protocol requirement.
    ///
    ///   Assuming main-actor isolation inside is sound rather than a gamble:
    ///   the delegate is registered with `queue: .main` in `configureSession`,
    ///   so callbacks genuinely do arrive on the main queue. If that queue ever
    ///   changes, this must become an explicit hop.
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // Reduce to plain strings *before* crossing into the main actor.
        // `AVMetadataObject` is not Sendable, so handing the array itself over
        // is a data-race error under Swift 6; `[String]` crosses freely.
        let payloads = metadataObjects.compactMap {
            ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue
        }
        guard !payloads.isEmpty else { return }

        MainActor.assumeIsolated {
            handle(payloads)
        }
    }

    private func handle(_ payloads: [String]) {
        for payload in payloads {
            let now = Date()
            if payload == lastEmittedPayload, now.timeIntervalSince(lastEmittedAt) < debounceInterval {
                continue
            }
            lastEmittedPayload = payload
            lastEmittedAt = now
            onScan?(payload)
        }
    }
}
