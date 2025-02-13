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
                MenuButton(title: "COLLECTIONS", icon: "tv", action: { showMenu = false })
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
    @State private var showVideoPlayer = false
    @State private var selectedVideo: Video?
    @StateObject private var aiService = AISearchViewModel()
    @StateObject private var tipViewModel = TipViewModel.shared
    @StateObject private var feedViewModel = VideoFeedViewModel()
    @StateObject private var archiveViewModel = ArchiveVideoViewModel()
    @Environment(\.dismiss) private var dismiss
    
    let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    RetroStatusBar()
                        .frame(height: 44)
                        .ignoresSafeArea(.container, edges: .top)
                    
                    TerminalContentView(
                        conversation: $conversation,
                        userInput: $userInput,
                        isProcessing: $isProcessing,
                        showCursor: $showCursor,
                        processCommand: processCommand
                    )
                }
                .edgesIgnoringSafeArea(.top)
                
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
            .sheet(isPresented: $showVideoPlayer) {
                if let video = selectedVideo {
                    VideoPlayerView(
                        video: video,
                        showBackButton: true,
                        clearSearchOnDismiss: .constant(false),
                        isVisible: .constant(true),
                        showCreator: true
                    )
                    .environmentObject(feedViewModel)
                }
            }
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
        case "play 0":
            // Play test pattern video
            let testVideo = Video(
                id: nil,
                archiveIdentifier: "big_buck_bunny",
                userID: "archive_user",
                videoURL: "https://archive.org/download/BigBuckBunny_328/BigBuckBunny_512kb.mp4",
                thumbnailURL: nil,
                caption: "Big Buck Bunny",
                description: "Big Buck Bunny - Classic open source animation",
                hashtags: ["test"],
                createdAt: Date(),
                likes: 0,
                views: 0
            )
            selectedVideo = testVideo
            showVideoPlayer = true
            conversation.append((role: "system", content: "Playing test video: Big Buck Bunny"))
            isProcessing = false
        case let cmd where cmd.hasPrefix("play "):
            handlePlayCommand(cmd)
        case let cmd where cmd.hasPrefix("view "):
            handleViewCommand(cmd)
        case "random":
            handleRandomSearch()
        case "back":
            conversation.append((role: "system", content: "Returned to previous view."))
            isProcessing = false
        case "more":
            let currentBatchStart = (aiService.searchResults.count / 5) * 5
            showResultsBatch(startIndex: currentBatchStart)
        default:
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
        - random: Show random videos
        - play [number]: Play video from search results
        
        Type 'search' or 'wallet' for more specific help.
        """
        conversation.append((role: "system", content: helpMessage))
        isProcessing = false
    }
    
    private func showSearchHelp() {
        let searchHelp = """
        Search Commands:
        ═══════════════
        
        1. Natural Language Search:
           search [query]
           Examples:
           - search funny cat videos from the 90s
           - search educational documentaries about space
           - search classic movies from 1950 to 1960
           - search viral dance videos from 2020s
        
        2. Random Videos:
           random
        
        The AI will understand:
        - Time periods (90s, 2000s, specific years)
        - Content types (movies, documentaries)
        - Genres (funny, educational, classic)
        - Subjects (cats, space, dance)
        
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
            var allResults: [ArchiveVideo] = []
            
            // Show initial results one by one through callback
            let searchCallback: (ArchiveVideo) -> Void = { video in
                print("Callback received video: \(video.identifier)")
                Task { @MainActor in
                    if video.identifier == "CLEAR_RESULTS" {
                        // Add a separator between initial and ranked results
                        self.conversation.append((role: "system", content: """
                        
                        ═══════════════════════
                        Ranking results by relevance...
                        ═══════════════════════
                        
                        ╔═══ RANKED RESULTS ═══╗
                        Most relevant matches:
                        ═══════════════════════
                        """))
                        // Reset the counter for ranked results
                        displayedResults.removeAll()
                    } else if video.identifier == "END_RANKED_RESULTS" {
                        // Add commands after all ranked results are shown
                        self.conversation.append((role: "system", content: """
                        
                        ═══════════════════════
                        Available Commands:
                        - view [number]: View video details (e.g., 'view 1')
                        - play [number]: Play video
                        - search [query]: New search
                        """))
                    } else {
                        self.conversation.append((role: "system", content: """
                        [\(displayedResults.count + 1)] \(video.title)
                        ├─ ID: \(video.identifier)
                        └─ Description: \(video.description?.prefix(100) ?? "No description")...
                        """))
                        displayedResults.insert(video.identifier)
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
            
            // Check for error message
            if let error = aiService.errorMessage {
                conversation.append((role: "system", content: error))
                isProcessing = false
                return
            } else if displayedResults.isEmpty && !aiService.isLoading {
                conversation.append((role: "system", content: "No results found for: \(query)"))
                isProcessing = false
                return
            }
            
            // If we have results, process them with AI
            if !allResults.isEmpty {
                conversation.append((role: "system", content: """
                
                Found \(allResults.count) videos. Ranking by relevance...
                """))
                await processResultsWithAI(allResults, query: query)
            }
            
            isProcessing = false
        }
    }
    
    private func processResultsWithAI(_ videos: [ArchiveVideo], query: String) async {
        // Use AISearchService to rank results
        do {
            let taskId = UUID()
            let rankedResults = try await AISearchService.shared.searchAndRankVideos(videos, query: query, taskId: taskId)
            
            // Update search results for play/view commands
            aiService.searchResults = rankedResults
            
            // Show first batch of results
            showResultsBatch(startIndex: 0)
            
        } catch let error as AISearchError {
            conversation.append((role: "system", content: "AI Ranking Error: \(error.localizedDescription)"))
        } catch {
            conversation.append((role: "system", content: "Unexpected error during ranking: \(error.localizedDescription)"))
        }
    }
    
    private func showResultsBatch(startIndex: Int) {
        guard startIndex < aiService.searchResults.count else {
            conversation.append((role: "system", content: "No more results to show."))
            return
        }
        
        let endIndex = min(startIndex + 5, aiService.searchResults.count)
        let isFirstBatch = startIndex == 0
        let hasMoreResults = endIndex < aiService.searchResults.count
        
        // Show header
        conversation.append((role: "system", content: """
        
        ╔═══ RANKED RESULTS (\(startIndex + 1)-\(endIndex) of \(aiService.searchResults.count)) ═══╗
        Most relevant matches:
        ═══════════════════════
        """))
        
        // Display results batch
        for index in startIndex..<endIndex {
            let video = aiService.searchResults[index]
            conversation.append((role: "system", content: """
            [\(index + 1)] \(video.title)
            ├─ ID: \(video.identifier)
            └─ Description: \(video.description?.prefix(100) ?? "No description")...
            """))
        }
        
        // Show footer with appropriate commands
        var commandsText = """
        ═══════════════════════
        Available Commands:
        - view [number]: View video details (e.g., 'view 1')
        - play [number]: Play video
        - search [query]: New search
        """
        
        if hasMoreResults {
            commandsText += "\n- more: Show next 5 results"
        }
        
        conversation.append((role: "system", content: commandsText))
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
    
    private func handleRandomSearch() {
        Task { @MainActor in
            isProcessing = true
            conversation.append((role: "system", content: "Finding random videos..."))
            
            do {
                // Use a random sort and basic video filters
                let randomQuery = """
                (mediatype:movies OR mediatype:movingimage) AND \
                -collection:test_videos AND \
                (format:mp4 OR format:h.264 OR format:512kb)
                """
                
                let results = try await InternetArchiveAPI.shared.fetchCollectionItems(
                    query: randomQuery,
                    offset: Int.random(in: 0...100),  // Random offset for variety
                    limit: 10
                )
                
                // Store results in AISearchViewModel for play/view commands
                aiService.searchResults = results
                
                // Show results
                if results.isEmpty {
                    conversation.append((role: "system", content: "No random videos found."))
                } else {
                    conversation.append((role: "system", content: """
                    ╔═══ RANDOM VIDEOS ═══╗
                    Found \(results.count) random videos:
                    ═══════════════════════
                    """))
                    
                    // Display each result
                    for (index, video) in results.enumerated() {
                        conversation.append((role: "system", content: """
                        [\(index + 1)] \(video.title)
                        ├─ ID: \(video.identifier)
                        └─ Description: \(video.description?.prefix(100) ?? "No description")...
                        """))
                    }
                    
                    // Show footer
                    conversation.append((role: "system", content: """
                    
                    Commands:
                    - play [number]: Play video
                    - view [number]: Show full video info
                    - random: Get new random videos
                    """))
                }
            } catch {
                conversation.append((role: "system", content: "Error finding random videos: \(error.localizedDescription)"))
            }
            
            isProcessing = false
        }
    }
    
    private func handlePlayCommand(_ command: String) {
        // Extract the number from the command
        let parts = command.split(separator: " ")
        guard parts.count == 2,
              let number = Int(parts[1]),
              number > 0,
              number <= aiService.searchResults.count else {
            conversation.append((role: "system", content: "Invalid play command. Usage: play [number]"))
            isProcessing = false
            return
        }
        
        // Get the archive video
        let archiveVideo = aiService.searchResults[number - 1]
        
        // Convert ArchiveVideo to Video
        let video = Video(
            id: nil,
            archiveIdentifier: archiveVideo.identifier,
            userID: "archive_user",
            videoURL: archiveVideo.videoURL,
            thumbnailURL: archiveVideo.thumbnailURL,
            caption: archiveVideo.title,
            description: archiveVideo.description,
            hashtags: ["archive"],
            createdAt: Date(),
            likes: 0,
            views: 0
        )
        
        selectedVideo = video
        showVideoPlayer = true
        
        conversation.append((role: "system", content: "Playing video: \(video.caption)"))
        isProcessing = false
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