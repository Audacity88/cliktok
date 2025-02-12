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
    private let logger = Logger(component: "AppDelegate")
    
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        logger.info("🚀 App launch started")
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
            logger.performance("💾 Initial memory usage: \(String(format: "%.2f", usedMB))MB")
        } else {
            logger.warning("⚠️ Could not get memory usage information")
        }
        
        logger.info("🔥 Configuring Firebase...")
        FirebaseConfig.shared.configure()
        
        // Check initial auth state
        let authState = FirebaseConfig.shared.checkAuthState()
        logger.info("👤 Initial auth state: \(String(describing: authState))")
        
        logger.success("✅ App initialization complete")
        return true
    }
}

@main
struct cliktokApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthenticationManager.shared
    private let logger = Logger(component: "cliktokApp")
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    logger.debug("🔗 Handling URL callback: \(url)")
                    // Handle Stripe return URL
                    let stripeHandled = StripeAPI.handleURLCallback(with: url)
                    if stripeHandled {
                        logger.debug("✅ URL handled by Stripe")
                    } else {
                        logger.debug("⏭️ URL not handled by Stripe, skipping")
                    }
                }
        }
    }
}
