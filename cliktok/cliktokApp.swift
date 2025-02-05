//
//  cliktokApp.swift
//  cliktok
//
//  Created by Daniel Gilles on 2/4/25.
//

import SwiftUI
import FirebaseCore
import OSLog
import StoreKit

class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "com.cliktok", category: "AppDelegate")
    
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        logger.debug("Configuring Firebase...")
        FirebaseCore.FirebaseApp.configure()
        logger.debug("Firebase configuration completed")
        return true
    }
}

@main
struct cliktokApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var productsManager = ProductsManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(productsManager)
        }
    }
}
