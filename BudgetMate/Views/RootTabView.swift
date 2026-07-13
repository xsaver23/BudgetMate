import OSLog
import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var authStore: AuthSessionStore
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            customTabBar
        }
        .background(AppTheme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            LocalSaveToast()
                .padding(.bottom, 74)
                .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        let scope = authStore.currentBudgetScopeId
        switch selectedTab {
        case .dashboard:
            DashboardView(
                budgetScopeId: scope,
                onOpenSettings: { selectedTab = .settings },
                onOpenBudget: { selectedTab = .budget }
            )
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

            GlobalAddTransactionButton()

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
}

private struct LocalSaveToast: View {
    @EnvironmentObject private var transactionFlow: TransactionFlowCoordinator

    var body: some View {
        if let message = transactionFlow.lastActionMessage {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(AppTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.surfaceStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// Owns the global add sheet inside the persistent root tab bar. Keeping its
/// presentation dependencies in this small leaf means opening the keyboard
/// does not invalidate or reconstruct the selected Dashboard/Budget tab.
private struct GlobalAddTransactionButton: View {
    @EnvironmentObject private var transactionFlow: TransactionFlowCoordinator
    @EnvironmentObject private var settingsStore: SettingsStore
    private static let interactionSignposter = OSSignposter(subsystem: "BudgetMate", category: "Interaction")
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var authStore: AuthSessionStore

    private var presentation: Binding<Bool> {
        Binding(
            get: { transactionFlow.shouldPresentAddTransaction },
            set: { isPresented in
                if isPresented {
                    transactionFlow.openAddTransaction()
                } else {
                    transactionFlow.closeAddTransaction()
                }
            }
        )
    }

    var body: some View {
        Button {
            Self.interactionSignposter.emitEvent("Add Transaction Requested")
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
        // This used to live in TransactionsView, forcing its @Query and
        // financial metrics path to initialize before the editor appeared.
        // Repeated iPhone watchdog reports ended inside UITextField layout
        // while UISheetPresentationController reacted to keyboard frame
        // changes. Transaction entry is keyboard-first, so use a stable full
        // screen presentation instead of a resizing page sheet.
        .fullScreenCover(isPresented: presentation, onDismiss: {
            transactionFlow.closeAddTransaction()
            transactionFlow.setTransactionEditorActive(false)
        }) {
            AddTransactionView(
                initialSettings: settingsStore.settings,
                initialSelectedMemberId: defaultTransactionMemberId
            )
        }
    }

    private var defaultTransactionMemberId: UUID {
        memberViewModel.profileMember(
            userScopeId: authStore.currentUserScopeId,
            email: authStore.userEmail
        )?.id ?? memberViewModel.activeMember.id
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
