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
    private let privacyPolicyURL = URL(string: "https://github.com/samjan190799-cmyk/StockFlow.ios/blob/main/PRIVACY_POLICY.md") ?? URL(fileURLWithPath: "/")
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") ?? URL(fileURLWithPath: "/")
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Динамический анимированный фон
            LiquidBackgroundView()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    // Верхняя панель: закрыть и восстановить (44pt Hit targets)
                    headerControls
                    
                    // Заголовок и PRO-бейдж
                    proHeader
                    
                    // Список преимуществ PRO
                    featuresList
                    
                    // Карточки выбора тарифов
                    pricingSection
                    
                    // Большая кнопка действия
                    actionButton
                    
                    // Ссылки на Privacy, Terms, и условия автопродления
                    footerLegalSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
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
                                .tint(.purple)
                                .scaleEffect(1.3)
                            Text("Связь с App Store...".localized)
                                .font(.system(size: 14, weight: .semibold))
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
    
    private var headerControls: some View {
        HStack {
            Button(action: {
                HapticHelper.trigger(.light)
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.12)))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PremiumButtonStyle())
        }
    }
    
    private var proHeader: some View {
        VStack(spacing: 10) {
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
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2.2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FDE047"), Color(hex: "C084FC"), Color(hex: "60A5FA")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.purple.opacity(0.22))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(LinearGradient(colors: [.yellow.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            
            Text("Максимум продаж на стоках".localized)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            
            Text("Автоматизируйте рутину и отправляйте сотни фото и видео на 10+ стоков в один клик.".localized)
                .font(.system(size: 13, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 12)
        }
        .padding(.top, 4)
    }
    
    private var featuresList: some View {
        VStack(spacing: 12) {
            featureRow(
                icon: "sparkles.rectangle.stack.fill",
                color: Color(hex: "A855F7"),
                title: "Безлимитный ИИ-анализ кадра".localized,
                subtitle: "Генерация коммерческих названий, описаний и до 50 тегов через Gemini 2.5, GPT-4o, Claude".localized
            )
            
            featureRow(
                icon: "paperplane.fill",
                color: Color(hex: "3B82F6"),
                title: "Выгрузка на все 10+ стоков сразу".localized,
                subtitle: "Shutterstock, Adobe Stock, Getty Images, Freepik, Depositphotos, Dreamstime и др.".localized
            )
            
            featureRow(
                icon: "infinity",
                color: Color(hex: "10B981"),
                title: "Безлимитная очередь файлов".localized,
                subtitle: "Пакетная обработка и загрузка сотен фото и 4K/8K видео без пауз и ограничений".localized
            )
            
            featureRow(
                icon: "icloud.and.arrow.down.fill",
                color: Color(hex: "F97316"),
                title: "Google Фото и Google Диск".localized,
                subtitle: "Неограниченный импорт исходных медиафайлов прямо из облака".localized
            )
            
            featureRow(
                icon: "tablecells.fill",
                color: Color(hex: "06B6D4"),
                title: "Экспорт CSV и метаданных".localized,
                subtitle: "Мгновенное создание таблиц метаданных для любых агентств".localized
            )
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
    
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    private var pricingSection: some View {
        VStack(spacing: 12) {
            // Годовой тариф (Рекомендуемый)
            pricingCard(
                productID: StoreManager.ProductID.yearly,
                badge: "ВЫГОДА 50% • 3 ДНЯ БЕСПЛАТНО".localized,
                title: "Годовая подписка".localized,
                price: getPriceString(for: StoreManager.ProductID.yearly, fallback: "2 990 ₽ / год ($29.99)"),
                subtitle: "Всего ~249 ₽ в месяц. Списание после 3-дневного триала.".localized,
                isPopular: true
            )
            
            // Месячный тариф
            pricingCard(
                productID: StoreManager.ProductID.monthly,
                badge: nil,
                title: "Месячная подписка".localized,
                price: getPriceString(for: StoreManager.ProductID.monthly, fallback: "399 ₽ / месяц ($3.99)"),
                subtitle: "Ежемесячный доступ со всеми обновлениями.".localized,
                isPopular: false
            )
            
            // Пожизненный тариф (Lifetime)
            pricingCard(
                productID: StoreManager.ProductID.lifetime,
                badge: "НАВСЕГДА".localized,
                title: "Пожизненный PRO".localized,
                price: getPriceString(for: StoreManager.ProductID.lifetime, fallback: "5 990 ₽ ($59.99)"),
                subtitle: "Один платёж раз и навсегда. Без подписок.".localized,
                isPopular: false
            )
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: selectedProductID)
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
            HapticHelper.trigger(.selection)
            selectedProductID = productID
        }) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                            
                            if let badge = badge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(isPopular ? LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(price)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        ZStack {
                            Circle()
                                .stroke(isSelected ? Color(hex: "A855F7") : Color.white.opacity(0.3), lineWidth: 2)
                                .frame(width: 20, height: 20)
                            
                            if isSelected {
                                Circle()
                                    .fill(Color(hex: "A855F7"))
                                    .frame(width: 12, height: 12)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelected ? Color.purple.opacity(0.24) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? Color(hex: "A855F7") : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )
            }
        }
        .buttonStyle(PremiumButtonStyle())
    }
    
    private var actionButton: some View {
        Button(action: {
            HapticHelper.trigger(.medium)
            makePurchase()
        }) {
            HStack(spacing: 8) {
                if storeManager.isLoading {
                    ProgressView()
                        .tint(.white)
                    Text("Загрузка...".localized)
                        .font(.system(size: 16, weight: .bold))
                } else {
                    if #available(iOS 17.0, *) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .symbolEffect(.bounce, value: selectedProductID)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                    }
                    
                    Text(selectedProductID == StoreManager.ProductID.yearly ? "Попробовать 3 дня бесплатно".localized : "Продолжить с SmartStock PRO".localized)
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [Color(hex: "8B5CF6"), Color(hex: "3B82F6")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.purple.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(PremiumButtonStyle())
        .disabled(storeManager.isLoading)
        .padding(.top, 4)
    }
    
    private var footerLegalSection: some View {
        VStack(spacing: 8) {
            Text("Подписка продлевается автоматически, пока не будет отменена в настройках Apple ID не менее чем за 24 часа до окончания текущего периода.".localized)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.55))
            
            HStack(spacing: 16) {
                Link("Условия использования (EULA)".localized, destination: termsOfUseURL)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                
                Text("•")
                    .foregroundStyle(.white.opacity(0.4))
                
                Link("Политика конфиденциальности".localized, destination: privacyPolicyURL)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - Actions
    
    private func getPriceString(for productID: String, fallback: String) -> String {
        if let product = storeManager.products.first(where: { $0.id == productID }) {
            return product.displayPrice
        }
        return fallback
    }
    
    private func makePurchase() {
        guard let product = storeManager.products.first(where: { $0.id == selectedProductID }) else {
            // Если продукты ещё загружаются, пробуем загрузить снова
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

