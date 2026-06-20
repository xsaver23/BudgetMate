import SwiftData
import SwiftUI

struct BudgetMembersView: View {
    @EnvironmentObject private var memberViewModel: MemberViewModel
    @EnvironmentObject private var authStore: AuthSessionStore
    @EnvironmentObject private var cloudSyncStore: CloudSyncStore
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]
    @State private var isShowingInviteSheet = false
    @State private var feedbackMessage: String?

    var body: some View {
        List {
            Section("Members") {
                if canManageMembers {
                    ForEach(memberViewModel.members) { member in
                        memberRow(member)
                    }
                    .onDelete(perform: deleteMembers)
                } else {
                    ForEach(memberViewModel.members) { member in
                        memberRow(member)
                    }

                    Text("Only the budget owner can invite or remove members.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if canManageMembers {
                Section {
                    Button("Invite Member") {
                        isShowingInviteSheet = true
                    }
                    .tint(AppTheme.brand)
                }
            }
        }
        .navigationTitle("Budget Members")
        .sheet(isPresented: $isShowingInviteSheet) {
            InviteMemberView { name, email in
                if memberViewModel.inviteMember(displayName: name, email: email) != nil {
                    cloudSyncStore.saveMembers(
                        memberViewModel.members,
                        userScopeId: authStore.currentUserScopeId,
                        budgetScopeId: authStore.currentBudgetScopeId
                    )
                    if let email {
                        Task {
                            do {
                                try await cloudSyncStore.inviteMember(
                                    displayName: name,
                                    email: email,
                                    userScopeId: authStore.currentUserScopeId
                                )
                                feedbackMessage = "Invite saved for \(name). Email delivery is coming next."
                            } catch {
                                feedbackMessage = "Member added locally, but the cloud invite failed: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
        .alert("Budget Members", isPresented: feedbackAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(feedbackMessage ?? "")
        }
    }

    private var canManageMembers: Bool {
        authStore.currentBudgetScopeId == authStore.currentUserScopeId
    }

    private func memberRow(_ member: BudgetMember) -> some View {
        HStack(spacing: 12) {
            MemberInitialsBadge(
                initials: member.initials,
                colorHex: member.colorHex,
                size: 40,
                accessibilityLabel: "Member \(member.displayName)"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.roundedBold(17))

                if let email = member.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    memberChip(
                        title: member.role.displayName,
                        systemImage: member.role == .owner ? "crown.fill" : "person.fill",
                        tint: member.role == .owner ? AppTheme.warning : AppTheme.brand
                    )
                    inviteStatusChip(member.inviteStatus)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func inviteStatusChip(_ status: InviteStatus) -> some View {
        let style = inviteStatusStyle(status)
        return memberChip(
            title: status.displayName,
            systemImage: style.systemImage,
            tint: style.tint
        )
    }

    private func inviteStatusStyle(_ status: InviteStatus) -> (systemImage: String, tint: Color) {
        switch status {
        case .active:
            return ("checkmark.circle.fill", AppTheme.income)
        case .invited:
            return ("paperplane.fill", AppTheme.brand)
        case .pending:
            return ("clock.fill", AppTheme.warning)
        }
    }

    private func memberChip(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }

    private var feedbackAlertBinding: Binding<Bool> {
        Binding(
            get: { feedbackMessage != nil },
            set: { newValue in
                if !newValue {
                    feedbackMessage = nil
                }
            }
        )
    }

    private func deleteMembers(at offsets: IndexSet) {
        do {
            let membersToDelete = offsets.compactMap { memberViewModel.members[safe: $0] }
            let result = try memberViewModel.removeMembers(at: offsets)
            let deletedTransactionCount = deleteTransactions(
                forMemberIds: result.removedMemberIds
            )
            membersToDelete.forEach {
                cloudSyncStore.deleteMember(
                    $0,
                    userScopeId: authStore.currentUserScopeId,
                    budgetScopeId: authStore.currentBudgetScopeId
                )
                if let authUserId = $0.authUserId {
                    cloudSyncStore.revokeMembership(
                        memberUserId: authUserId,
                        userScopeId: authStore.currentUserScopeId,
                        budgetScopeId: authStore.currentBudgetScopeId
                    )
                }
            }
            cloudSyncStore.saveMembers(
                memberViewModel.members,
                userScopeId: authStore.currentUserScopeId,
                budgetScopeId: authStore.currentBudgetScopeId
            )

            if result.didReassignActiveMember {
                feedbackMessage = "Deleted member and \(deletedTransactionCount) related transactions. \"Using app as\" was switched to \(memberViewModel.activeMember.displayName)."
            } else if deletedTransactionCount > 0 {
                feedbackMessage = "Deleted member and \(deletedTransactionCount) related transactions."
            }
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    private func deleteTransactions(forMemberIds ids: Set<UUID>) -> Int {
        let toDelete = transactions.filter { ids.contains($0.createdByMemberId) }
        toDelete.forEach { modelContext.delete($0) }
        return toDelete.count
    }
}

#Preview {
    NavigationStack {
        BudgetMembersView()
            .environmentObject(MemberViewModel())
            .environmentObject(AuthSessionStore())
            .environmentObject(CloudSyncStore())
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
