import Testing

@testable import Spotter

@Suite("BarcodeValidator")
struct BarcodeValidatorTests {

    @Test("Real barcodes of every accepted length validate", arguments: [
        "96385074",         // EAN-8
        "737628064502",     // UPC-A — the product probed live during planning
        "9300675024235",    // EAN-13
        "00012345600012",   // GTIN-14
    ])
    func realBarcodesAreValid(barcode: String) {
        #expect(BarcodeValidator.validate(barcode) == .valid(barcode))
    }

    @Test("Spaces and hyphens copied from packaging are stripped")
    func separatorsAreStripped() {
        #expect(BarcodeValidator.validate("9 300675 024235") == .valid("9300675024235"))
        #expect(BarcodeValidator.validate("7376-2806-4502") == .valid("737628064502"))
        #expect(BarcodeValidator.validate("  96385074\n") == .valid("96385074"))
    }

    @Test("A single mistyped digit is caught by the check digit")
    func typoFailsCheckDigit() {
        // Last digit off by one — the case the validator exists for, since the
        // alternative is a wasted rate-limited lookup that reads as "not found".
        #expect(BarcodeValidator.validate("737628064503") == .invalidCheckDigit)
        #expect(BarcodeValidator.validate("9300675024236") == .invalidCheckDigit)
    }

    @Test("Blank input is empty, not an error")
    func blankIsEmpty() {
        #expect(BarcodeValidator.validate("") == .empty)
        #expect(BarcodeValidator.validate("   ") == .empty)
        #expect(BarcodeValidator.message(for: .empty) == nil)
    }

    @Test("Unsupported lengths are rejected with the count")
    func wrongLength() {
        #expect(BarcodeValidator.validate("12345") == .wrongLength(5))
        #expect(BarcodeValidator.validate("123456789012345") == .wrongLength(15))
        #expect(BarcodeValidator.message(for: .wrongLength(5))?.contains("5") == true)
    }

    @Test("Every invalid result has a message to show")
    func invalidResultsHaveMessages() {
        #expect(BarcodeValidator.message(for: .invalidCheckDigit) != nil)
        #expect(BarcodeValidator.message(for: .wrongLength(3)) != nil)
        #expect(BarcodeValidator.message(for: .valid("96385074")) == nil)
    }

    @Test("Mock catalogue barcodes are valid, so they can be typed in previews")
    func mockBarcodesValidate() {
        for record in MockFoodDataSource.sampleRecords {
            guard let barcode = record.barcode else { continue }
            #expect(BarcodeValidator.validate(barcode) == .valid(barcode), "\(record.name)")
        }
    }
}
