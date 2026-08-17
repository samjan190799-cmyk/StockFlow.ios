import Foundation
import StoreKit
import SwiftUI

/// Менеджер покупок и подписок StoreKit 2 (iOS 16+ / Swift 6)
@MainActor
public final class StoreManager: ObservableObject {
    public static let shared = StoreManager()
    
    // Идентификаторы продуктов App Store
    public enum ProductID {
        public static let monthly = "com.samvel.smartstock.monthly"
        public static let yearly = "com.samvel.smartstock.yearly"
        public static let lifetime = "com.samvel.smartstock.lifetime"
        
        public static let all: [String] = [yearly, monthly, lifetime]
    }
    
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchasedProductIDs: Set<String> = []
    @Published public private(set) var isProUser: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    private init() {
        // Начинаем слушать обновления транзакций Apple в реальном времени
        updateListenerTask = listenForTransactions()
        
        Task {
            await fetchProducts()
            await updateCustomerProductStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Загрузка продуктов из App Store
    
    public func fetchProducts() async {
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            let storeProducts = try await Product.products(for: ProductID.all)
            // Сортируем: Годовой (рекомендуемый), Месячный, Пожизненный
            self.products = storeProducts.sorted { p1, p2 in
                if p1.id == ProductID.yearly { return true }
                if p2.id == ProductID.yearly { return false }
                if p1.id == ProductID.monthly { return true }
                return false
            }
            self.isLoading = false
        } catch {
            print("StoreKit: Ошибка загрузки продуктов: \(error.localizedDescription)")
            self.errorMessage = "Не удалось загрузить тарифы: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
    
    // MARK: - Совершение покупки
    
    public func purchase(_ product: Product) async -> Bool {
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateCustomerProductStatus()
                self.isLoading = false
                HapticHelper.notification(.success)
                return true
                
            case .userCancelled:
                self.isLoading = false
                return false
                
            case .pending:
                self.isLoading = false
                self.errorMessage = "Покупка ожидает подтверждения (Ask to Buy)."
                return false
                
            @unknown default:
                self.isLoading = false
                return false
            }
        } catch {
            print("StoreKit: Ошибка покупки: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.isLoading = false
            HapticHelper.notification(.error)
            return false
        }
    }
    
    // MARK: - Восстановление покупок (Restore Purchases)
    
    public func restorePurchases() async -> Bool {
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            // Принудительная синхронизация с серверами App Store
            try await AppStore.sync()
            await updateCustomerProductStatus()
            self.isLoading = false
            HapticHelper.notification(.success)
            return isProUser
        } catch {
            print("StoreKit: Ошибка восстановления: \(error.localizedDescription)")
            self.errorMessage = "Ошибка восстановления: \(error.localizedDescription)"
            self.isLoading = false
            HapticHelper.notification(.error)
            return false
        }
    }
    
    // MARK: - Обновление активных прав пользователя
    
    public func updateCustomerProductStatus() async {
        var activePurchases = Set<String>()
        
        // Проверяем все активные права доступа пользователя
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                // Проверяем, не была ли транзакция отозвана (возврат средств)
                if transaction.revocationDate == nil {
                    activePurchases.insert(transaction.productID)
                }
            } catch {
                print("StoreKit: Ошибка проверки прав: \(error.localizedDescription)")
            }
        }
        
        self.purchasedProductIDs = activePurchases
        self.isProUser = !activePurchases.isEmpty
        
        #if DEBUG
        // Для удобства локальной отладки в симуляторе
        if UserDefaults.standard.bool(forKey: "debug_force_pro_user") {
            self.isProUser = true
        }
        #endif
    }
    
    // MARK: - Слушатель транзакций
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached(priority: .background) {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await transaction.finish()
                    await self.updateCustomerProductStatus()
                } catch {
                    print("StoreKit: Ошибка в потоке транзакций: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Криптографическая проверка подписи Apple
    
    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(domain: "StoreKit", code: 403, userInfo: [NSLocalizedDescriptionKey: "Транзакция не прошла проверку подписи Apple."])
        case .verified(let safe):
            return safe
        }
    }
}
