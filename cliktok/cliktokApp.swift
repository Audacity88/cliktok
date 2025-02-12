//
//  cliktokApp.swift
//  cliktok
//
//  Created by Daniel Gilles on 2/4/25.
//

import SwiftUI
import FirebaseCore
import OSLog
import StripePaymentSheet
import FirebaseAuth
import FirebaseFirestore

class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "gauntletai.cliktok", category: "AppDelegate")
    
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        logger.debug("🚀 App launch started")
        logger.debug("📱 Device: \(UIDevice.current.name), iOS \(UIDevice.current.systemVersion)")
        logger.debug("🏗️ Starting app initialization...")
        
        // Log memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            logger.debug("💾 Initial memory usage: \(String(format: "%.2f", usedMB))MB")
        }
        
        logger.debug("🔥 Configuring Firebase...")
        FirebaseCore.FirebaseApp.configure()
        logger.debug("✅ Firebase configuration completed")
        
        return true
    }
}

@main
struct cliktokApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    // Handle Stripe return URL
                    let stripeHandled = StripeAPI.handleURLCallback(with: url)
                    if !stripeHandled {
                        // Handle other URL schemes if needed
                    }
                }
        }
    }
}
