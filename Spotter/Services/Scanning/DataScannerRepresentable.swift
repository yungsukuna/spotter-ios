import SwiftUI
import VisionKit
import Vision

/// VisionKit-backed barcode scanner for hardware that supports it (A12
/// Bionic / iOS 16 or newer). ``BarcodeScannerView`` is responsible for
/// checking `DataScannerViewController.isSupported` and `.isAvailable`
/// before ever constructing this — older or camera-less hardware gets
/// ``MetadataCaptureScannerRepresentable`` instead.
struct DataScannerRepresentable: UIViewControllerRepresentable {
    /// Called once per newly-recognised barcode payload. Debouncing repeat
    /// detections of the same code across frames is this type's job, not the
    /// caller's — see ``Coordinator/lastEmittedPayload``.
    var onScan: (String) -> Void

    private static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !uiViewController.isScanning else { return }
        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        /// The most recently emitted payload. A barcode held steady in frame
        /// gets re-detected on every capture cycle; without this a single
        /// scan would fire `onScan` dozens of times.
        private var lastEmittedPayload: String?

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      payload != lastEmittedPayload
                else { continue }
                lastEmittedPayload = payload
                onScan(payload)
            }
        }
    }
}
