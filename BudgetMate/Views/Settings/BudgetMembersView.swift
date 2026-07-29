import SwiftUI

struct BudgetMembersView: View {
    @EnvironmentObject private var memberViewModel: MemberViewModel

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
                    }

                    if memberViewModel.members.contains(where: { $0.role != .owner }) {
                        Label(DestructiveActionGuardrails.memberRemovalSummary, systemImage: "lock.shield.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BudgetBeaverPalette.wood)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("budgetMembers.memberRemovalSummary")
                    }
                } else {
                    ForEach(memberViewModel.members) { member in
                        memberRow(member)
                    }

                    Text("Only the budget owner can invite members. Member removal is temporarily unavailable for everyone.")
                        .font(.caption)
                        .foregroundStyle(BudgetBeaverPalette.wood)
                }

                if canManageMembers {
                    unavailableActionRow(DestructiveActionGuardrails.inviteCreation)
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Budget Members")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canManageMembers: Bool {
        memberViewModel.activeMember.role == .owner
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
                let restriction = DestructiveActionGuardrails.memberRemoval(for: member)
                Image(systemName: "lock.shield.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.surfaceAlt, in: Circle())
                    .accessibilityLabel("\(restriction.title). \(restriction.message)")
                    .accessibilityIdentifier(restriction.accessibilityIdentifier)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.surfaceStroke, lineWidth: 1)
        )
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
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(AppTheme.brand)
    }

    private func unavailableActionRow(_ restriction: RestrictedDestructiveAction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.danger)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(restriction.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.danger)

                Text(restriction.message)
                    .font(.caption)
                    .foregroundStyle(BudgetBeaverPalette.wood)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(restriction.title). \(restriction.message)")
        .accessibilityIdentifier(restriction.accessibilityIdentifier)
    }

}

#Preview {
    NavigationStack {
        BudgetMembersView()
            .environmentObject(MemberViewModel())
            .environmentObject(AuthSessionStore())
            .environmentObject(CloudSyncStore())
            .environmentObject(SettingsStore())
    }
}
