import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var transactionFlow: TransactionFlowCoordinator
    @EnvironmentObject private var authStore: AuthSessionStore
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            customTabBar
        }
        .background(AppTheme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var selectedContent: some View {
        let scope = authStore.currentBudgetScopeId
        switch selectedTab {
        case .dashboard:
            DashboardView(budgetScopeId: scope, onOpenSettings: { selectedTab = .settings })
        case .transactions:
            TransactionsView(budgetScopeId: scope, onOpenSettings: { selectedTab = .settings })
        case .budget:
            BudgetView(budgetScopeId: scope, onOpenSettings: { selectedTab = .settings })
        case .settings:
            SettingsView(budgetScopeId: scope)
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 4) {
            tabButton(for: .dashboard, title: "Dashboard", icon: "house")
            tabButton(for: .transactions, title: "Transactions", icon: "list.bullet.rectangle")

            addTransactionButton

            tabButton(for: .budget, title: "Budget", icon: "chart.bar")
            tabButton(for: .settings, title: "Settings", icon: "gearshape")
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity)
        .background(
            AppTheme.background
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppTheme.surfaceStroke)
                        .frame(height: 1)
                }
        )
    }

    private func tabButton(for tab: AppTab, title: String, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selectedTab == tab ? "\(icon).fill" : icon)
                    .font(.system(size: 21, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
                .foregroundStyle(selectedTab == tab ? AppTheme.brand : BudgetBeaverPalette.wood)
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97, pressedOpacity: 0.86))
        .accessibilityLabel(title)
    }

    private var addTransactionButton: some View {
        Button {
            selectedTab = .transactions
            transactionFlow.openAddTransaction()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.brand)
                )
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96))
        .accessibilityLabel("Add Transaction")
    }
}

#Preview {
    RootTabView()
        .environmentObject(SettingsStore())
        .environmentObject(MemberViewModel())
        .environmentObject(TransactionFlowCoordinator())
        .environmentObject(MonthSelectionStore())
        .environmentObject(AuthSessionStore())
        .environmentObject(CloudSyncStore())
        .environmentObject(AppRefreshStore())
        .modelContainer(PreviewContainer.seeded)
}
