import SwiftUI
import UIKit

// MARK: - Terminal Content View
private struct TerminalContentView: View {
    @Binding var conversation: [(role: String, content: String)]
    @Binding var userInput: String
    @Binding var isProcessing: Bool
    @Binding var showCursor: Bool
    let processCommand: () -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // Welcome Message
                    WelcomeMessageView()
                    
                    // Conversation History
                    ConversationHistoryView(conversation: conversation)
                    
                    // Current Input Line
                    InputLineView(
                        userInput: $userInput,
                        isProcessing: isProcessing,
                        showCursor: showCursor,
                        processCommand: processCommand
                    )
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
}

// MARK: - Welcome Message View
private struct WelcomeMessageView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Welcome to CliktokOS v1.0")
                .foregroundColor(.green)
                .font(.system(.body, design: .monospaced))
            
            Text("Type 'help' for available commands")
                .foregroundColor(.green)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - Conversation History View
private struct ConversationHistoryView: View {
    let conversation: [(role: String, content: String)]
    
    var body: some View {
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
    }
}

// MARK: - Input Line View
private struct InputLineView: View {
    @Binding var userInput: String
    @FocusState private var isFocused: Bool
    let isProcessing: Bool
    let showCursor: Bool
    let processCommand: () -> Void
    
    var body: some View {
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
                .onSubmit(processCommand)
                .submitLabel(.return)
                .focused($isFocused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isFocused = true
                    }
                }
                .onDisappear {
                    isFocused = false
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            
            if showCursor && !isProcessing {
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 8, height: 20)
            }
        }
    }
}

// MARK: - Menu Overlay View
private struct MenuOverlayView: View {
    @Binding var showMenu: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.01)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    showMenu = false
                }
            
            VStack(spacing: 20) {
                MenuButton(title: "SUBMISSIONS", icon: "house.fill", action: { showMenu = false })
                MenuButton(title: "ARCHIVE", icon: "tv", action: { showMenu = false })
                MenuButton(title: "SEARCH", icon: "magnifyingglass.circle.fill", action: { showMenu = false })
                MenuButton(title: "WALLET", icon: "dollarsign.circle.fill", action: { showMenu = false })
                MenuButton(title: "UPLOAD", icon: "plus.square.fill", action: { showMenu = false })
                MenuButton(title: "PROFILE", icon: "person.fill", action: { showMenu = false })
            }
            .padding()
            .background(Color.black.opacity(0.9))
        }
    }
}

// MARK: - Menu Button
private struct MenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
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
}

