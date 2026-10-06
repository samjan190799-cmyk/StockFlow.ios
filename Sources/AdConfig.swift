import Foundation

/// Настройки рекламы (Яндекс). Идентификаторы блоков лежат в Info.plist (генерируется из project.yml):
/// по умолчанию там тестовые блоки Яндекса, свои из кабинета partner.yandex.ru подставляются без правки кода.
enum AdConfig {
    /// Общий выключатель рекламы (ключ AdsEnabled в Info.plist)
    static var adsEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "AdsEnabled") as? Bool) ?? true
    }

    static var bannerUnitID: String {
        value(for: "YandexBannerUnitID", fallback: "demo-banner-yandex")
    }

    static var rewardedUnitID: String {
        value(for: "YandexRewardedUnitID", fallback: "demo-rewarded-yandex")
    }

    /// Сколько бонусных действий (ИИ-анализ или отправка) даёт один досмотренный ролик
    static let rewardCredits = 5

    /// Сколько роликов за бонус можно посмотреть за день
    static let maxRewardedPerDay = 5

    private static func value(for key: String, fallback: String) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? fallback : raw
    }
}
