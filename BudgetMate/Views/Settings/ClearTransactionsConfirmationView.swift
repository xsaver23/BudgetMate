import SwiftUI

struct ClearTransactionsConfirmationView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.red)

                VStack(spacing: 10) {
                    Text("Clear All Transactions?")
                        .font(.title2.weight(.bold))

                    Text("This will permanently remove all transactions and settle-up records.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Button("Clear All Transactions", role: .destructive) {
                        onConfirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Confirm Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        onCancel()
                    }
                }
            }
        }
    }
}
