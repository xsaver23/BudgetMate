import Foundation

@MainActor
final class TransactionFlowCoordinator: ObservableObject {
    @Published private(set) var shouldPresentAddTransaction: Bool = false
    @Published private(set) var isTransactionEditorActive = false
    @Published private(set) var lastActionMessage: String?
    private var clearMessageTask: Task<Void, Never>?

    func openAddTransaction() {
        guard !shouldPresentAddTransaction else { return }
        shouldPresentAddTransaction = true
    }

    func closeAddTransaction() {
        guard shouldPresentAddTransaction else { return }
        shouldPresentAddTransaction = false
    }

    func setTransactionEditorActive(_ isActive: Bool) {
        guard isTransactionEditorActive != isActive else { return }
        isTransactionEditorActive = isActive
    }

    func recordLocalSave() {
        clearMessageTask?.cancel()
        lastActionMessage = "Transaction saved on this device"
        clearMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.lastActionMessage = nil
        }
    }
}
