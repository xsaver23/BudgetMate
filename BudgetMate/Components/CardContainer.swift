import SwiftUI

struct CardContainer<Content: View>: View {
    var content: Content
    var showsShadow: Bool

    init(showsShadow: Bool = true, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.showsShadow = showsShadow
    }

    var body: some View {
        content.cardSurface(showsShadow: showsShadow)
    }
}

#Preview {
    CardContainer {
        VStack(alignment: .leading) {
            Text("Card Title")
                .font(.headline)
            Text("Card content")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .background(AppTheme.background)
}
