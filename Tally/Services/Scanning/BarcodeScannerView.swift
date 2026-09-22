import AVFoundation
import SwiftUI
import VisionKit

/// Barcode scanner surface for a feature screen to embed.
///
/// Picks the best available scanning backend at runtime — VisionKit's
/// `DataScannerViewController` where the device supports it,
/// ``MetadataCaptureScannerRepresentable`` (classic `AVCaptureMetadataOutput`)
/// everywhere else — and owns camera permission end to end, including the
/// not-determined prompt and a denied/restricted state with a Settings deep
/// link. The caller supplies nothing but `onScan`.
///
/// Typing the barcode number is always available as a fallback, and is the
/// *only* option on a device with no camera. That case is detected up front
/// rather than left to the capture backend: with no camera, the AVFoundation
/// path cannot build a session and would render an empty black view with no
/// explanation — which is exactly what the Simulator showed before this.
///
/// This view does no food lookup and shows no logging UI. Wiring a barcode to
/// a ``FoodDataSource`` and presenting the result is the caller's job; this
/// type only ever reports a raw barcode string, scanned or typed.
struct BarcodeScannerView: View {
    var onScan: (String) -> Void

    @State private var authorization: CameraAuthorization = CameraAuthorization.current
    @State private var showingManualEntry = false

    /// Checked once. Cameras do not come and go during a session, and on the
    /// Simulator this is always false.
    @State private var hasCamera = AVCaptureDevice.default(for: .video) != nil

    var body: some View {
        content
            .task {
                // No point prompting for a camera that does not exist.
                if hasCamera, authorization == .notDetermined {
                    authorization = await CameraAuthorization.request()
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualBarcodeEntrySheet(onSubmit: onScan)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !hasCamera {
            noCameraMessage
        } else {
            switch authorization {
            case .authorized:
                scannerBackend
                    .overlay(alignment: .bottom) { typeInsteadButton }
            case .notDetermined:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.groupedBackground)
            case .denied, .restricted:
                permissionMessage
            }
        }
    }

    /// `DataScannerViewController.isSupported` reflects the hardware (needs
    /// A12 Bionic or newer, iOS 16+); `.isAvailable` additionally reflects
    /// runtime conditions. Both must hold, or the classic AVFoundation path is
    /// used instead.
    @ViewBuilder
    private var scannerBackend: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScannerRepresentable(onScan: onScan)
                .ignoresSafeArea()
        } else {
            MetadataCaptureScannerRepresentable(onScan: onScan)
                .ignoresSafeArea()
        }
    }

    /// For the barcode that will not scan — creased, curved, or badly printed.
    private var typeInsteadButton: some View {
        Button {
            showingManualEntry = true
        } label: {
            Label("Type barcode instead", systemImage: "keyboard")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, Theme.Spacing.xl)
    }

    private var noCameraMessage: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "camera.slash")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.Colors.secondaryText)
                Text("No camera available")
                    .font(.headline)
                Text("Type the number printed under the barcode instead.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            ManualBarcodeField(onSubmit: onScan)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.groupedBackground)
    }

    private var permissionMessage: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.Colors.secondaryText)
                Text(authorization == .restricted ? "Camera access is restricted" : "Camera access is off")
                    .font(.headline)
                if authorization == .denied {
                    Text("Turn on camera access in Settings to scan, or type the barcode number below.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                    if let url = CameraAuthorization.settingsURL {
                        Link("Open Settings", destination: url)
                            .padding(.top, Theme.Spacing.xs)
                    }
                }
            }
            ManualBarcodeField(onSubmit: onScan)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.groupedBackground)
    }
}

#Preview("Scanner") {
    // The preview canvas has no camera, so this renders the no-camera state
    // with manual entry — the same thing the Simulator shows.
    BarcodeScannerView { _ in }
}
