import SwiftUI
import UIKit
import YandexMobileAds

/// Реклама Яндекса: баннер в очереди и ролик за бонусные действия. Только для пользователей без PRO.
/// SDK запускается лениво, при первом показе: подписчикам он не нужен вообще.
@MainActor
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    @Published private(set) var isLoadingRewarded = false

    private var isStarted = false
    private let rewardedLoader = RewardedAdLoader()
    private var rewardedAd: RewardedAd?
    private var didEarnReward = false
    private var rewardHandler: (() -> Void)?
    private var failureHandler: ((String) -> Void)?

    private override init() {
        super.init()
    }

    /// Реклама разрешена: включена в настройках и у пользователя нет PRO
    var adsAllowed: Bool {
        AdConfig.adsEnabled && !StoreManager.shared.isProUser
    }

    /// Можно ли предложить ролик за бонус (лимит на день не исчерпан)
    var canOfferRewarded: Bool {
        adsAllowed && RewardAdManager.shared.rewardedAdsLeftToday > 0
    }

    func startIfNeeded() async {
        guard !isStarted else { return }
        isStarted = true
        await YandexAds.initializeSDK()
    }

    // MARK: - Ролик за бонус

    func showRewardedAd(onReward: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
        guard adsAllowed else { return }
        guard !isLoadingRewarded else { return }
        guard RewardAdManager.shared.rewardedAdsLeftToday > 0 else {
            onFailure("Лимит рекламных бонусов на сегодня исчерпан.".localized)
            return
        }

        isLoadingRewarded = true
        didEarnReward = false
        rewardHandler = onReward
        failureHandler = onFailure

        Task {
            await startIfNeeded()
            rewardedLoader.loadAd(with: AdRequest(adUnitID: AdConfig.rewardedUnitID)) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoadingRewarded = false
                    switch result {
                    case .success(let ad):
                        ad.delegate = self
                        self.rewardedAd = ad
                        if let presenter = Self.topViewController() {
                            ad.show(from: presenter)
                        } else {
                            self.finishWithFailure("Реклама не загрузилась. Попробуйте позже.".localized)
                        }
                    case .failure:
                        self.finishWithFailure("Реклама не загрузилась. Попробуйте позже.".localized)
                    }
                }
            }
        }
    }

    private func finishWithFailure(_ message: String) {
        let handler = failureHandler
        clearHandlers()
        handler?(message)
    }

    private func clearHandlers() {
        rewardHandler = nil
        failureHandler = nil
        didEarnReward = false
    }

    /// Верхний контроллер, поверх которого показывается полноэкранная реклама
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - RewardedAdDelegate

extension AdManager: RewardedAdDelegate {
    func rewardedAd(_ rewardedAd: RewardedAd, didReward reward: Reward) {
        didEarnReward = true
    }

    func rewardedAd(_ rewardedAd: RewardedAd, didFailToShow error: Error) {
        self.rewardedAd = nil
        finishWithFailure("Реклама не загрузилась. Попробуйте позже.".localized)
    }

    func rewardedAdDidShow(_ rewardedAd: RewardedAd) {}

    func rewardedAdDidDismiss(_ rewardedAd: RewardedAd) {
        let earned = didEarnReward
        let onReward = rewardHandler
        let onFailure = failureHandler
        self.rewardedAd = nil
        clearHandlers()
        if earned {
            onReward?()
        } else {
            onFailure?("Видео не досмотрено — бонус не начислен.".localized)
        }
    }

    func rewardedAdDidClick(_ rewardedAd: RewardedAd) {}

    func rewardedAd(_ rewardedAd: RewardedAd, didTrackImpression impressionData: ImpressionData?) {}
}

// MARK: - Баннер

/// Баннер внизу очереди. Занимает место только когда реклама загрузилась; у подписчиков не создаётся вообще.
struct AdBannerView: View {
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var bannerState: BannerState? = nil
    @State private var isLoaded = false

    var body: some View {
        if AdConfig.adsEnabled && !storeManager.isProUser {
            ZStack {
                if let bannerState {
                    Banner(state: bannerState)
                        .onAdLoad { _ in isLoaded = true }
                        .onAdFailure { _ in isLoaded = false }
                        .opacity(isLoaded ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: isLoaded ? nil : 1)
            .task {
                await AdManager.shared.startIfNeeded()
                if bannerState == nil {
                    bannerState = BannerState(
                        size: .sticky(),
                        request: AdRequest(adUnitID: AdConfig.bannerUnitID)
                    )
                }
            }
        }
    }
}
