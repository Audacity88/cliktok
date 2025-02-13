import SwiftUI
import StripePaymentSheet

// MARK: - Supporting Views

struct TipHistoryRow: View {
    let tips: [Tip]
    let isReceived: Bool
    
    private var totalAmount: Double {
        tips.reduce(0) { $0 + $1.amount }
    }
    
    private var formattedDate: String {
        if let mostRecentTip = tips.max(by: { $0.timestamp < $1.timestamp }) {
            if tips.count > 1 {
                return "\(mostRecentTip.timestamp.formatted(date: .numeric, time: .shortened)) (\(tips.count) tips)"
            } else {
                return mostRecentTip.timestamp.formatted(date: .numeric, time: .shortened)
            }
        }
        return ""
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("$\(String(format: "%.2f", totalAmount))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                Text(formattedDate)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text("To: \(tips[0].receiverID)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

struct BalanceRow: View {
    let balance: Double
    
    var body: some View {
        HStack {
            Text("Current Balance")
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text("$\(String(format: "%.2f", balance))")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)
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
                Text("Add $\(String(format: "%.2f", amount))")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                if isPurchasing {
                    ProgressView()
                        .tint(.green)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPurchasing)
    }
}

// MARK: - Main View Sections

struct BalanceSection: View {
    let balance: Double
    
    var body: some View {
        Section {
            BalanceRow(balance: balance)
        }
    }
}

struct AddFundsSection: View {
    let tipAmounts: [Double]
    let isPurchasing: Bool
    let onAddFunds: (Double) -> Void
    
    var body: some View {
        Section("Add Funds") {
            ForEach(tipAmounts, id: \.self) { amount in
                AddFundsRow(
                    amount: amount,
                    isPurchasing: isPurchasing,
                    onTap: { onAddFunds(amount) }
                )
            }
        }
    }
}

struct TipsSection: View {
    let title: String
    let tips: [Tip]
    let isReceived: Bool
    
    private var consolidatedTips: [(id: String, tips: [Tip])] {
        let groupedTips = Dictionary(grouping: tips) { tip in
            let id = isReceived ? tip.senderID : tip.receiverID
            let timeWindow = Int(tip.timestamp.timeIntervalSince1970 / 30)
            return "\(id)-\(timeWindow)"
        }
        
        return groupedTips.map { key, tips in
            let latestTip = tips.max(by: { $0.timestamp < $1.timestamp })
            return (
                id: "\(key)-\(tips.count)-\(latestTip?.timestamp.timeIntervalSince1970 ?? 0)",
                tips: tips
            )
        }.sorted { group1, group2 in
            let latest1 = group1.tips.max(by: { $0.timestamp < $1.timestamp })?.timestamp ?? Date.distantPast
            let latest2 = group2.tips.max(by: { $0.timestamp < $1.timestamp })?.timestamp ?? Date.distantPast
            return latest1 > latest2
        }
    }
    
    var body: some View {
        Section(header: Text(title).font(.system(.headline, design: .monospaced))) {
            if tips.isEmpty {
                Text("No tips \(isReceived ? "received" : "sent")")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.gray)
            } else {
                ForEach(consolidatedTips, id: \.id) { group in
                    TipHistoryRow(tips: group.tips, isReceived: isReceived)
                }
            }
        }
    }
}

// MARK: - Main View

struct WalletView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TipViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var paymentResult: PaymentSheetResult?
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            WalletContentView(
                viewModel: viewModel,
                colorScheme: colorScheme,
                onDismiss: { dismiss() },
                isLoading: isLoading,
                paymentResult: paymentResult
            )
        }
    }
}

// MARK: - Content View

private struct WalletContentView: View {
    @ObservedObject var viewModel: TipViewModel
    let colorScheme: ColorScheme
    let onDismiss: () -> Void
    let isLoading: Bool
    let paymentResult: PaymentSheetResult?
    
