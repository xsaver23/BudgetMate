import Foundation

enum AppTab: Hashable {
    case dashboard
    case transactions
    case budget
    case settings
}

struct AppTabSelectionState {
    private(set) var selectedTab: AppTab = .dashboard
    private(set) var visitedTabs: Set<AppTab> = [.dashboard]

    mutating func select(_ tab: AppTab) {
        guard selectedTab != tab else { return }
        visitedTabs.insert(tab)
        selectedTab = tab
    }
}
