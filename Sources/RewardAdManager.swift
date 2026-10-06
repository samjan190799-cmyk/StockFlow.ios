import Foundation
import SwiftUI
import Combine

/// Менеджер раздельных дневных лимитов (15 ИИ-анализов + 15 отправок в день + бонусные слоты)
@MainActor
public final class RewardAdManager: ObservableObject {
    public static let shared = RewardAdManager()

    // Базовый дневной лимит (15 ИИ-анализов и 15 отправок в день)
    public static let baseDailyLimit: Int = 15

    // Ключи UserDefaults
    private let bonusCreditsKey = "bonus_upload_credits_v1"
    private let dailyUploadsUsedKey = "daily_free_uploads_used_v3"
    private let dailyAIUsedKey = "daily_free_ai_used_v3"
    private let dailyDayKey = "daily_free_limits_day_v3"
    private let rewardedAdsDayKey = "rewarded_ads_day_v1"
    private let rewardedAdsCountKey = "rewarded_ads_count_v1"
    
    @Published public private(set) var bonusCredits: Int = 0
    @Published public private(set) var dailyUploadsUsed: Int = 0
    @Published public private(set) var dailyAIUsed: Int = 0
    @Published public var showDailyLimitAlert: Bool = false

    private init() {
        self.bonusCredits = UserDefaults.standard.integer(forKey: bonusCreditsKey)
        checkAndResetDailyCount()
    }
    
    // MARK: - Сброс дневных счетчиков в полночь (чистый календарный расчет)
    
    private var currentDayOrdinal: Int {
        Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    }
    
    public func checkAndResetDailyCount() {
        let todayDay = currentDayOrdinal
        let savedDay = UserDefaults.standard.integer(forKey: dailyDayKey)
        
        if savedDay != todayDay {
            self.dailyUploadsUsed = 0
            self.dailyAIUsed = 0
            UserDefaults.standard.set(0, forKey: dailyUploadsUsedKey)
            UserDefaults.standard.set(0, forKey: dailyAIUsedKey)
            UserDefaults.standard.set(todayDay, forKey: dailyDayKey)
        } else {
            self.dailyUploadsUsed = UserDefaults.standard.integer(forKey: dailyUploadsUsedKey)
            self.dailyAIUsed = UserDefaults.standard.integer(forKey: dailyAIUsedKey)
        }
    }
    
    // MARK: - Бонусы за просмотр рекламы

    /// Сколько роликов за бонус ещё можно посмотреть сегодня
    public var rewardedAdsLeftToday: Int {
        let today = currentDayOrdinal
        if UserDefaults.standard.integer(forKey: rewardedAdsDayKey) != today {
            UserDefaults.standard.set(today, forKey: rewardedAdsDayKey)
            UserDefaults.standard.set(0, forKey: rewardedAdsCountKey)
        }
        let watched = UserDefaults.standard.integer(forKey: rewardedAdsCountKey)
        return max(0, AdConfig.maxRewardedPerDay - watched)
    }

    /// Начисляет бонусные действия за досмотренный рекламный ролик
    public func grantBonus(_ credits: Int) {
        guard credits > 0 else { return }
        bonusCredits += credits
        UserDefaults.standard.set(bonusCredits, forKey: bonusCreditsKey)
        _ = rewardedAdsLeftToday
        let watched = UserDefaults.standard.integer(forKey: rewardedAdsCountKey)
        UserDefaults.standard.set(watched + 1, forKey: rewardedAdsCountKey)
    }

    // MARK: - Остаток доступных действий сегодня
    
    /// Остаток доступных отправок на стоки (15 базовых + бонусы)
    public var remainingUploadsToday: Int {
        if StoreManager.shared.isProUser {
            return Int.max
        }
        let baseRemaining = max(0, RewardAdManager.baseDailyLimit - dailyUploadsUsed)
        return baseRemaining + bonusCredits
    }
    
    /// Остаток доступных ИИ-анализов (15 базовых + бонусы)
    public var remainingAIToday: Int {
        if StoreManager.shared.isProUser {
            return Int.max
        }
        let baseRemaining = max(0, RewardAdManager.baseDailyLimit - dailyAIUsed)
        return baseRemaining + bonusCredits
    }
    
    // MARK: - Проверка возможности выполнить действие
    
    public func canPerformAction(isAIAnalysis: Bool = false) -> Bool {
        if StoreManager.shared.isProUser {
            return true
        }
        checkAndResetDailyCount()
        return isAIAnalysis ? (remainingAIToday > 0) : (remainingUploadsToday > 0)
    }
    
    // MARK: - Списание слота (Раздельный учет: ИИ-анализ или отправка)
    
    @discardableResult
    public func consumeActionSlot(isAIAnalysis: Bool = false) -> Bool {
        if StoreManager.shared.isProUser {
            return true
        }
        
        checkAndResetDailyCount()
        
        // 1. Сначала списываем бонусные слоты за рекламу, если есть
        if bonusCredits > 0 {
            bonusCredits -= 1
            UserDefaults.standard.set(bonusCredits, forKey: bonusCreditsKey)
            return true
        }
        
        // 2. Иначе используем соответствующий базовый дневной счетчик
        if isAIAnalysis {
            if dailyAIUsed < RewardAdManager.baseDailyLimit {
                dailyAIUsed += 1
                UserDefaults.standard.set(dailyAIUsed, forKey: dailyAIUsedKey)
                return true
            }
        } else {
            if dailyUploadsUsed < RewardAdManager.baseDailyLimit {
                dailyUploadsUsed += 1
                UserDefaults.standard.set(dailyUploadsUsed, forKey: dailyUploadsUsedKey)
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Возврат слота в случае сбоя сети или ошибки
    
    public func refundActionSlot(isAIAnalysis: Bool = false) {
        if StoreManager.shared.isProUser {
            return
        }
        
        if isAIAnalysis {
            if dailyAIUsed > 0 {
                dailyAIUsed -= 1
                UserDefaults.standard.set(dailyAIUsed, forKey: dailyAIUsedKey)
            } else {
                bonusCredits += 1
                UserDefaults.standard.set(bonusCredits, forKey: bonusCreditsKey)
            }
        } else {
            if dailyUploadsUsed > 0 {
                dailyUploadsUsed -= 1
                UserDefaults.standard.set(dailyUploadsUsed, forKey: dailyUploadsUsedKey)
            } else {
                bonusCredits += 1
                UserDefaults.standard.set(bonusCredits, forKey: bonusCreditsKey)
            }
        }
    }
    
    public func getMaxQueueLimit(baseLimit: Int = 20) -> Int {
        if StoreManager.shared.isProUser {
            return Int.max
        }
        return baseLimit + bonusCredits
    }
}
