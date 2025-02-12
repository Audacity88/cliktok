import SwiftUI

struct TerminalView: View {
    @State private var userInput = ""
    @State private var conversation: [(role: String, content: String)] = []
    @State private var isProcessing = false
    @State private var showCursor = true
    @State private var showMenu = false
    @StateObject private var aiService = AISearchViewModel()
    @StateObject private var tipViewModel = TipViewModel.shared
    @Environment(\.dismiss) private var dismiss
    
    let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Terminal Header
                RetroStatusBar()
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            // Welcome Message
                            Text("Welcome to CliktokOS v1.0")
                                .foregroundColor(.green)
                                .font(.system(.body, design: .monospaced))
                            
                            Text("Type 'help' for available commands")
                                .foregroundColor(.green)
                                .font(.system(.body, design: .monospaced))
                            
                            // Conversation History
                            ForEach(conversation.indices, id: \.self) { index in
                                VStack(alignment: .leading) {
                                    if conversation[index].role == "user" {
                                        Text("> \(conversation[index].content)")
                                            .foregroundColor(.green)
                                    } else {
                                        Text(conversation[index].content)
                                            .foregroundColor(.green)
                                    }
                                }
                                .font(.system(.body, design: .monospaced))
                            }
                            
                            // Current Input Line
                            HStack(spacing: 2) {
                                Text(">")
                                    .foregroundColor(.green)
                                    .font(.system(.body, design: .monospaced))
                                
                                TextField("", text: $userInput)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(.green)
                                    .font(.system(.body, design: .monospaced))
                                    .background(Color.clear)
                                    .accentColor(.green)
                                    .onSubmit {
                                        processCommand()
                                    }
                                    .submitLabel(.return)
                                    .onAppear {
                                        // Focus the text field when it appears
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            UIApplication.shared.sendAction(#selector(UIResponder.becomeFirstResponder), to: nil, from: nil, for: nil)
                                        }
                                    }
                                
                                if showCursor && !isProcessing {
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 20)
                                }
                            }
                            .id("inputLine")
                        }
                        .padding()
                    }
                    .onChange(of: conversation.count) { _ in
                        withAnimation {
                            proxy.scrollTo("inputLine")
                        }
                    }
                }
            }
            
            // Menu Overlay
            if showMenu {
                Color.black.opacity(0.01)  // Invisible overlay to catch taps
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        showMenu = false
                    }
                
                VStack(spacing: 20) {
                    menuButton(title: "SUBMISSIONS", icon: "house.fill") {
                        // Navigate to submissions
                        showMenu = false
                    }
                    menuButton(title: "ARCHIVE", icon: "tv") {
                        // Navigate to archive
                        showMenu = false
                    }
                    menuButton(title: "SEARCH", icon: "sparkles.magnifyingglass") {
                        // Navigate to search
                        showMenu = false
                    }
                    menuButton(title: "WALLET", icon: "dollarsign.circle.fill") {
                        // Navigate to wallet
                        showMenu = false
                    }
                    menuButton(title: "UPLOAD", icon: "plus.square.fill") {
                        // Navigate to upload
                        showMenu = false
                    }
                    menuButton(title: "PROFILE", icon: "person.fill") {
                        // Navigate to profile
                        showMenu = false
                    }
                }
                .padding()
                .background(Color.black.opacity(0.9))
            }
        }
        .onReceive(timer) { _ in
            showCursor.toggle()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    // Dismiss keyboard when tapping outside the text field
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        )
        .task {
            await tipViewModel.loadBalance()
            await tipViewModel.loadTipHistory()
        }
    }
    
    private func menuButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.green)
                Text(title)
                    .foregroundColor(.green)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green, lineWidth: 1)
            )
        }
    }
    
    private func processCommand() {
        guard !userInput.isEmpty else { return }
        
        let command = userInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        conversation.append((role: "user", content: userInput))
        userInput = ""
        isProcessing = true
        
        switch command {
        case "help":
            showHelpMessage()
        case "menu":
            showMenu.toggle()
            isProcessing = false
        case "clear":
            conversation.removeAll()
            isProcessing = false
        case "wallet":
            showWalletInfo()
        case let cmd where cmd.hasPrefix("add "):
            let trimmedCommand = String(cmd.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            handleAddFunds(command: trimmedCommand)
        case "search":
            showSearchHelp()
        case let cmd where cmd.hasPrefix("search "):
            let query = String(cmd.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            handleSearch(query: query)
        case "trending":
            handleTrendingSearch()
        case "random":
            handleRandomSearch()
        default:
            // No longer process as AI query by default
            conversation.append((role: "system", content: "Unknown command. Type 'help' for available commands."))
            isProcessing = false
        }
    }
    
    private func showHelpMessage() {
        let helpMessage = """
        Available commands:
        - help: Show this message
        - menu: Toggle app menu
        - clear: Clear conversation
        - wallet: Show wallet balance and transactions
        
        Search commands:
        - search [query]: Search for videos
        - trending: Show trending videos
        - random: Show random videos
        
        Type 'search' or 'wallet' for more specific help.
        """
        conversation.append((role: "system", content: helpMessage))
        isProcessing = false
    }
    
    private func showSearchHelp() {
        let searchHelp = """
        Search Commands:
        ═══════════════
        
        1. Basic Search:
           search [query]
           Example: search funny cats
        
        2. Trending Videos:
           trending
        
        3. Random Videos:
           random
        
        Results will show:
        - Title
        - Description
        - Views & Tips
        """
        conversation.append((role: "system", content: searchHelp))
        isProcessing = false
    }
    
    private func handleSearch(query: String) {
        Task {
            await aiService.performSearch()
            
            if aiService.searchResults.isEmpty {
                conversation.append((role: "system", content: "No results found for: \(query)"))
            } else {
                let formattedResults = formatSearchResults(aiService.searchResults)
                conversation.append((role: "system", content: formattedResults))
            }
            isProcessing = false
        }
    }
    
    private func handleTrendingSearch() {
        Task {
            // For now, just use regular search with "trending" query
            await aiService.performSearch()
            
            if aiService.searchResults.isEmpty {
                conversation.append((role: "system", content: "No trending videos found."))
            } else {
                let header = "╔═══ TRENDING VIDEOS ═══╗\n"
                let results = formatSearchResults(aiService.searchResults)
                conversation.append((role: "system", content: header + results))
            }
            isProcessing = false
        }
    }
    
    private func handleRandomSearch() {
        Task {
            // For now, just use regular search with "random" query
            await aiService.performSearch()
            
            if aiService.searchResults.isEmpty {
                conversation.append((role: "system", content: "No random videos found."))
            } else {
                let header = "╔═══ RANDOM SELECTION ═══╗\n"
                let results = formatSearchResults(aiService.searchResults)
                conversation.append((role: "system", content: header + results))
            }
            isProcessing = false
        }
    }
    
    private func formatSearchResults(_ videos: [ArchiveVideo]) -> String {
        let header = """
        Found \(videos.count) results:
        ═══════════════════════
        
        """
        
        let results = videos.prefix(5).enumerated().map { (index, video) in
            """
            [\(index + 1)] \(video.title)
            └─ \(video.description?.prefix(100) ?? "No description")...
            └─ ID: \(video.id)
            ───────────────────────
            """
        }.joined(separator: "\n")
        
        let footer = "\nType 'search [query]' to search again"
        
        return header + results + footer
    }
    
    private func showWalletInfo() {
        Task {
            // Reload latest data
            await tipViewModel.loadBalance()
            await tipViewModel.loadTipHistory()
            
            let balance = String(format: "%.2f", tipViewModel.balance)
            let receivedCount = tipViewModel.receivedTips.count
            let sentCount = tipViewModel.sentTips.count
            
            let walletInfo = """
            ╔════ WALLET INFO ════╗
            ║ Balance: $\(balance)
            ║ Tips Received: \(receivedCount)
            ║ Tips Sent: \(sentCount)
            ╚═══════════════════════
            
            Recent Transactions:
            \(formatRecentTransactions())
            
            Wallet Commands:
            - add [amount]: Add funds (e.g., 'add 10')
            - wallet: Show this info
            """
            
            conversation.append((role: "system", content: walletInfo))
            isProcessing = false
        }
    }
    
    private func formatRecentTransactions() -> String {
        let allTips = (tipViewModel.receivedTips + tipViewModel.sentTips)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(5)
        
        if allTips.isEmpty {
            return "No recent transactions"
        }
        
        return allTips.map { tip in
            let type = tipViewModel.receivedTips.contains(where: { $0.id == tip.id }) ? "+" : "-"
            let date = tip.timestamp.formatted(date: .abbreviated, time: .shortened)
            return "\(type)$\(String(format: "%.2f", tip.amount)) (\(date))"
        }.joined(separator: "\n")
    }
    
    private func handleAddFunds(command: String) {
        guard let amount = Double(command) else {
            conversation.append((role: "system", content: "Invalid amount. Usage: add [amount]"))
            isProcessing = false
            return
        }
        
        // Set the amount in the view model
        tipViewModel.selectedAmount = amount
        
        conversation.append((role: "system", content: """
        Opening payment sheet for $\(String(format: "%.2f", amount))...
        Use the 'wallet' command to check your updated balance after payment.
        """))
        
        // Present the payment sheet
        tipViewModel.isPaymentSheetPresented = true
        isProcessing = false
    }
} 