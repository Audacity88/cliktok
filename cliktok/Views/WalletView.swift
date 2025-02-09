import SwiftUI

// Tip History Row Component
struct TipHistoryRow: View {
    let tip: Tip
    let isReceived: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(isReceived ? "+" : "-")$\(String(format: "%.2f", tip.amount))")
                    .bold()
                    .foregroundColor(isReceived ? .green : .primary)
                Text(tip.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(isReceived ? "From" : "To"): \(isReceived ? tip.senderID : tip.receiverID)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct WalletView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TipViewModel.shared
    @State private var selectedAmount: Double = 1.00
    @State private var showingAddFunds = false
    @State private var showingTipHistory = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            List {
                balanceSection
                addFundsSection
                receivedTipsSection
                sentTipsSection
            }
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color.black : Color.white)
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(colorScheme == .dark ? Color.black : Color.white, for: .navigationBar)
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                Task {
                    await viewModel.loadBalance()
                    await viewModel.loadTipHistory()
                }
            }
        }
    }
    
    private var balanceSection: some View {
        Section {
            BalanceRow(balance: viewModel.balance)
        }
    }
    
    private var addFundsSection: some View {
        Section("Add Funds") {
            ForEach(viewModel.tipAmounts, id: \.self) { amount in
                AddFundsRow(
                    amount: amount,
                    isPurchasing: viewModel.isPurchasing
                ) {
                    handleAddFunds(amount: amount)
                }
            }
        }
    }
    
    private var receivedTipsSection: some View {
        Section("Tips Received") {
            if viewModel.receivedTips.isEmpty {
                Text("No tips received")
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.receivedTips) { tip in
                    TipHistoryRow(tip: tip, isReceived: true)
                }
            }
        }
    }
    
    private var sentTipsSection: some View {
        Section("Tips Sent") {
            if viewModel.sentTips.isEmpty {
                Text("No tips sent")
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.sentTips) { tip in
                    TipHistoryRow(tip: tip, isReceived: false)
                }
            }
        }
    }
    
    private func handleAddFunds(amount: Double) {
        Task {
            do {
                try await viewModel.addFunds(amount)
                dismiss()
            } catch {
                showingError = true
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Supporting Views

struct AddFundsRow: View {
    let amount: Double
    let isPurchasing: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("Add $\(String(format: "%.2f", amount))")
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