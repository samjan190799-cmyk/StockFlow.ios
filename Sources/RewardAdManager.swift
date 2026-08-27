import Foundation
import SwiftUI
import Combine

/// Менеджер вознаграждений за рекламу и дневных лимитов (15 бесплатных отправок/анализов в день + бонусы)
@MainActor
public final class RewardAdManager: ObservableObject {
    public static let shared = RewardAdManager()
    
    // Идентификаторы Google AdMob пользователя
    public static let adMobAppID = "ca-app-pub-1230774710816122~9425524877"
    public static let rewardedAdUnitID = "ca-app-pub-1230774710816122/7729299826"
    
    // Базовый дневной лимит бесплатных отправок/анализов
    public static let baseDailyLimit: Int = 15
    
    // Ключи UserDefaults
    private let bonusCreditsKey = "bonus_upload_credits_v1"
    private let totalAdsWatchedKey = "total_reward_ads_watched"
    private let dailyUploadsUsedKey = "daily_free_uploads_used_v1"
    private let dailyUploadsDateKey = "daily_free_uploads_date_v1"
    
    @Published public private(set) var bonusCredits: Int = 0
    @Published public private(set) var totalAdsWatched: Int = 0
    @Published public private(set) var dailyUploadsUsed: Int = 0
    @Published public var isShowingRewardModal: Bool = false
    @Published public var showDailyLimitAlert: Bool = false
    
    private init() {
        self.bonusCredits = UserDefaults.standard.integer(forKey: bonusCreditsKey)
        self.totalAdsWatched = UserDefaults.standard.integer(forKey: totalAdsWatchedKey)
        checkAndResetDailyCount()
    }
    
    // MARK: - Сброс дневного счетчика в полночь (чистый календарный расчет без ICU-блокировок)
    
    private var currentDayOrdinal: Int {
        Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    }
    
    public func checkAndResetDailyCount() {
        let todayDay = currentDayOrdinal
        let savedDay = UserDefaults.standard.integer(forKey: "daily_free_uploads_day_v2")
        
        if savedDay != todayDay {
            self.dailyUploadsUsed = 0
            UserDefaults.standard.set(0, forKey: dailyUploadsUsedKey)
            UserDefaults.standard.set(todayDay, forKey: "daily_free_uploads_day_v2")
        } else {
            self.dailyUploadsUsed = UserDefaults.standard.integer(forKey: dailyUploadsUsedKey)
        }
    }
    
    // MARK: - Проверка наличия личного API-ключа
    
    public var hasCustomAPIKey: Bool {
        let gemini = UserDefaults.standard.string(forKey: "api_key_gemini")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let openai = UserDefaults.standard.string(forKey: "api_key_openai")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let claude = UserDefaults.standard.string(forKey: "api_key_claude")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !gemini.isEmpty || !openai.isEmpty || !claude.isEmpty
    }
    
    // MARK: - Остаток доступных отправок сегодня (чистый геттер без вызова мутаций в теле SwiftUI)
    
    public var remainingUploadsToday: Int {
        if StoreManager.shared.isProUser {
            return Int.max
        }
        let baseRemaining = max(0, RewardAdManager.baseDailyLimit - dailyUploadsUsed)
        return baseRemaining + bonusCredits
    }
    
    // MARK: - Проверка возможности выполнить действие (Строго 15 в день для всех без PRO)
    
    public func canPerformAction(isAIAnalysis: Bool = false) -> Bool {
        // 1. Только PRO пользователи имеют безлимит
        if StoreManager.shared.isProUser {
            return true
        }
        // 2. Для всех остальных — лимит 15 действий в день (+ бонусы за просмотр рекламы)
        checkAndResetDailyCount()
        return remainingUploadsToday > 0
    }
    
    // MARK: - Списание слота (1 отправка или ИИ-анализ)
    
    @discardableResult
    public func consumeActionSlot(isAIAnalysis: Bool = false) -> Bool {
        if StoreManager.shared.isProUser {
            return true
        }
        
        checkAndResetDailyCount()
        
        // Сначала списываем бонусные слоты за рекламу, если есть
        if bonusCredits > 0 {
            bonusCredits -= 1
            UserDefaults.standard.set(bonusCredits, forKey: bonusCreditsKey)
            return true
        }
        
        // Иначе используем базовый дневной слот
        if dailyUploadsUsed < RewardAdManager.baseDailyLimit {
            dailyUploadsUsed += 1
            UserDefaults.standard.set(dailyUploadsUsed, forKey: dailyUploadsUsedKey)
            return true
        }
        
        return false
    }
    
    // MARK: - Начисление бонусов за просмотр рекламы (+5 слотов)
    
    public func rewardUser(with credits: Int = 5) {
        self.bonusCredits += credits
        self.totalAdsWatched += 1
        UserDefaults.standard.set(self.bonusCredits, forKey: bonusCreditsKey)
        UserDefaults.standard.set(self.totalAdsWatched, forKey: totalAdsWatchedKey)
        
        HapticHelper.notification(.success)
    }
    
    public func getMaxQueueLimit(baseLimit: Int = 20) -> Int {
        if StoreManager.shared.isProUser {
            return Int.max
        }
        return baseLimit + bonusCredits
    }
}
