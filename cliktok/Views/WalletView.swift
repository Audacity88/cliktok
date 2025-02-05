import SwiftUI

struct WalletView: View {
    @StateObject private var tipViewModel = TipViewModel()
    @State private var showAddFundsSheet = false
    @State private var fundAmount: Double = 1.00
    
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
                
                Button(action: { showAddFundsSheet = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Funds")
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            } header: {
                Text("Balance")
                    .foregroundColor(.black)
            }
            
            // Tip History Section
            Section {
                if tipViewModel.tipHistory.isEmpty {
                    Text("No tips sent yet")
                        .foregroundColor(.gray)
                } else {
                    ForEach(tipViewModel.tipHistory) { tip in
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
                await tipViewModel.loadBalance()
                await tipViewModel.loadTipHistory()
            }
        }
        .sheet(isPresented: $showAddFundsSheet) {
            NavigationView {
                Form {
                    Section {
                        Picker("Amount", selection: $fundAmount) {
                            Text("$1.00").tag(1.00)
                            Text("$5.00").tag(5.00)
                            Text("$10.00").tag(10.00)
                            Text("$20.00").tag(20.00)
                        }
                    } header: {
                        Text("Select Amount")
                            .foregroundColor(.black)
                    }
                    
                    Section {
                        Button(action: {
                            Task {
                                do {
                                    try await tipViewModel.addFunds(fundAmount)
                                    showAddFundsSheet = false
                                } catch {
                                    // Handle error
                                }
                            }
                        }) {
                            HStack {
                                Spacer()
                                Text("Add \(fundAmount, specifier: "$%.2f")")
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                        }
                        .disabled(tipViewModel.isProcessing)
                    }
                }
                .navigationTitle("Add Funds")
                .navigationBarItems(trailing: Button("Cancel") {
                    showAddFundsSheet = false
                })
            }
        }
        .task {
            await tipViewModel.loadBalance()
            await tipViewModel.loadTipHistory()
        }
    }
} 