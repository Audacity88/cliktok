import StoreKit
import FirebaseFirestore
import OSLog

@MainActor
class ProductsManager: ObservableObject {
    static let shared = ProductsManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseInProgress = false
    @Published private(set) var isLoading = true
    @Published private(set) var lastError: String?
    
    private let productIdentifiers = Set([
        "com.cliktok.coins.1",
        "com.cliktok.coins.5"
    ])
    
    private let logger = Logger(subsystem: "com.cliktok", category: "ProductsManager")
    
    private init() {
        print("🛍️ ProductsManager initialized")
        self.logger.debug("ProductsManager initialized")
        
        // Start loading products
        Task {
            do {
                try await self.loadProducts()
            } catch {
                print("❌ Initial product load failed: \(error.localizedDescription)")
                self.logger.error("Initial product load failed: \(error.localizedDescription)")
            }
        }
    }
    
    func loadProducts() async throws {
        print("🛍️ Starting to load products...")
        self.logger.debug("Starting to load products...")
        self.isLoading = true
        self.lastError = nil
        
        defer { self.isLoading = false }
        
        do {
            // Request products from StoreKit
            print("🛍️ Requesting products for identifiers: \(self.productIdentifiers)")
            self.logger.debug("Requesting products for identifiers: \(self.productIdentifiers)")
            
            let storeProducts = try await Product.products(for: self.productIdentifiers)
            print("🛍️ Raw StoreKit response received with \(storeProducts.count) products")
            
            // Sort products by price
            self.products = storeProducts.sorted { $0.price < $1.price }
            
            if self.products.isEmpty {
                let error = "No products returned from StoreKit"
                print("❌ \(error)")
                self.logger.error("\(error)")
                self.lastError = error
            } else {
                print("✅ Successfully loaded \(self.products.count) products:")
                self.logger.debug("Successfully loaded \(self.products.count) products:")
                for product in self.products {
                    print("📦 Product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
                    self.logger.debug("Product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
                }
            }
        } catch {
            print("❌ Failed to load products: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
            self.logger.error("Failed to load products: \(error.localizedDescription)")
            self.lastError = error.localizedDescription
            self.products = []
            throw error
        }
    }
    
    func purchase(_ product: Product) async throws -> Bool {
        guard !self.purchaseInProgress else {
            self.logger.warning("Purchase already in progress")
            return false
        }
        
        self.purchaseInProgress = true
        defer { self.purchaseInProgress = false }
        
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            self.logger.error("User not authenticated")
            throw NSError(domain: "Purchase", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        do {
            self.logger.debug("Starting purchase for product: \(product.id)")
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Verify the transaction
                let transaction = try self.checkVerified(verification)
                
                // Get the amount from the product identifier
                let amountString = product.id.split(separator: ".").last ?? "0"
                guard let amount = Double(amountString) else {
                    self.logger.error("Invalid product identifier format: \(product.id)")
                    throw NSError(domain: "Purchase", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid product format"])
                }
                
                // Add funds to user's wallet
                try await self.addFundsToWallet(userId: userId, amount: amount)
                
                // Finish the transaction
                await transaction.finish()
                self.logger.debug("Successfully completed purchase for product: \(product.id)")
                return true
                
            case .userCancelled:
                self.logger.debug("User cancelled purchase for product: \(product.id)")
                return false
                
            case .pending:
                self.logger.debug("Purchase pending for product: \(product.id)")
                return false
                
            @unknown default:
                self.logger.error("Unknown purchase result for product: \(product.id)")
                return false
            }
        } catch {
            self.logger.error("Purchase failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            self.logger.error("Transaction verification failed")
            throw NSError(domain: "Purchase", code: 400, userInfo: [NSLocalizedDescriptionKey: "Transaction verification failed"])
        case .verified(let safe):
            return safe
        }
    }
    
    private func addFundsToWallet(userId: String, amount: Double) async throws {
        let db = Firestore.firestore()
        
        let transaction = Transaction(
            userID: userId,
            type: .deposit,
            amount: amount,
            status: .completed,
            description: "Added \(amount) coins via in-app purchase"
        )
        
        let batch = db.batch()
        
        do {
            // Add transaction
            let transactionRef = db.collection("transactions").document(transaction.id)
            try batch.setData(from: transaction, forDocument: transactionRef)
            
            // Update balance
            let userRef = db.collection("users").document(userId)
            batch.updateData(["balance": FieldValue.increment(amount)], forDocument: userRef)
            
            try await batch.commit()
            self.logger.debug("Successfully added \(amount) to wallet for user: \(userId)")
        } catch {
            self.logger.error("Failed to add funds to wallet: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Debug helper
    func reloadProducts() async {
        print("🔄 Manually reloading products...")
        self.logger.debug("Manually reloading products...")
        do {
            try await loadProducts()
        } catch {
            print("❌ Manual reload failed: \(error.localizedDescription)")
            self.logger.error("Manual reload failed: \(error.localizedDescription)")
        }
    }
}