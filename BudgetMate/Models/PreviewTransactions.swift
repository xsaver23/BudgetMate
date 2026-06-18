import Foundation

enum PreviewTransactions {
    static let samples: [Transaction] = [
        Transaction(
            title: "Salary - May",
            amount: 3200,
            type: .income,
            category: .work,
            paymentMethod: nil,
            createdByMemberId: MemberSampleData.userAId,
            date: Calendar.current.date(byAdding: .day, value: -12, to: .now) ?? .now
        ),
        Transaction(
            title: "Grocery Store",
            amount: 94.30,
            type: .expense,
            category: .food,
            paymentMethod: .card,
            createdByMemberId: MemberSampleData.userBId,
            date: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
        ),
        Transaction(
            title: "Rent Payment",
            amount: 1200,
            type: .expense,
            category: .rent,
            paymentMethod: .cash,
            createdByMemberId: MemberSampleData.userAId,
            date: Calendar.current.date(byAdding: .day, value: -8, to: .now) ?? .now
        )
    ]
}
