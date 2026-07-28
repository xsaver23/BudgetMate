import Foundation
import SwiftData

enum CurrencyFinancialHistoryState: Equatable {
    case knownEmpty
    case populated
    case unknown
}

struct CurrencyFinancialHistorySnapshot: Equatable {
    let state: CurrencyFinancialHistoryState

    init(
        budgetScopeId: String,
        transactionOwnerScopeIds: [String],
        splitTransactionOwnerScopeIds: [String?],
        settlementOwnerScopeIds: [String],
        categoryBudgetKeys: [String],
        hasPreviouslyObservedFinancialHistory: Bool = false
    ) {
        guard let budgetScopeUUID = UUID(uuidString: budgetScopeId) else {
            state = .unknown
            return
        }

        if hasPreviouslyObservedFinancialHistory {
            state = .populated
            return
        }

        // A stored key means a category budget has existed, even if a legacy
        // client represented it with zero or an internal/hidden marker.
        if !categoryBudgetKeys.isEmpty {
            state = .populated
            return
        }

        let ownerScopeMatches =
            transactionOwnerScopeIds.map {
                Self.scopeMatch(for: $0, budgetScopeUUID: budgetScopeUUID)
            } +
            splitTransactionOwnerScopeIds.map {
                Self.scopeMatch(for: $0, budgetScopeUUID: budgetScopeUUID)
            } +
            settlementOwnerScopeIds.map {
                Self.scopeMatch(for: $0, budgetScopeUUID: budgetScopeUUID)
            }

        if ownerScopeMatches.contains(.activeBudget) {
            state = .populated
        } else if ownerScopeMatches.contains(.unknown) {
            state = .unknown
        } else {
            state = .knownEmpty
        }
    }

    private enum ScopeMatch {
        case activeBudget
        case otherBudget
        case unknown
    }

    private static func scopeMatch(
        for ownerScopeId: String?,
        budgetScopeUUID: UUID
    ) -> ScopeMatch {
        guard let ownerScopeId,
              let ownerScopeUUID = UUID(uuidString: ownerScopeId) else {
            return .unknown
        }
        return ownerScopeUUID == budgetScopeUUID ? .activeBudget : .otherBudget
    }
}

struct CurrencyChangeDecision: Equatable {
    enum Reason: Equatable {
        case available
        case checkingHistory
        case financialHistory
        case unverifiedHistory
    }

    let reason: Reason

    var isAllowed: Bool {
        reason == .available
    }

    var restrictionMessage: String? {
        switch reason {
        case .available:
            return nil
        case .checkingHistory:
            return "Checking this household’s financial history before currency can be changed."
        case .financialHistory:
            return "Currency can’t be changed after financial activity is added. Existing amounts are not converted, and currency conversion isn’t supported yet."
        case .unverifiedHistory:
            return "Currency can’t be changed because this household’s financial history can’t be verified. Existing amounts are not converted, and currency conversion isn’t supported yet."
        }
    }
}

enum CurrencyChangeGuardrail {
    @MainActor
    static func snapshot(
        in modelContext: ModelContext,
        budgetScopeId: String,
        categoryBudgetKeys: [String],
        hasPreviouslyObservedFinancialHistory: Bool = false
    ) throws -> CurrencyFinancialHistorySnapshot {
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        let splits = try modelContext.fetch(FetchDescriptor<TransactionSplit>())
        let settlements = try modelContext.fetch(FetchDescriptor<Settlement>())

        return CurrencyFinancialHistorySnapshot(
            budgetScopeId: budgetScopeId,
            transactionOwnerScopeIds: transactions.map(\.ownerUserId),
            splitTransactionOwnerScopeIds: splits.map { $0.transaction?.ownerUserId },
            settlementOwnerScopeIds: settlements.map(\.ownerUserId),
            categoryBudgetKeys: categoryBudgetKeys,
            hasPreviouslyObservedFinancialHistory: hasPreviouslyObservedFinancialHistory
        )
    }

    static func decision(
        activeBudgetScopeId: String,
        presentedBudgetScopeId: String,
        isHistoryValidated: Bool,
        isSyncing: Bool,
        history: CurrencyFinancialHistorySnapshot
    ) -> CurrencyChangeDecision {
        switch history.state {
        case .populated:
            return CurrencyChangeDecision(reason: .financialHistory)
        case .unknown:
            return CurrencyChangeDecision(reason: .unverifiedHistory)
        case .knownEmpty:
            break
        }

        guard activeBudgetScopeId == presentedBudgetScopeId,
              isHistoryValidated,
              !isSyncing else {
            return CurrencyChangeDecision(reason: .checkingHistory)
        }

        return CurrencyChangeDecision(reason: .available)
    }
}
