import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// "Data" section of Settings: export everything to a JSON file, or merge one
/// back in.
///
/// Import is a two-step flow: picking a file runs ``BackupImporter/dryRun``
/// to build an ``ImportReport``, which is shown in a confirmation dialog
/// before anything is written. Nothing is inserted until that's confirmed.
struct DataManagementSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var exportURL: URL?
    @State private var exportErrorMessage: String?

    @State private var isImporterPresented = false
    @State private var pendingImport: TallyBackup?
    @State private var pendingReport: ImportReport?
    @State private var isConfirmingImport = false
    @State private var importErrorMessage: String?
    @State private var importResultMessage: String?

    var body: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                Label("Export Backup", systemImage: "square.and.arrow.up")
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share Backup File", systemImage: "square.and.arrow.up.on.square")
                }
            }

            Button {
                isImporterPresented = true
            } label: {
                Label("Import Backup…", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("A backup is a plain, unencrypted file containing all of your food, water and workout history. Store and share it carefully.")
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
            handlePickedFile(result)
        }
        .confirmationDialog(
            "Import Backup",
            isPresented: $isConfirmingImport,
            presenting: pendingReport
        ) { _ in
            Button("Import") { commitPendingImport() }
            Button("Cancel", role: .cancel) { discardPendingImport() }
        } message: { report in
            Text(report.summary)
        }
        .alert("Couldn't Export", isPresented: exportErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .alert("Couldn't Import", isPresented: importErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert("Import Complete", isPresented: importResultPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResultMessage ?? "")
        }
    }

    // MARK: - Export

    private func exportBackup() {
        do {
            exportURL = try BackupExporter.writeExportFile(from: modelContext)
        } catch {
            exportErrorMessage = Self.friendlyMessage(for: error)
        }
    }

    // MARK: - Import

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = Self.friendlyMessage(for: error)

        case .success(let url):
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let backup = try BackupCoding.makeDecoder().decode(TallyBackup.self, from: data)
                guard backup.formatVersion <= BackupFormat.supportedVersion else {
                    throw BackupError.unsupportedVersion(found: backup.formatVersion, supported: BackupFormat.supportedVersion)
                }
                let report = try BackupImporter.dryRun(backup, into: modelContext)
                pendingImport = backup
                pendingReport = report
                isConfirmingImport = true
            } catch {
                importErrorMessage = Self.friendlyMessage(for: error)
            }
        }
    }

    private func commitPendingImport() {
        guard let pendingImport else { return }
        do {
            let report = try BackupImporter.performImport(pendingImport, into: modelContext)
            importResultMessage = report.summary
            WidgetSnapshotWriter.refresh(in: modelContext)
        } catch {
            importErrorMessage = Self.friendlyMessage(for: error)
        }
        self.pendingImport = nil
        pendingReport = nil
    }

    private func discardPendingImport() {
        pendingImport = nil
        pendingReport = nil
    }

    // MARK: - Alert bindings
    //
    // Each alert is driven by an optional message rather than its own Bool,
    // so there is exactly one source of truth for "is there something to
    // show" per alert.

    private var exportErrorPresented: Binding<Bool> {
        Binding(get: { exportErrorMessage != nil }, set: { if !$0 { exportErrorMessage = nil } })
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })
    }

    private var importResultPresented: Binding<Bool> {
        Binding(get: { importResultMessage != nil }, set: { if !$0 { importResultMessage = nil } })
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let backupError = error as? BackupError {
            return backupError.errorDescription ?? "Something went wrong."
        }
        if error is DecodingError {
            return BackupError.decodingFailed.errorDescription ?? "This file doesn't look like a Tally backup."
        }
        return BackupError.fileReadFailed.errorDescription ?? "Couldn't read that file."
    }
}

#Preview {
    Form {
        DataManagementSection()
    }
    .modelContainer(TallySchema.previewContainer())
    .environment(\.appEnvironment, .preview())
}
