import Foundation
import Testing

@testable import Tally

@MainActor
@Suite("ExercisePickerFilter")
struct ExercisePickerFilterTests {

    private func sampleExercises() -> [Exercise] {
        [
            Exercise(name: "Barbell Bench Press", equipment: .barbell, muscleGroup: .chest),
            Exercise(name: "Dumbbell Bench Press", equipment: .dumbbell, muscleGroup: .chest),
            Exercise(name: "Back Squat", equipment: .barbell, muscleGroup: .quads),
            Exercise(name: "Old Machine", equipment: .machine, muscleGroup: .back, isCustom: true),
        ]
    }

    @Test("Query filters by a case-insensitive name match")
    func queryFiltersCaseInsensitively() {
        let exercises = sampleExercises()
        let results = ExercisePickerFilter.filtered(exercises, query: "bench")
        #expect(results.count == 2)
    }

    @Test("An empty query returns everything not archived")
    func emptyQueryReturnsEverything() {
        let exercises = sampleExercises()
        #expect(ExercisePickerFilter.filtered(exercises, query: "").count == exercises.count)
    }

    @Test("Muscle group filter narrows the results")
    func muscleGroupFilterNarrows() {
        let exercises = sampleExercises()
        let results = ExercisePickerFilter.filtered(exercises, query: "", muscleGroup: .chest)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.muscleGroup == .chest })
    }

    @Test("Equipment filter narrows the results")
    func equipmentFilterNarrows() {
        let exercises = sampleExercises()
        let results = ExercisePickerFilter.filtered(exercises, query: "", equipment: .barbell)
        #expect(results.count == 2)
    }

    @Test("Archived exercises are excluded by default")
    func archivedExcludedByDefault() {
        let exercises = sampleExercises()
        exercises[0].isArchived = true

        let results = ExercisePickerFilter.filtered(exercises, query: "")
        #expect(!results.contains { $0.id == exercises[0].id })
    }

    @Test("Archived exercises can be included explicitly")
    func archivedIncludedWhenAsked() {
        let exercises = sampleExercises()
        exercises[0].isArchived = true

        let results = ExercisePickerFilter.filtered(exercises, query: "", includeArchived: true)
        #expect(results.count == exercises.count)
    }

    @Test("Grouping by region sorts sections and exercises by name")
    func groupingSortsSectionsAndExercises() {
        let exercises = sampleExercises()
        let grouped = ExercisePickerFilter.groupedByRegion(exercises)

        let regions = grouped.map { $0.region }
        #expect(regions == regions.sorted())

        let upperBody = grouped.first { $0.region == "Upper Body" }
        let names = upperBody?.exercises.map(\.name) ?? []
        #expect(names == names.sorted())
    }
}
