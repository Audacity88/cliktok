import SwiftUI
import StripePaymentSheet

// MARK: - Supporting Views

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
    
    var body: some View {
        Section(title) {
            if tips.isEmpty {
                Text("No tips \(isReceived ? "received" : "sent")")
                    .foregroundColor(.secondary)
            } else {
                ForEach(tips) { tip in
                    TipHistoryRow(tip: tip, isReceived: isReceived)
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
                        // Set a default amount of $10.00
                        viewModel.selectedAmount = 10.00
                        await handlePayment()
                    }
                }
                .disabled(isLoading)
                
                if let result = paymentResult {
                    switch result {
                    case .completed:
                        Text("Payment completed!")
                            .foregroundColor(.green)
                    case .canceled:
                        Text("Payment canceled.")
                            .foregroundColor(.orange)
                    case .failed(let error):
                        Text("Payment failed: \(error.localizedDescription)")
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
                title: "Tips Received",
                tips: viewModel.receivedTips,
                isReceived: true
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
        .onAppear(perform: loadData)
        .fullScreenCover(isPresented: $viewModel.isPaymentSheetPresented) {
            if let paymentSheet = viewModel.paymentSheet {
                PaymentSheetViewController(paymentSheet: paymentSheet) { result in
                    viewModel.isPaymentSheetPresented = false
                    Task {
                        await viewModel.handlePaymentCompletion(result)
                    }
                }
                .edgesIgnoringSafeArea(.all)
                .presentationBackground(.clear)
            }
        }
        .alert("Success", isPresented: $viewModel.showSuccessAlert) {
            Button("OK", role: .cancel) {
                onDismiss()
            }
        } message: {
            Text("Payment successful! Your balance has been updated.")
        }
    }
    
    private func loadData() {
        Task {
            await viewModel.loadBalance()
            await viewModel.loadTipHistory()
        }
    }
    
    private func handleAddFunds(_ amount: Double) {
        Task {
            try? await viewModel.addFunds(amount)
        }
    }
    
    private func handlePayment() async {
        guard let amount = viewModel.selectedAmount else { return }
        
        do {
            try await viewModel.addFunds(amount)
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