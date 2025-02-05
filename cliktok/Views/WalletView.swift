import SwiftUI
import StoreKit

// Product Row Component
private struct ProductRowView: View {
    let product: Product
    let isPurchasing: Bool
    let onPurchase: () async throws -> Void
    @Binding var showError: Bool
    @Binding var errorMessage: String
    
    var body: some View {
        Button(action: {
            Task {
                do {
                    try await onPurchase()
                } catch {
                    showError = true
                    errorMessage = error.localizedDescription
                }
            }
        }) {
            HStack {
                VStack(alignment: .leading) {
                    Text(product.displayName)
                        .foregroundColor(.primary)
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(product.displayPrice)
                        .foregroundColor(.blue)
                        .bold()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }
}

// Tip History Row Component
private struct TipHistoryRowView: View {
    let tip: Tip
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Tip Sent")
                    .font(.subheadline)
                    .foregroundColor(.black)
                Text(tip.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text("$\(tip.amount, specifier: "%.2f")")
                .bold()
                .foregroundColor(.black)
        }
    }
}

struct WalletView: View {
    @StateObject private var tipViewModel = TipViewModel()
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        List {
            // Balance Section
            Section {
                HStack {
                    Text("Current Balance")
                        .foregroundColor(.black)
                    Spacer()
                    Text("$\(tipViewModel.balance, specifier: "%.2f")")
                        .bold()
                        .foregroundColor(.black)
                }
            } header: {
                Text("Balance")
                    .foregroundColor(.black)
            }
            
            // Add Funds Section
            Section {
                if ProductsManager.shared.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if tipViewModel.products.isEmpty {
                    Text("No products available")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(tipViewModel.products, id: \.id) { product in
                        ProductRowView(
                            product: product,
                            isPurchasing: tipViewModel.isPurchasing,
                            onPurchase: {
                                try await tipViewModel.purchaseCoins(product)
                            },
                            showError: $showError,
                            errorMessage: $errorMessage
                        )
                    }
                }
            } header: {
                Text("Add Funds")
                    .foregroundColor(.black)
            } footer: {
                Text("Purchase coins to tip your favorite creators")
                    .foregroundColor(.gray)
            }
            
            // Tip History Section
            Section {
                if tipViewModel.tipHistory.isEmpty {
                    Text("No tips sent yet")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(tipViewModel.tipHistory) { tip in
                        TipHistoryRowView(tip: tip)
                    }
                }
            } header: {
                Text("Recent Tips")
                    .foregroundColor(.black)
            }
        }
        .navigationTitle("Wallet")
        .background(Color.white)
        .scrollContentBackground(.hidden)
        .refreshable {
            Task {
                await ProductsManager.shared.loadProducts()
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
            await ProductsManager.shared.loadProducts()
            await tipViewModel.loadBalance()
            await tipViewModel.loadTipHistory()
        }
    }
} 