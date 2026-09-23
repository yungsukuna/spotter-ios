import SwiftUI

/// Validates a barcode number typed by hand.
///
/// Typing a 13-digit number is error-prone, and a typo would otherwise cost a
/// round trip to Open Food Facts (against a 15-per-minute budget) only to come
/// back as "product not found" — which reads as "the database doesn't have it"
/// rather than "you mistyped". Every retail barcode carries a GS1 check digit,
/// so almost all single-digit typos can be caught locally, before any request.
enum BarcodeValidator {

    enum Result: Equatable {
        /// Digits only, ready to look up.
        case valid(String)
        case empty
        case wrongLength(Int)
        case invalidCheckDigit
    }

    /// EAN-8, UPC-A, EAN-13 and GTIN-14 — the lengths that appear on retail
    /// food packaging and that share the GS1 check-digit scheme.
    static let acceptedLengths: Set<Int> = [8, 12, 13, 14]

    /// Strip the spaces and hyphens people copy from packaging, then check the
    /// length and check digit.
    static func validate(_ input: String) -> Result {
        let digits = input.filter(\.isNumber)
        guard !digits.isEmpty else { return .empty }
        guard acceptedLengths.contains(digits.count) else { return .wrongLength(digits.count) }
        guard hasValidCheckDigit(digits) else { return .invalidCheckDigit }
        return .valid(digits)
    }

    /// GS1 mod-10: working leftward from the digit before the check digit,
    /// weight alternately 3 and 1, and the check digit brings the sum up to a
    /// multiple of ten. The same rule covers every accepted length.
    static func hasValidCheckDigit(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, let check = values.last else { return false }

        var sum = 0
        for (index, value) in values.dropLast().reversed().enumerated() {
            sum += value * (index % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }

    /// Message for an invalid result, or nil when there is nothing to say.
    static func message(for result: Result) -> String? {
        switch result {
        case .valid, .empty:
            nil
        case .wrongLength(let count):
            "Barcodes are 8, 12, 13 or 14 digits — that's \(count)."
        case .invalidCheckDigit:
            "That number doesn't check out. Look for a typo."
        }
    }
}

/// A text field for typing a barcode number, reporting it through the same
/// `onScan` callback a camera scan uses — so the caller can't tell, and
/// doesn't need to care, how the barcode arrived.
struct ManualBarcodeField: View {
    var onSubmit: (String) -> Void

    @State private var text = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Barcode number", text: $text)
                    .keyboardType(.numberPad)
                    .font(Theme.Typography.setValue)
                    .focused($isFocused)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .onChange(of: text) {
                        // Clear a stale error as soon as the user edits.
                        errorMessage = nil
                    }

                // The number pad has no return key, so submission needs a
                // button of its own.
                Button("Look Up", action: submit)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                    .disabled(text.filter(\.isNumber).isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }
        }
    }

    private func submit() {
        let result = BarcodeValidator.validate(text)
        if case .valid(let digits) = result {
            isFocused = false
            onSubmit(digits)
        } else {
            errorMessage = BarcodeValidator.message(for: result)
        }
    }
}

/// Sheet wrapper for typing a barcode while the camera scanner is open.
struct ManualBarcodeEntrySheet: View {
    var onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Type the number printed under the barcode.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
                ManualBarcodeField { barcode in
                    dismiss()
                    onSubmit(barcode)
                }
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .navigationTitle("Enter Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("Field") {
    ManualBarcodeField { _ in }
        .padding()
}

#Preview("Sheet") {
    ManualBarcodeEntrySheet { _ in }
}
