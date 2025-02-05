import SwiftUI
import StripePayments

// Tip History Row Component
struct TipHistoryRow: View {
    let tip: Tip
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("$\(String(format: "%.2f", tip.amount))")
                    .bold()
                Text(tip.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("To: \(tip.receiverID)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct WalletView: View {
    @StateObject private var tipViewModel = TipViewModel()
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            List {
                // Balance Section
                Section {
                    BalanceRow(balance: tipViewModel.balance)
                }
                
                // Add Funds Section
                Section("Add Funds") {
                    ForEach(tipViewModel.tipAmounts, id: \.self) { amount in
                        AddFundsRow(
                            amount: amount,
                            isPurchasing: tipViewModel.isPurchasing,
                            onTap: {
                                Task {
                                    await tipViewModel.addFunds(amount)
                                }
                            }
                        )
                    }
                }
                
                // Recent Tips Section
                Section("Recent Tips") {
                    if tipViewModel.tipHistory.isEmpty {
                        Text("No tips yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(tipViewModel.tipHistory) { tip in
                            TipHistoryRow(tip: tip)
                        }
                    }
                }
            }
            .navigationTitle("Wallet")
            .background(Color.white)
            .scrollContentBackground(.hidden)
            .refreshable {
                Task {
                    await tipViewModel.loadBalance()
                    await tipViewModel.loadTipHistory()
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task {
                await tipViewModel.loadBalance()
                await tipViewModel.loadTipHistory()
            }
        }
    }
}

// MARK: - Supporting Views

struct BalanceRow: View {
    let balance: Double
    
    var body: some View {
        HStack {
            Text("Balance")
            Spacer()
            Text("$\(String(format: "%.2f", balance))")
                .bold()
        }
    }
}

struct AddFundsRow: View {
    let amount: Double
    let isPurchasing: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("$\(String(format: "%.2f", amount))")
                Spacer()
                if isPurchasing {
                    ProgressView()
                }
            }
        }
        .disabled(isPurchasing)
    }
}