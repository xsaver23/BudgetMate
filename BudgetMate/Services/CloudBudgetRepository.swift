import Foundation

enum CloudBudgetRepositoryError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Cloud budget sync is not implemented yet."
        }
    }
}

/// Placeholder repository for future iCloud/CloudKit budget sharing.
/// For now, this delegates local reads/writes to the fallback repository.
final class CloudKitBudgetRepository: BudgetRepository {
    let syncMode: BudgetSyncMode = .cloudPlaceholder

    private let fallback: BudgetRepository

    init(fallback: BudgetRepository = LocalBudgetRepository()) {
        self.fallback = fallback
    }

    func loadCurrentBudget() -> Budget {
        fallback.loadCurrentBudget()
    }

    func saveCurrentBudget(_ budget: Budget) {
        fallback.saveCurrentBudget(budget)
    }

    // MARK: - Future Cloud Share & Sync API

    func createBudgetShare(for budget: Budget) async throws -> String {
        _ = budget
        throw CloudBudgetRepositoryError.notImplemented
    }

    func acceptBudgetShare(shareToken: String) async throws {
        _ = shareToken
        throw CloudBudgetRepositoryError.notImplemented
    }

    func inviteMember(email: String, to budgetId: UUID) async throws {
        _ = email
        _ = budgetId
        throw CloudBudgetRepositoryError.notImplemented
    }

    func refreshBudgetFromCloud(budgetId: UUID) async throws -> Budget {
        _ = budgetId
        throw CloudBudgetRepositoryError.notImplemented
    }

    func pushBudgetChangesToCloud(_ budget: Budget) async throws {
        _ = budget
        throw CloudBudgetRepositoryError.notImplemented
    }
}
