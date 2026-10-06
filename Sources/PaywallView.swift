import SwiftUI
import StoreKit

/// Премиальный экран покупки подписки SmartStock PRO (Apple HIG / StoreKit 2 / Glassmorphism)
@MainActor
public struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storeManager = StoreManager.shared
    
    @State private var selectedProductID: String = StoreManager.ProductID.yearly
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isRestoring = false
    
    // Privacy & Terms URLs (Apple Guidelines requirement)
    private let privacyPolicyURL = URL(string: "https://samjan190799-cmyk.github.io/StockFlow.ios/privacy.html") ?? URL(fileURLWithPath: "/")
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") ?? URL(fileURLWithPath: "/")
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Динамический анимированный фон
            LiquidBackgroundView()
                .ignoresSafeArea()
            
            // Основной прокручиваемый контент
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Отступ сверху под закрепленную панель кнопок
                    Color.clear.frame(height: 48)
                    
                    // Заголовок и PRO-бейдж
                    proHeader
                    
                    // Список преимуществ PRO (компактный и выразительный)
                    featuresList
                    
                    // Карточки выбора тарифов
                    pricingSection
                    
                    // Большая кнопка действия с прозрачными условиями списания
                    actionButton
                    
                    // Ссылки на Privacy, Terms, и полный юридический дисклеймер автопродления
                    footerLegalSection
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 64)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 24)
            }
            
            // Фиксированная верхняя панель (Закрыть и Восстановить покупки)
            stickyHeaderControls
        }
        .preferredColorScheme(.dark)
        .alert("Подписка".localized, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {
                if storeManager.isProUser {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
        .overlay {
            if storeManager.isLoading || isRestoring {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(AppPalette.accentLight)
                                .scaleEffect(1.3)
                            Text("Связь с App Store...".localized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                    )
            }
        }
        .task {
            if storeManager.products.isEmpty {
                await storeManager.fetchProducts()
            }
        }
    }
    
    // MARK: - Subviews
    
    /// Фиксированная верхняя панель — кнопки Закрыть и Восстановить всегда на виду
    private var stickyHeaderControls: some View {
        HStack {
            Button(action: {
                HapticHelper.trigger(.light)
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .accessibilityLabel("Закрыть".localized)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PremiumButtonStyle())
            .accessibilityLabel("Закрыть".localized)
            
            Spacer()
            
            Button(action: {
                restorePurchases()
            }) {
                Text("Восстановить".localized)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PremiumButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.88), Color.black.opacity(0.4), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }
    
    private var proHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if #available(iOS 17.0, *) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                        .symbolEffect(.pulse)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                }
                Text("SMARTSTOCK PRO")
                    .font(.caption.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FDE047"), Color(hex: "C084FC"), Color(hex: "60A5FA")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(AppPalette.accent.opacity(0.22))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(LinearGradient(colors: [.yellow.opacity(0.6), AppPalette.accentLight.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            
            Text("Работайте без ограничений".localized)
                .font(Font.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            
            Text("Без дневных лимитов отправляйте фото и видео на все стоки и импортируйте из Google Фото.".localized)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 10)
        }
        .padding(.top, 2)
    }
    
    private var featuresList: some View {
        VStack(spacing: 9) {
            featureRow(
                icon: "sparkles",
                color: Color(hex: "A855F7"),
                title: "Без дневных лимитов".localized,
                subtitle: "ИИ-анализ и отправка без ограничений. В бесплатной версии — 15 в день каждого.".localized
            )

            featureRow(
                icon: "paperplane.fill",
                color: Color(hex: "3B82F6"),
                title: "Все доступные стоки сразу".localized,
                subtitle: "В бесплатной версии — 2 стока. Adobe Stock и Freepik работают через ПК-сервер.".localized
            )

            featureRow(
                icon: "icloud.and.arrow.down.fill",
                color: Color(hex: "F97316"),
                title: "Google Фото и Google Диск".localized,
                subtitle: "Импорт исходных файлов прямо из облака".localized
            )

            featureRow(
                icon: "eye.slash.fill",
                color: Color(hex: "64748B"),
                title: "Без рекламы".localized,
                subtitle: "Баннеры и рекламные ролики не показываются".localized
            )
        }
        .appCard(cornerRadius: 20, padding: 14)
    }
    
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    private var pricingSection: some View {
        VStack(spacing: 10) {
            // Годовой тариф (Рекомендуемый) с динамическим расчетом цены за месяц
            pricingCard(
                productID: StoreManager.ProductID.yearly,
                badge: yearlyBadge,
                title: "Годовая подписка".localized,
                price: getFormattedPriceWithPeriod(for: StoreManager.ProductID.yearly),
                subtitle: yearlySubtitle,
                isPopular: true
            )
            
            // Месячный тариф
            pricingCard(
                productID: StoreManager.ProductID.monthly,
                badge: nil,
                title: "Месячная подписка".localized,
                price: getFormattedPriceWithPeriod(for: StoreManager.ProductID.monthly),
                subtitle: "Ежемесячный доступ со всеми обновлениями.".localized,
                isPopular: false
            )
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: selectedProductID)
    }
    
    /// Динамический расчет цены за месяц для годового плана в валюте пользователя
    private var yearlySubtitle: String {
        if let yearlyProduct = storeManager.products.first(where: { $0.id == StoreManager.ProductID.yearly }) {
            let monthlyPriceDecimal = yearlyProduct.price / 12
            let formattedMonthly = monthlyPriceDecimal.formatted(yearlyProduct.priceFormatStyle)
            // Про пробный период пишем только если App Store подтвердил его для этого пользователя
            let pattern = hasYearlyTrial
                ? "Всего ~%@ в месяц. Списание после пробного периода."
                : "Всего ~%@ в месяц."
            let localizedPattern = pattern.localized
            if localizedPattern.contains("%@") {
                return String(format: localizedPattern, formattedMonthly)
            } else {
                return pattern.replacingOccurrences(of: "%@", with: formattedMonthly)
            }
        }
        return "Годовой доступ со всеми обновлениями.".localized
    }
    
    // MARK: - Пробный период и выгода по данным App Store
    
    /// Дни бесплатного пробного периода годового тарифа: только если он есть в App Store и доступен этому пользователю
    private var yearlyTrialDays: Int? {
        storeManager.freeTrialDays[StoreManager.ProductID.yearly]
    }
    
    private var hasYearlyTrial: Bool {
        yearlyTrialDays != nil
    }
    
    /// «3 дн. бесплатно» / «1 день бесплатно»
    private func trialLabel(days: Int) -> String {
        if days == 1 {
            return "1 " + "день бесплатно".localized
        }
        return "\(days) " + "дн. бесплатно".localized
    }
    
    /// Выгода годового тарифа против 12 месячных платежей по реальным ценам App Store, в процентах (округляется вниз)
    private var yearlySavingsPercent: Int? {
        guard let yearly = storeManager.products.first(where: { $0.id == StoreManager.ProductID.yearly }),
              let monthly = storeManager.products.first(where: { $0.id == StoreManager.ProductID.monthly }) else {
            return nil
        }
        let yearlyPrice = NSDecimalNumber(decimal: yearly.price).doubleValue
        let monthlyTotal = NSDecimalNumber(decimal: monthly.price).doubleValue * 12
        guard monthlyTotal > 0 else { return nil }
        let percent = Int(((1 - yearlyPrice / monthlyTotal) * 100).rounded(.down))
        return percent >= 5 ? percent : nil
    }
    
    private var yearlyBadge: String? {
        var parts: [String] = []
        if let percent = yearlySavingsPercent {
            parts.append("\("ВЫГОДА".localized) \(percent)%")
        }
        if let days = yearlyTrialDays {
            parts.append(trialLabel(days: days).uppercased())
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    
    private func pricingCard(
        productID: String,
        badge: String?,
        title: String,
        price: String,
        subtitle: String,
        isPopular: Bool
    ) -> some View {
        let isSelected = selectedProductID == productID
        
        return Button(action: {
            HapticHelper.selection()
            selectedProductID = productID
        }) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    // Бейдж на своей строке во всю ширину карточки: рядом с названием он сжимался и переносился на 4 строки
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(
                                    isPopular
                                        ? LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                                        : LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
                                )
                            )
                    }

                    HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.70))
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer(minLength: 8)
                    
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(price)
                            .font(Font.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .layoutPriority(1)

                        ZStack {
                            Circle()
                                .stroke(isSelected ? AppPalette.accentLight : Color.white.opacity(0.3), lineWidth: 2)
                                .frame(width: 20, height: 20)
                            
                            if isSelected {
                                Circle()
                                    .fill(AppPalette.accentLight)
                                    .frame(width: 12, height: 12)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? AppPalette.accent.opacity(0.24) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? AppPalette.accentLight : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )
            }
        }
        .buttonStyle(PremiumButtonStyle())
    }
    
    private var actionButton: some View {
        VStack(spacing: 8) {
            Button(action: {
                HapticHelper.trigger(.medium)
                makePurchase()
            }) {
                HStack(spacing: 8) {
                    if storeManager.isLoading {
                        ProgressView()
                            .tint(.white)
                        Text("Загрузка...".localized)
                            .font(.body.weight(.bold))
                    } else {
                        if #available(iOS 17.0, *) {
                            Image(systemName: "sparkles")
                                .font(.body.weight(.bold))
                                .symbolEffect(.bounce, value: selectedProductID)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.body.weight(.bold))
                        }
                        
                        Text(actionButtonTitle)
                            .font(.body.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AppPalette.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: AppPalette.accent.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(PremiumButtonStyle())
            .disabled(storeManager.isLoading)
            
            // Прозрачные условия списания по требованиям Apple Guideline 3.1.2
            Text(trialTermsClarification)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
        }
        .padding(.top, 4)
    }
    
    private var actionButtonTitle: String {
        switch selectedProductID {
        case StoreManager.ProductID.yearly:
            if hasYearlyTrial {
                return "Попробовать бесплатно".localized
            }
            let price = getPriceString(for: StoreManager.ProductID.yearly, fallback: "$19.99")
            return "\("Подписаться за".localized) \(price) / \("год".localized)"
        case StoreManager.ProductID.monthly:
            let price = getPriceString(for: StoreManager.ProductID.monthly, fallback: "$3.99")
            return "\("Подписаться за".localized) \(price) / \("мес.".localized)"
        default:
            return "Продолжить с SmartStock PRO".localized
        }
    }
    
    private var trialTermsClarification: String {
        let yearlyPrice = getPriceString(for: StoreManager.ProductID.yearly, fallback: "$19.99")
        let monthlyPrice = getPriceString(for: StoreManager.ProductID.monthly, fallback: "$3.99")
        
        switch selectedProductID {
        case StoreManager.ProductID.yearly:
            if let days = yearlyTrialDays {
                return "\(trialLabel(days: days)), \("затем".localized) \(yearlyPrice) \("в год. Отмена в любой момент в настройках Apple ID.".localized)"
            }
            return "\("Списание".localized) \(yearlyPrice) \("каждый год. Отмена в любое время в настройках Apple ID.".localized)"
        case StoreManager.ProductID.monthly:
            return "\("Списание".localized) \(monthlyPrice) \("каждый месяц. Отмена в любое время в настройках Apple ID.".localized)"
        default:
            return ""
        }
    }
    
    /// Полный официальный блок условий подписки и автопродления (Apple Guideline 3.1.2)
    private var footerLegalSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Условия автопродления подписки:".localized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                
                Text("• Оплата будет списана с учетной записи Apple ID при подтверждении покупки.".localized)
                Text("• Подписка продлевается автоматически, если автопродление не отключено не менее чем за 24 часа до окончания текущего периода.".localized)
                Text("• Плата за продление будет взиматься в течение 24 часов до окончания текущего расчетного периода с указанием стоимости.".localized)
                Text("• Управлять подпиской и отключить автопродление можно в настройках учетной записи Apple ID в любое время после покупки.".localized)
                if !storeManager.freeTrialDays.isEmpty {
                    Text("• Любая неиспользованная часть бесплатного пробного периода аннулируется при приобретении подписки.".localized)
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.82))
            .lineSpacing(2.5)
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            // Крупные, высококонтрастные и доступные ссылки
            HStack(spacing: 18) {
                Link("Условия использования (EULA)".localized, destination: termsOfUseURL)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.accentLight)
                    .frame(minHeight: 44)
                
                Text("•")
                    .foregroundStyle(.white.opacity(0.3))
                
                Link("Политика конфиденциальности".localized, destination: privacyPolicyURL)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.accentLight)
                    .frame(minHeight: 44)
            }
            .padding(.top, 2)
            
            Button(action: {
                restorePurchases()
            }) {
                Text("Восстановить покупки".localized)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .underline()
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
    
    // MARK: - Actions
    
    private func getFormattedPriceWithPeriod(for productID: String) -> String {
        let rawPrice = getPriceString(for: productID, fallback: fallbackPrice(for: productID))
        switch productID {
        case StoreManager.ProductID.yearly:
            return "\(rawPrice) / \("год".localized)"
        case StoreManager.ProductID.monthly:
            return "\(rawPrice) / \("мес.".localized)"
        default:
            return rawPrice
        }
    }
    
    private func fallbackPrice(for productID: String) -> String {
        switch productID {
        case StoreManager.ProductID.yearly: return "$19.99"
        case StoreManager.ProductID.monthly: return "$3.99"
        default: return ""
        }
    }
    
    private func getPriceString(for productID: String, fallback: String) -> String {
        if let product = storeManager.products.first(where: { $0.id == productID }) {
            return product.displayPrice
        }
        return fallback
    }
    
    private func makePurchase() {
        guard let product = storeManager.products.first(where: { $0.id == selectedProductID }) else {
            Task {
                await storeManager.fetchProducts()
                if let retryProduct = storeManager.products.first(where: { $0.id == selectedProductID }) {
                    let success = await storeManager.purchase(retryProduct)
                    if success {
                        alertMessage = "Поздравляем! SmartStock PRO успешно активирован! 🎉".localized
                        showingAlert = true
                    }
                } else {
                    alertMessage = "Не удалось подключиться к App Store. Пожалуйста, проверьте интернет-соединение.".localized
                    showingAlert = true
                }
            }
            return
        }
        
        Task {
            let success = await storeManager.purchase(product)
            if success {
                alertMessage = "Поздравляем! SmartStock PRO успешно активирован! 🎉".localized
                showingAlert = true
            } else if let error = storeManager.errorMessage {
                alertMessage = error
                showingAlert = true
            }
        }
    }
    
    private func restorePurchases() {
        HapticHelper.trigger(.medium)
        isRestoring = true
        Task {
            let hasRestored = await storeManager.restorePurchases()
            isRestoring = false
            if hasRestored {
                alertMessage = "Ваши покупки успешно восстановлены! Доступ к SmartStock PRO открыт.".localized
            } else {
                alertMessage = "Активных подписок не найдено. Если вы совершали покупку, убедитесь, что вошли под нужным Apple ID.".localized
            }
            showingAlert = true
        }
    }
}
