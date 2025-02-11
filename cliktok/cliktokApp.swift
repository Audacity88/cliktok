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

class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "gauntletai.cliktok", category: "AppDelegate")
    
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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
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
