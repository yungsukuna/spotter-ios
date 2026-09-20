import Foundation

/// Defensive field decoding for third-party food APIs.
///
/// Both Open Food Facts (crowd-edited) and USDA FoodData Central are
/// inconsistent about JSON types in ways a strict `Decodable` struct cannot
/// absorb: the same nutrient field is a JSON number on one product and a
/// numeric string on another, and a missing panel is the norm rather than the
/// exception. A single malformed field must never fail decoding of an entire
/// product — these helpers decode a value if present and simply return `nil`
/// when the value is there but not in a shape we can use, rather than
/// throwing and losing everything else on the record.
extension KeyedDecodingContainer {

    /// Decodes a `Double` that may be present as a JSON number or a numeric
    /// string (or absent, or unparsable) without throwing in any of those
    /// cases.
    func lenientDouble(forKey key: Key) -> Double? {
        guard contains(key) else { return nil }
        if let direct = try? decode(Double.self, forKey: key) {
            return direct
        }
        if let string = try? decode(String.self, forKey: key) {
            return Double(string)
        }
        return nil
    }

    /// Decodes an `Int` that may be present as a JSON number, a JSON floating
    /// point number, or a numeric string.
    func lenientInt(forKey key: Key) -> Int? {
        guard contains(key) else { return nil }
        if let direct = try? decode(Int.self, forKey: key) {
            return direct
        }
        if let double = try? decode(Double.self, forKey: key) {
            return Int(double)
        }
        if let string = try? decode(String.self, forKey: key) {
            return Int(string) ?? Double(string).map(Int.init)
        }
        return nil
    }

    /// Decodes a `String`, tolerating a value that arrived as a JSON number.
    func lenientString(forKey key: Key) -> String? {
        guard contains(key) else { return nil }
        if let direct = try? decode(String.self, forKey: key) {
            // OFF sends empty strings for a good number of unset text
            // fields; treat those the same as absent.
            return direct.isEmpty ? nil : direct
        }
        if let double = try? decode(Double.self, forKey: key) {
            return String(double)
        }
        return nil
    }
}
