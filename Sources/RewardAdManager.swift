import Foundation
import SwiftUI
import Combine

/// Менеджер вознаграждений за рекламу и раздельных дневных лимитов (15 ИИ-анализов + 15 отправок в день + бонусы)
@MainActor
public final class RewardAdManager: ObservableObject {
    public static let shared = RewardAdManager()
    
    // Идентификаторы Meta Audience Network (Facebook Audience Network)
    public static let metaPlacementID = "VID_HD_16_9_30S_APP_INSTALL#YOUR_PLACEMENT_ID"
    public static let metaBannerPlacementID = "IMG_16_9_APP_INSTALL#YOUR_BANNER_PLACEMENT_ID"
    
    // Супер-награда за 30-секундное видео от Meta (+15 слотов)
    public static let superRewardAmount: Int = 15
    
    // Базовый дневной лимит (15 ИИ-анализов и 15 отправок в день)
    public static let baseDailyLimit: Int = 15
    
    // Ключи UserDefaults
    private let bonusCreditsKey = "bonus_upload_credits_v1"
    private let totalAdsWatchedKey = "total_reward_ads_watched"
    private let dailyUploadsUsedKey = "daily_free_uploads_used_v3"
    private let dailyAIUsedKey = "daily_free_ai_used_v3"
    private let dailyDayKey = "daily_free_limits_day_v3"
    
    @Published public private(set) var bonusCredits: Int = 0
    @Published public private(set) var totalAdsWatched: Int = 0
    @Published public private(set) var dailyUploadsUsed: Int = 0
    @Published public private(set) var dailyAIUsed: Int = 0
    @Published public var isShowingRewardModal: Bool = false
    @Published public var showDailyLimitAlert: Bool = false
    
    private init() {
        self.bonusCredits = UserDefaults.standard.integer(forKey: bonusCreditsKey)
        self.totalAdsWatched = UserDefaults.standard.integer(forKey: totalAdsWatchedKey)
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
