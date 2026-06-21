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
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(greeting)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 12)

            Button(action: onProfileTap) {
                MemberInitialsBadge(
                    initials: member.initials,
                    colorHex: member.colorHex,
                    size: 40,
                    accessibilityLabel: "Open settings. Active member \(member.displayName)"
                )
            }
            .buttonStyle(.plain)
            .buttonStyle(PressableButtonStyle(scale: 0.94))
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
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
