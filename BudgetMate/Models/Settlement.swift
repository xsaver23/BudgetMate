import Foundation
import SwiftData

/// A recorded "settle up" payment that clears split-bill debt between two
/// members. Kept separate from `Transaction` so it never affects income,
/// expense, or category totals - it only adjusts who-owes-whom balances.
@Model
final class Settlement {
    var id: UUID
    var fromMemberId: UUID
    var toMemberId: UUID
    var amount: Double
    var date: Date
    var ownerUserId: String

    init(
        id: UUID = UUID(),
        fromMemberId: UUID,
        toMemberId: UUID,
        amount: Double,
        date: Date = .now,
        ownerUserId: String = "local"
    ) {
        self.id = id
        self.fromMemberId = fromMemberId
        self.toMemberId = toMemberId
        self.amount = amount
        self.date = date
        self.ownerUserId = ownerUserId
    }
}
