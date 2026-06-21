import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var transactionFlow: TransactionFlowCoordinator
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
        switch selectedTab {
        case .dashboard:
            DashboardView(onOpenSettings: { selectedTab = .settings })
        case .transactions:
            TransactionsView(onOpenSettings: { selectedTab = .settings })
        case .budget:
            BudgetView(onOpenSettings: { selectedTab = .settings })
        case .settings:
            SettingsView()
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 8) {
            tabButton(for: .dashboard, title: "Dashboard", icon: "house")
            tabButton(for: .transactions, title: "Transactions", icon: "list.bullet.rectangle")

            addTransactionButton

            tabButton(for: .budget, title: "Budget", icon: "chart.bar")
            tabButton(for: .settings, title: "Settings", icon: "gearshape")
        }
        .padding(.horizontal, 24)
        .padding(.top, 9)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity)
        .background(
            AppTheme.background
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppTheme.expense.opacity(0.45))
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
                    .font(.caption2.weight(.bold))
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
