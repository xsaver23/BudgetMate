import Charts
import SwiftUI

struct ExpenseCategoryPieChartView: View {
    let items: [ExpenseCategoryBreakdown]
    let currencySymbol: String

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Spending by Category")
                    .font(.title3.weight(.bold))

                if items.isEmpty {
                    Text("Add expense transactions to see category breakdown.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Chart(items) { item in
                        SectorMark(
                            angle: .value("Amount", item.amount),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .foregroundStyle(CategoryColor.color(for: item.category))
                        .cornerRadius(6)
                    }
                    .frame(height: 220)

                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CategoryColor.color(for: item.category))
                                .frame(width: 10, height: 10)

                            Text(item.category.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(CurrencyFormatter.amountString(item.amount, symbol: currencySymbol))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ExpenseCategoryPieChartView(
        items: [
            ExpenseCategoryBreakdown(category: .food, amount: 120),
            ExpenseCategoryBreakdown(category: .rent, amount: 900),
            ExpenseCategoryBreakdown(category: .transportation, amount: 80)
        ],
        currencySymbol: "$"
    )
    .padding()
}
