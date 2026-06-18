import Foundation

@MainActor
final class TransactionFlowCoordinator: ObservableObject {
    @Published var shouldPresentAddTransaction: Bool = false

    func openAddTransaction() {
        shouldPresentAddTransaction = true
    }
}
