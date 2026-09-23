import AVFoundation
import UIKit

/// Camera permission state relevant to the barcode scanner.
///
/// A thin wrapper over `AVCaptureDevice.authorizationStatus`, kept as its own
/// type so ``BarcodeScannerView`` can switch over something `Equatable`
/// rather than repeating the AVFoundation enum's `@unknown default` handling
/// in view code.
enum CameraAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    static var current: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    /// Requests access if the user has never been asked; otherwise returns
    /// the current state unchanged. iOS only ever shows the system prompt
    /// once per install, so calling this after a denial is a no-op, not a
    /// second prompt.
    @discardableResult
    static func request() async -> CameraAuthorization {
        guard current == .notDetermined else { return current }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    /// Deep link to this app's page in Settings, for recovering from a
    /// `.denied` state without leaving the user stranded.
    static var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
}