// MARK: - Main Terminal View
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
                RetroStatusBar()
                
                TerminalContentView(
                    conversation: $conversation,
                    userInput: $userInput,
                    isProcessing: $isProcessing,
                    showCursor: $showCursor,
                    processCommand: processCommand
                )
            }
            
            if showMenu {
                MenuOverlayView(showMenu: $showMenu)
            }
        }
        .onReceive(timer) { _ in
            showCursor.toggle()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        )
        .task {
            await tipViewModel.loadBalance()
            await tipViewModel.loadTipHistory()
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
        case let cmd where cmd.hasPrefix("view "):
            handleViewCommand(cmd)
        case "trending":
            handleTrendingSearch()
        case "random":
            handleRandomSearch()
        case "back":
            conversation.append((role: "system", content: "Returned to previous view."))
            isProcessing = false
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
        Task { @MainActor in
            print("Starting search for query: \(query)")
            isProcessing = true
            conversation.append((role: "system", content: "Searching for: \(query)..."))
            
            // Track displayed results
            var displayedResults = Set<String>()
            var headerShown = false
            
            // Create callback
            let searchCallback: (ArchiveVideo) -> Void = { video in
                print("Callback received video: \(video.identifier)")
                Task { @MainActor in
                    if !displayedResults.contains(video.identifier) {
                        displayedResults.insert(video.identifier)
                        
                        // Show header if this is the first result
                        if !headerShown {
                            self.conversation.append((role: "system", content: """
                            ╔═══ SEARCH RESULTS ═══╗
                            Found matching videos:
                            ═══════════════════════
                            """))
                            headerShown = true
                        }
                        
                        // Add result
                        self.conversation.append((role: "system", content: """
                        [\(displayedResults.count)] \(video.title)
                        ├─ ID: \(video.identifier)
                        ├─ Description: \(video.description?.prefix(100) ?? "No description")...
                        └─ URL: \(video.videoURL)
                        ───────────────────────
                        """))
                        print("Added video to conversation")
                    }
                }
            }
            
            // Set callback and start search
            print("Setting callback")
            aiService.onResultFound = searchCallback
            print("Callback set, starting search")
            
            aiService.searchQuery = query
            await aiService.performSearch()
            
            // Clear callback
            aiService.onResultFound = nil
            
            // Show footer if results were found
            if !displayedResults.isEmpty {
                conversation.append((role: "system", content: """
                
                Commands:
                - view [number]: View video details (e.g., 'view 1')
                - play [number]: Play video
                - search [query]: New search
                """))
            } else {
                conversation.append((role: "system", content: "No results found for: \(query)"))
            }
            
            isProcessing = false
        }
    }
    
    private func handleViewCommand(_ command: String) {
        // Extract the number from the command
        let parts = command.split(separator: " ")
        guard parts.count == 2,
              let number = Int(parts[1]),
              number > 0,
              number <= aiService.searchResults.count else {
            conversation.append((role: "system", content: "Invalid view command. Usage: view [number]"))
            isProcessing = false
            return
        }
        
        // Get the video
        let video = aiService.searchResults[number - 1]
        
        // Show detailed info
        conversation.append((role: "system", content: """
        ╔═══ VIDEO DETAILS ═══╗
        Title: \(video.title)
        ID: \(video.identifier)
        
        Description:
        \(video.description ?? "No description available")
        
        URL: \(video.videoURL)
        Thumbnail: \(video.thumbnailURL ?? "No thumbnail")
        ═══════════════════════
        
        Commands:
        - play \(number): Play this video
        - back: Return to search results
        """))
        isProcessing = false
    }
    
    private func handleTrendingSearch() {
        Task { @MainActor in
            isProcessing = true
            conversation.append((role: "system", content: "Finding trending videos..."))
            
            // Track already displayed results to avoid duplicates
            var displayedResults = Set<String>()
            var headerShown = false
            
            // Set up the callback for new results
            aiService.onResultFound = { (video: ArchiveVideo) in
                Task { @MainActor in
                    if !displayedResults.contains(video.identifier) {
                        displayedResults.insert(video.identifier)
                        
                        // Show header if this is the first result
                        if !headerShown {
                            conversation.append((role: "system", content: """
                            ╔═══ TRENDING VIDEOS ═══╗
                            Found trending videos:
                            ═══════════════════════
                            """))
                            headerShown = true
                        }
                        
                        let result = """
                        [\(displayedResults.count)] \(video.title)
                        ├─ ID: \(video.identifier)
                        ├─ Description: \(video.description?.prefix(100) ?? "No description")...
                        └─ URL: \(video.videoURL)
                        ───────────────────────
                        """
                        conversation.append((role: "system", content: result))
                    }
                }
            }
            
            // Start the search
            await aiService.performSearch()
            
            // Clear the callback
            aiService.onResultFound = nil
            
            if displayedResults.isEmpty {
                conversation.append((role: "system", content: "No trending videos found."))
            } else {
                // Show footer
                conversation.append((role: "system", content: """
                
                Commands:
                - play [ID]: Play video
                - info [ID]: Show full video info
                - trending: Refresh trending videos
                """))
            }
            
            isProcessing = false
        }
    }
    
    private func handleRandomSearch() {
        Task { @MainActor in
            isProcessing = true
            conversation.append((role: "system", content: "Finding random videos..."))
            
            // Track already displayed results to avoid duplicates
            var displayedResults = Set<String>()
            var headerShown = false
            
            // Set up the callback for new results
            aiService.onResultFound = { (video: ArchiveVideo) in
                Task { @MainActor in
                    if !displayedResults.contains(video.identifier) {
                        displayedResults.insert(video.identifier)
                        
                        // Show header if this is the first result
                        if !headerShown {
                            conversation.append((role: "system", content: """
                            ╔═══ RANDOM VIDEOS ═══╗
                            Found random videos:
                            ═══════════════════════
                            """))
                            headerShown = true
                        }
                        
                        let result = """
                        [\(displayedResults.count)] \(video.title)
                        ├─ ID: \(video.identifier)
                        ├─ Description: \(video.description?.prefix(100) ?? "No description")...
                        └─ URL: \(video.videoURL)
                        ───────────────────────
                        """
                        conversation.append((role: "system", content: result))
                    }
                }
            }
            
            // Start the search
            await aiService.performSearch()
            
            // Clear the callback
            aiService.onResultFound = nil
            
            if displayedResults.isEmpty {
                conversation.append((role: "system", content: "No random videos found."))
            } else {
                // Show footer
                conversation.append((role: "system", content: """
                
                Commands:
                - play [ID]: Play video
                - info [ID]: Show full video info
                - random: Get new random videos
                """))
            }
            
            isProcessing = false
        }
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
        // Group tips by user and time window (30 second intervals)
        let allTips = (tipViewModel.receivedTips + tipViewModel.sentTips)
        
        // Group tips by user and time window
        let groupedTips = Dictionary(grouping: allTips) { tip in
            let id = tipViewModel.receivedTips.contains(where: { $0.id == tip.id }) ? tip.senderID : tip.receiverID
            let timeWindow = Int(tip.timestamp.timeIntervalSince1970 / 30)
            return "\(id)-\(timeWindow)"
        }
        
        // Convert grouped tips to sorted array
        let consolidatedTips = groupedTips.map { key, tips in
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
        
        if consolidatedTips.isEmpty {
            return "No recent transactions"
        }
        
        // Format each group
        return consolidatedTips.prefix(5).map { group in
            let totalAmount = group.tips.reduce(0) { $0 + $1.amount }
            let isReceived = tipViewModel.receivedTips.contains(where: { $0.id == group.tips[0].id })
            let type = isReceived ? "+" : "-"
            let date = group.tips[0].timestamp.formatted(date: .numeric, time: .shortened)
            let userID = isReceived ? group.tips[0].senderID : group.tips[0].receiverID
            let countSuffix = group.tips.count > 1 ? " (\(group.tips.count) tips)" : ""
            
            return "\(type)$\(String(format: "%.2f", totalAmount)) from \(userID) at \(date)\(countSuffix)"
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