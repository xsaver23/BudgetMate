import Foundation

enum BudgetSyncMode {
    case local
    case cloudPlaceholder

    var displayName: String {
        switch self {
        case .local:
            return "Local"
        case .cloudPlaceholder:
            return "Cloud (Placeholder)"
        }
    }
}

protocol BudgetRepository {
    var syncMode: BudgetSyncMode { get }
    func loadCurrentBudget() -> Budget
    func saveCurrentBudget(_ budget: Budget)
}

final class LocalBudgetRepository: BudgetRepository {
    let syncMode: BudgetSyncMode = .local

    private let baseBudgetKey = "budgetmate.currentBudget"
    private let userScopeId: String
    private let fallbackBudget: Budget
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        userScopeId: String = "local",
        fallbackBudget: Budget = BudgetSampleData.currentBudget
    ) {
        self.userDefaults = userDefaults
        self.userScopeId = userScopeId
        self.fallbackBudget = fallbackBudget
    }

    func loadCurrentBudget() -> Budget {
        guard let data = userDefaults.data(forKey: budgetKey),
              let decoded = try? decoder.decode(Budget.self, from: data),
              !decoded.members.isEmpty else {
            return fallbackBudget
        }

        return decoded
    }

    func saveCurrentBudget(_ budget: Budget) {
        guard let data = try? encoder.encode(budget) else { return }
        userDefaults.set(data, forKey: budgetKey)
    }

    private var budgetKey: String {
        "\(baseBudgetKey).\(userScopeId)"
    }
}
