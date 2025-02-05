import SwiftUI
import OSLog

struct TestDataView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var isLoading = false
    @State private var error: Error?
    private let logger = Logger(subsystem: "gauntletai.cliktok", category: "TestDataView")
    
    var body: some View {
        NavigationView {
            List {
                if !networkMonitor.isConnected {
                    Section {
                        HStack {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.red)
                            Text("No Internet Connection")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        logger.debug("Test Firebase Connection button tapped")
                        Task {
                            await testFirebaseConnection()
                        }
                    }) {
                        HStack {
                            Text("Test Firebase Connection")
                            Spacer()
                            if isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoading || !networkMonitor.isConnected)
                }
                
                Section {
                    Button(action: {
                        logger.debug("Add Single Video button tapped")
                        Task {
                            await addSingleVideo()
                        }
                    }) {
                        HStack {
                            Text("Add Single Sample Video")
                            Spacer()
                            if isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoading || !networkMonitor.isConnected)
                    
                    Button(action: {
                        logger.debug("Add Multiple Videos button tapped")
                        Task {
                            await addMultipleVideos()
                        }
                    }) {
                        HStack {
                            Text("Add 5 Sample Videos")
                            Spacer()
                            if isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoading || !networkMonitor.isConnected)
                }
                
                if let error = error {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Error")
                                .font(.headline)
                                .foregroundColor(.red)
                            Text(error.localizedDescription)
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section {
                    HStack {
                        Text("Network Status")
                        Spacer()
                        Label(
                            networkMonitor.isConnected ? "Connected" : "Offline",
                            systemImage: networkMonitor.isConnected ? "wifi" : "wifi.slash"
                        )
                        .foregroundColor(networkMonitor.isConnected ? .green : .red)
                    }
                    
                    if networkMonitor.isConnected {
                        HStack {
                            Text("Connection Type")
                            Spacer()
                            Text(connectionTypeString)
                        }
                    }
                }
            }
            .navigationTitle("Test Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var connectionTypeString: String {
        switch networkMonitor.connectionType {
        case .wifi:
            return "WiFi"
        case .cellular:
            return "Cellular"
        case .ethernet:
            return "Ethernet"
        case .unknown:
            return "Unknown"
        }
    }
    
    private func testFirebaseConnection() async {
        isLoading = true
        error = nil
        
        do {
            try await TestDataManager.shared.testFirebaseConnection()
            logger.debug("Firebase connection test successful")
        } catch {
            logger.error("Firebase connection test failed: \(error.localizedDescription)")
            self.error = error
        }
        
        isLoading = false
    }
    
    private func addSingleVideo() async {
        logger.debug("Starting single video upload")
        guard networkMonitor.isConnected else {
            logger.error("No network connection")
            error = NSError(
                domain: "NetworkError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No internet connection available"]
            )
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            try await TestDataManager.shared.addSampleVideo()
            logger.debug("Single video upload completed successfully")
        } catch {
            logger.error("Failed to upload single video: \(error.localizedDescription)")
            self.error = error
        }
        
        isLoading = false
    }
    
    private func addMultipleVideos() async {
        logger.debug("Starting multiple videos upload")
        guard networkMonitor.isConnected else {
            logger.error("No network connection")
            error = NSError(
                domain: "NetworkError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No internet connection available"]
            )
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            try await TestDataManager.shared.addMultipleSampleVideos()
            logger.debug("Multiple videos upload completed successfully")
        } catch {
            logger.error("Failed to upload multiple videos: \(error.localizedDescription)")
            self.error = error
        }
        
        isLoading = false
    }
} 