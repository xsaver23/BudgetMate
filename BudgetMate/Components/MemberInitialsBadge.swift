import SwiftUI

struct MemberInitialsBadge: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 28
    var accessibilityLabel: String?
    var showsShadow: Bool = false

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accessibleForeground(forHex: colorHex))
            )
            .overlay(
                Circle().stroke(AppTheme.background, lineWidth: max(2, size * 0.07))
            )
            .shadow(color: showsShadow ? Color(hex: colorHex).opacity(0.12) : .clear, radius: 4, x: 0, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel ?? "Member \(initials)")
    }
}

/// Overlapping avatars used to indicate the members a split bill is shared with.
struct MemberAvatarCluster: View {
    let members: [BudgetMember]
    var size: CGFloat = 34
    var maxVisible: Int = 3

    var body: some View {
        let uniqueMembers = members.reduce(into: [BudgetMember]()) { result, member in
            if !result.contains(where: { $0.id == member.id }) {
                result.append(member)
            }
        }
        let visible = Array(uniqueMembers.prefix(maxVisible))
        let overflow = uniqueMembers.count - visible.count

        HStack(spacing: -size * 0.38) {
            ForEach(visible) { member in
                MemberInitialsBadge(
                    initials: member.displayInitials,
                    colorHex: member.colorHex,
                    size: size,
                    accessibilityLabel: "Member \(member.displayName)"
                )
            }

            if overflow > 0 {
                Circle()
                    .fill(Color(hex: "#9CA3AF"))
                    .frame(width: size, height: size)
                    .overlay(
                        Text("+\(overflow)")
                            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
                    .overlay(Circle().stroke(AppTheme.background, lineWidth: max(2, size * 0.07)))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Split with \(uniqueMembers.count) members")
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            MemberInitialsBadge(initials: "A", colorHex: "#3B82F6")
            MemberInitialsBadge(initials: "B", colorHex: "#F97316")
        }
        MemberAvatarCluster(members: MemberSampleData.members)
    }
    .padding()
}
