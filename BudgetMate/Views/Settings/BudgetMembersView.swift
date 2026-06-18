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

                Text("\(member.role.displayName) • \(member.inviteStatus.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
