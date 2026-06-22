import SwiftUI

struct AppTopBar: View {
    let member: BudgetMember
    var onProfileTap: () -> Void = {}

    private var firstName: String {
        let first = member.displayName
            .split(separator: " ")
            .first
            .map(String.init) ?? member.displayName
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        switch hour {
        case 5..<12: timeOfDay = "Good morning"
        case 12..<17: timeOfDay = "Good afternoon"
        case 17..<22: timeOfDay = "Good evening"
        default: timeOfDay = "Hello"
        }
        return firstName.isEmpty ? timeOfDay : "\(timeOfDay), \(firstName)"
    }

    private var todayLabel: String {
        Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(todayLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BudgetBeaverPalette.wood)
                    .lineLimit(1)
                Text(greeting)
                    .font(.roundedBold(30))
                    .foregroundStyle(BudgetBeaverPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 12)

            Button(action: onProfileTap) {
                MemberInitialsBadge(
                    initials: member.displayInitials,
                    colorHex: member.colorHex,
                    size: 48,
                    accessibilityLabel: "Open settings. Active member \(member.displayName)"
                )
            }
            .buttonStyle(.plain)
            .buttonStyle(PressableButtonStyle(scale: 0.94))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 0) {
        AppTopBar(member: MemberSampleData.members[0])
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
