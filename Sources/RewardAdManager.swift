import Foundation
import SwiftUI
import Combine

/// Менеджер вознаграждений за просмотр рекламы (Rewarded Ads / Bonus Credits)
@MainActor
public final class RewardAdManager: ObservableObject {
    public static let shared = RewardAdManager()
    
    // Идентификаторы Google AdMob пользователя
    public static let adMobAppID = "ca-app-pub-1230774710816122~9425524877"
    public static let rewardedAdUnitID = "ca-app-pub-1230774710816122/7729299826"
    
    // Ключи UserDefaults
    private let bonusCreditsKey = "bonus_upload_credits_v1"
    private let totalAdsWatchedKey = "total_reward_ads_watched"
    
    @Published public private(set) var bonusCredits: Int = 0
    @Published public private(set) var totalAdsWatched: Int = 0
    @Published public var isShowingRewardModal: Bool = false
    
    private init() {
        self.bonusCredits = UserDefaults.standard.integer(forKey: bonusCreditsKey)
        self.totalAdsWatched = UserDefaults.standard.integer(forKey: totalAdsWatchedKey)
    }
    
    // MARK: - Начисление и списание бонусов
    
    /// Начислить бонусные фото за просмотр видео
    public func rewardUser(with credits: Int = 5) {
        self.bonusCredits += credits
        self.totalAdsWatched += 1
        UserDefaults.standard.set(self.bonusCredits, forKey: bonusCreditsKey)
        UserDefaults.standard.set(self.totalAdsWatched, forKey: totalAdsWatchedKey)
        
        HapticHelper.notification(.success)
    }
    
    /// Списать один бонусный слот при загрузке
    public func consumeCredit() -> Bool {
        if bonusCredits > 0 {
            bonusCredits -= 1
            UserDefaults.standard.set(bonusCredits, forKey: bonusCreditsKey)
            return true
        }
        return false
    }
    
    /// Общий лимит файлов для пользователя (PRO = безлимит, Free = 20 + бонусы)
    public func getMaxQueueLimit(baseLimit: Int = 20) -> Int {
        if StoreManager.shared.isProUser {
            return Int.max
        }
        return baseLimit + bonusCredits
    }
}
