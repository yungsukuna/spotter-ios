import SwiftData
import SwiftUI

/// Manage saved routines: create, edit, reorder their exercises, delete.
/// Starting a session from a routine happens on `WorkoutsHomeView`, not here.
struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    @State private var showingNewRoutine = false

    var body: some View {
        List {
            ForEach(routines) { routine in
                NavigationLink(value: routine) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(routine.name)
                            .font(Theme.Typography.cardTitle)
                        Text(routine.exerciseCount == 0 ? "No exercises yet" : routine.exerciseSummary)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.vertical, Theme.Spacing.xxs)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Routines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New", systemImage: "plus") { showingNewRoutine = true }
            }
        }
        .sheet(isPresented: $showingNewRoutine) {
            NavigationStack {
                RoutineEditorView(routine: nil)
            }
        }
        .overlay {
            if routines.isEmpty {
                ContentUnavailableView(
                    "No Routines",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Save a workout as a routine, or create one from scratch.")
                )
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(routines[index])
        }
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    _ = WorkoutsPreviewData.seedRoutine(in: container.mainContext)

    return NavigationStack {
        RoutineListView()
            .navigationDestination(for: Routine.self) { RoutineEditorView(routine: $0) }
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
