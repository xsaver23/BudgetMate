import SwiftUI
import UniformTypeIdentifiers

struct PersistenceRecoveryView: View {
    @ObservedObject var coordinator: PersistenceStartupCoordinator
    @State private var isChoosingArchive = false
    @State private var isConfirmingReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text("BudgetMate needs help opening local data")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Text("Your local store was left untouched. Retry opening it, create a private support archive, or restore a verified archive.")
                    .foregroundStyle(.secondary)

                if let context = coordinator.failureContext {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Diagnostic")
                            .font(.headline)
                        Text(context.diagnostics.message)
                            .foregroundStyle(.secondary)
                        Text("Store: \(context.diagnostics.storeFilename)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Persistence diagnostic")
                }

                if let feedbackMessage = coordinator.feedbackMessage {
                    Text(feedbackMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("persistence-feedback")
                }

                VStack(spacing: 12) {
                    Button {
                        coordinator.retry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Try opening the existing local data again.")

                    Button {
                        coordinator.createSupportArchive()
                    } label: {
                        Label("Create Support Archive", systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Create a private archive of the local store for support.")

                    Button {
                        isChoosingArchive = true
                    } label: {
                        Label("Restore Archive", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Choose a verified BudgetMate support archive to restore.")

                    if let archiveURL = coordinator.latestArchiveURL {
                        ShareLink(item: archiveURL) {
                            Label("Share Support Archive", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Share the support archive using the system share sheet.")
                    }

                    Button(role: .destructive) {
                        isConfirmingReset = true
                    } label: {
                        Label("Reset Local Cache", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.verifiedArchiveURL == nil)
                    .accessibilityHint(
                        coordinator.verifiedArchiveURL == nil
                            ? "Create and verify a support archive before resetting local data."
                            : "Reset only this device's local cache after confirmation. Cloud data and the archive stay unchanged."
                    )
                }

                if coordinator.verifiedArchiveURL == nil {
                    Text("Reset Local Cache stays unavailable until a current archive has been verified.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if coordinator.isWorking {
                    ProgressView("Working…")
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Persistence recovery in progress")
                }
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .fileImporter(
            isPresented: $isChoosingArchive,
            allowedContentTypes: [.folder, .item],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            coordinator.restoreArchive(at: url)
        }
        .confirmationDialog(
            "Reset local cache?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Local Cache", role: .destructive) {
                coordinator.resetLocalCache()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes only the local cache after re-verifying the archive. Your support archive, UserDefaults, and cloud data are preserved.")
        }
    }
}
