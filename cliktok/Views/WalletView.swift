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
    @Environment(\.colorScheme) private var colorScheme
    
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
                        Text("No recent tips")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(tipViewModel.tipHistory) { tip in
                            TipHistoryRow(tip: tip)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color.black : Color.white)
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(colorScheme == .dark ? Color.black : Color.white, for: .navigationBar)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                Task {
                    await tipViewModel.loadBalance()
                    await tipViewModel.loadTipHistory()
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct BalanceRow: View {
    let balance: Double
    
    var body: some View {
        HStack {
            Text("Current Balance")
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
                Text("+$\(String(format: "%.2f", amount))")
                Spacer()
                if isPurchasing {
                    ProgressView()
                } else {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPurchasing)
    }
}