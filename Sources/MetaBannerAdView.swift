import SwiftUI

/// Премиальный адаптивный баннер Meta Audience Network (Apple HIG / Glassmorphism)
@MainActor
public struct MetaBannerAdView: View {
    @ObservedObject private var storeManager = StoreManager.shared
    
    /// Колбэк при тапе на «Убрать рекламу» (открывает Paywall PRO)
    public var onTapUpgrade: () -> Void
    
    @State private var creativeIndex: Int = Int.random(in: 0...2)
    @State private var timer: Timer? = nil
    
    public init(onTapUpgrade: @escaping () -> Void = {}) {
        self.onTapUpgrade = onTapUpgrade
    }
    
    public var body: some View {
        if !storeManager.isProUser {
            HStack(spacing: 12) {
                // Иконка креатива
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconBackgroundColor)
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                // Текстовая информация рекламодателя
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "infinity")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color(hex: "0081FB"))
                        
                        Text("Реклама от Meta".localized)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color(hex: "0081FB"))
                            .textCase(.uppercase)
                    }
                    
                    Text(creativeTitle)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(creativeSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                // Кнопка «Убрать рекламу (PRO)»
                Button(action: {
                    HapticHelper.selection()
                    onTapUpgrade()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text("PRO".localized)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.yellow.opacity(0.35), lineWidth: 0.8)
                    )
                }
                .buttonStyle(PremiumButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "111827").opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .onAppear {
                startRotationTimer()
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }
    
    // MARK: - Creatives Data
    
    private var creativeTitle: String {
        switch creativeIndex {
        case 0: return "DJI & Sony Creators"
        case 1: return "Capture One Pro"
        default: return "Freepik Contributor Hub"
        }
    }
    
    private var creativeSubtitle: String {
        switch creativeIndex {
        case 0: return "Скидки на оптику и стедикамы для 4K/8K съемки.".localized
        case 1: return "Профессиональная цветокоррекция для стоков.".localized
        default: return "Бонусы и заказы для авторов контента.".localized
        }
    }
    
    private var iconName: String {
        switch creativeIndex {
        case 0: return "camera.badge.ellipsis"
        case 1: return "slider.horizontal.3"
        default: return "sparkles"
        }
    }
    
    private var iconBackgroundColor: LinearGradient {
        switch creativeIndex {
        case 0:
            return LinearGradient(colors: [Color(hex: "3B82F6"), Color(hex: "1D4ED8")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 1:
            return LinearGradient(colors: [Color(hex: "8B5CF6"), Color(hex: "6D28D9")], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [Color(hex: "EC4899"), Color(hex: "BE185D")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private func startRotationTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                creativeIndex = (creativeIndex + 1) % 3
            }
        }
    }
}
