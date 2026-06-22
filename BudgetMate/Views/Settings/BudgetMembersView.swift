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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Budget members")
                    .font(.roundedBold(34))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .padding(.top, 18)

                if canManageMembers {
                    ForEach(memberViewModel.members) { member in
                        memberRow(member)
                            .contextMenu {
                                if member.role != .owner {
                                    Button(role: .destructive) {
                                        deleteMember(member)
                                    } label: {
                                        Label("Remove Member", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } else {
                    ForEach(memberViewModel.members) { member in
                        memberRow(member)
                    }

                    Text("Only the budget owner can invite or remove members.")
                        .font(.caption)
                        .foregroundStyle(BudgetBeaverPalette.wood)
                }

                if canManageMembers {
                    Button {
                        isShowingInviteSheet = true
                    } label: {
                        Text("Invite member")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98))
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Budget Members")
        .navigationBarTitleDisplayMode(.inline)
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
                initials: member.displayInitials,
                colorHex: member.colorHex,
                size: 52,
                accessibilityLabel: "Member \(member.displayName)"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.roundedBold(22))
                    .foregroundStyle(BudgetBeaverPalette.ink)

                if let email = member.email, !email.isEmpty {
                    Text(email)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BudgetBeaverPalette.wood)
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

            Spacer(minLength: 8)

            if canManageMembers, member.role != .owner {
                Button(role: .destructive) {
                    deleteMember(member)
                } label: {
                    Image(systemName: "trash")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.danger)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.expense.opacity(0.35), in: Circle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.94))
                .accessibilityLabel("Remove \(member.displayName)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            .font(.caption.weight(.black))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.30), in: Capsule())
            .foregroundStyle(AppTheme.brand)
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

    private func deleteMember(_ member: BudgetMember) {
        guard let index = memberViewModel.members.firstIndex(where: { $0.id == member.id }) else { return }
        deleteMembers(at: IndexSet(integer: index))
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
