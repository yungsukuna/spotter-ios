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
/// This view does no food lookup and shows no logging UI. Wiring a scanned
/// barcode to a ``FoodDataSource`` and presenting the result is the caller's
/// job; this type only ever reports a raw barcode string.
struct BarcodeScannerView: View {
    var onScan: (String) -> Void

    @State private var authorization: CameraAuthorization = CameraAuthorization.current

    var body: some View {
        content
            .task {
                if authorization == .notDetermined {
                    authorization = await CameraAuthorization.request()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch authorization {
        case .authorized:
            scannerBackend
        case .notDetermined:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.groupedBackground)
        case .denied, .restricted:
            permissionMessage
        }
    }

    /// `DataScannerViewController.isSupported` reflects the hardware (needs
    /// A12 Bionic or newer, iOS 16+); `.isAvailable` additionally reflects
    /// runtime conditions such as no camera being present at all (the
    /// Simulator). Both must hold, or the classic AVFoundation path is used
    /// instead.
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

    private var permissionMessage: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(authorization == .restricted ? "Camera access is restricted" : "Camera access is off")
                .font(.headline)
            if authorization == .denied {
                Text("Turn on camera access in Settings to scan a barcode.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                if let url = CameraAuthorization.settingsURL {
                    Link("Open Settings", destination: url)
                        .padding(.top, Theme.Spacing.xs)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.groupedBackground)
    }
}

#Preview("Denied") {
    BarcodeScannerView { _ in }
        // The preview canvas never grants camera access, so this exercises
        // the permission-message path without needing a device.
}
