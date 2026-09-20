import Foundation

// Enums used across the app.
//
// IMPORTANT for anyone adding SwiftData models: enums are persisted as their
// `String` raw value in a `...Raw` stored property, with a computed property
// exposing the typed form. SwiftData can persist `Codable` enums directly, but
// `#Predicate` support for them is unreliable, and predicates over meals, food
// sources and measurement types are used throughout the app. Storing the raw
// string keeps every query straightforward.
//
// The pattern:
//     var mealRaw: String = Meal.snack.rawValue
//     var meal: Meal {
//         get { Meal(rawValue: mealRaw) ?? .snack }
//         set { mealRaw = newValue.rawValue }
//     }

/// Which part of the day a diary entry belongs to.
enum Meal: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snacks"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        case .snack: "carrot"
        }
    }

    /// Display order on the diary screen.
    static let ordered: [Meal] = [.breakfast, .lunch, .dinner, .snack]

    /// A sensible default for a "quick add" based on the time of day.
    static func suggested(at date: Date, calendar: Calendar = .current) -> Meal {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 15..<21: .dinner
        default: .snack
        }
    }
}

/// Where a food record originally came from.
enum FoodSource: String, CaseIterable, Codable, Sendable {
    case openFoodFacts
    case usda
    case custom

    var displayName: String {
        switch self {
        case .openFoodFacts: "Open Food Facts"
        case .usda: "USDA"
        case .custom: "Custom"
        }
    }

    /// Open Food Facts data is ODbL-licensed and requires attribution wherever
    /// it is displayed. See Settings > About.
    var requiresAttribution: Bool { self == .openFoodFacts }
}

/// Equipment category for an exercise. Drives filtering and iconography.
enum Equipment: String, CaseIterable, Codable, Identifiable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, other, cardio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .other: "Other"
        case .cardio: "Cardio"
        }
    }
}

/// Primary muscle group worked. Used for grouping the exercise library and for
/// per-muscle volume breakdowns in stats.
enum MuscleGroup: String, CaseIterable, Codable, Identifiable, Sendable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quads, hamstrings, glutes, calves, core, fullBody, cardio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .core: "Core"
        case .fullBody: "Full Body"
        case .cardio: "Cardio"
        }
    }

    /// Coarse grouping used by the exercise picker's section headers.
    var region: String {
        switch self {
        case .chest, .back, .shoulders: "Upper Body"
        case .biceps, .triceps, .forearms: "Arms"
        case .quads, .hamstrings, .glutes, .calves: "Legs"
        case .core: "Core"
        case .fullBody: "Full Body"
        case .cardio: "Cardio"
        }
    }
}

/// What a body measurement records.
enum MeasurementType: String, CaseIterable, Codable, Identifiable, Sendable {
    case bodyWeight, bodyFatPercent, neck, chest, waist, hips, thigh, calf, bicep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyWeight: "Body Weight"
        case .bodyFatPercent: "Body Fat"
        case .neck: "Neck"
        case .chest: "Chest"
        case .waist: "Waist"
        case .hips: "Hips"
        case .thigh: "Thigh"
        case .calf: "Calf"
        case .bicep: "Bicep"
        }
    }

    /// Body weight is stored in kg, circumferences in cm, body fat in percent.
    var storedUnit: StoredUnit {
        switch self {
        case .bodyWeight: .kilograms
        case .bodyFatPercent: .percent
        default: .centimetres
        }
    }

    enum StoredUnit: String, Codable, Sendable {
        case kilograms, centimetres, percent
    }
}

/// User-facing weight unit. Weights are always *stored* in kilograms and
/// converted at the view layer — see `UnitConverter`.
enum WeightUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case kilograms, pounds

    var id: String { rawValue }
    var displayName: String { self == .kilograms ? "Kilograms (kg)" : "Pounds (lb)" }
    var abbreviation: String { self == .kilograms ? "kg" : "lb" }
}

/// User-facing volume unit. Volumes are always *stored* in millilitres.
enum VolumeUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case millilitres, fluidOunces

    var id: String { rawValue }
    var displayName: String { self == .millilitres ? "Millilitres (ml)" : "Fluid ounces (fl oz)" }
    var abbreviation: String { self == .millilitres ? "ml" : "fl oz" }
}

/// Which formula to use for estimated one-rep max.
enum OneRepMaxFormula: String, CaseIterable, Codable, Identifiable, Sendable {
    case epley, brzycki

    var id: String { rawValue }
    var displayName: String { self == .epley ? "Epley" : "Brzycki" }
}