    var body: some View {
        List {
            BalanceSection(balance: viewModel.balance)
            
            Section {
                Button(isLoading ? "Loading..." : "Pay with Card") {
                    Task {
                        viewModel.selectedAmount = 10.00
                        await handlePayment()
                    }
                }
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)
                .disabled(isLoading)
                
                if let result = paymentResult {
                    switch result {
                    case .completed:
                        Text("Payment completed!")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                    case .canceled:
                        Text("Payment canceled.")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.orange)
                    case .failed(let error):
                        Text("Payment failed: \(error.localizedDescription)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
            }
            
            AddFundsSection(
                tipAmounts: viewModel.tipAmounts,
                isPurchasing: viewModel.isPurchasing,
                onAddFunds: handleAddFunds
            )
            
            TipsSection(
                title: "Tips Sent",
                tips: viewModel.sentTips,
                isReceived: false
            )
        }
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(colorScheme == .dark ? Color.black : Color.white, for: .navigationBar)
        .onAppear {
            triggerDataReload()
        }
        .fullScreenCover(isPresented: $viewModel.isPaymentSheetPresented) {
            if let paymentSheet = viewModel.paymentSheet {
                PaymentSheetViewController(paymentSheet: paymentSheet) { result in
                    viewModel.isPaymentSheetPresented = false
                    Task {
                        // Handle payment completion first
                        await viewModel.handlePaymentCompletion(result)
                        
                        // Force UI refresh by reloading data
                        print("🔄 Reloading wallet data after payment")
                        await viewModel.loadBalance()
                        await viewModel.loadTipHistory()
                        
                        // Additional balance check
                        let currentBalance = viewModel.getDevelopmentBalance()
                        print("💰 Current balance after reload: \(currentBalance)")
                    }
                }
                .edgesIgnoringSafeArea(.all)
                .presentationBackground(.clear)
            }
        }
        .alert("Success", isPresented: $viewModel.showSuccessAlert) {
            Button("OK", role: .cancel) {
                onDismiss()
                triggerDataReload()
            }
            .font(.system(.body, design: .monospaced))
        } message: {
            Text("Payment successful! Your balance has been updated.")
                .font(.system(.body, design: .monospaced))
        }
    }
    
    private func loadData() async {
        await viewModel.loadBalance()
        await viewModel.loadTipHistory()
    }
    
    private func triggerDataReload() {
        Task {
            await loadData()
        }
    }
    
    private func handleAddFunds(_ amount: Double) {
        Task {
            do {
                print("💰 WalletView: Adding funds: $\(String(format: "%.2f", amount))")
                viewModel.selectedAmount = amount  // Set the amount before calling addFunds
                try await viewModel.addFunds(amount)
                await loadData()
            } catch {
                print("Payment error: \(error.localizedDescription)")
            }
        }
    }
    
    private func handlePayment() async {
        guard let amount = viewModel.selectedAmount else { return }
        
        do {
            try await viewModel.addFunds(amount)
            await loadData()
        } catch {
            print("Payment error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Payment Sheet View Controller
struct PaymentSheetViewController: UIViewControllerRepresentable {
    let paymentSheet: PaymentSheet
    let onCompletion: (PaymentSheetResult) -> Void
    
    class Coordinator: NSObject {
        let paymentSheet: PaymentSheet
        let onCompletion: (PaymentSheetResult) -> Void
        var presentationViewController: UIViewController?
        
        init(paymentSheet: PaymentSheet, onCompletion: @escaping (PaymentSheetResult) -> Void) {
            self.paymentSheet = paymentSheet
            self.onCompletion = onCompletion
            super.init()
        }
        
        func presentPaymentSheet(from viewController: UIViewController) {
            self.presentationViewController = viewController
            // Add a small delay to ensure the view controller is in the hierarchy
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, let presentationVC = self.presentationViewController else { return }
                
                self.paymentSheet.present(from: presentationVC) { result in
                    DispatchQueue.main.async {
                        self.onCompletion(result)
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(paymentSheet: paymentSheet, onCompletion: onCompletion)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        // Ensure view controller stays in memory
        viewController.view.backgroundColor = .clear
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Only present if not already presenting
        if context.coordinator.presentationViewController == nil {
            context.coordinator.presentPaymentSheet(from: uiViewController)
        }
    }
}