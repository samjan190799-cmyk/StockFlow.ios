import SwiftUI

/// Интерактивный экран просмотра рекламы за вознаграждение (Google AdMob Rewarded Simulator)
@MainActor
public struct RewardedAdView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var rewardManager = RewardAdManager.shared
    
    @State private var timeRemaining: Int = 30
    private let totalDuration: Double = 30.0
    @State private var isFinished: Bool = false
    @State private var timer: Timer? = nil
    @State private var progress: Double = 0.0
    @State private var isClaimed: Bool = false
    @State private var adCreativeIndex: Int = Int.random(in: 0...2)
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Верхний бар с брендингом Meta и таймером
                topBar
                
                Spacer()
                
                if !isFinished {
                    // Видео-плеер рекламы Meta
                    adPlayerCard
                } else {
                    // Экран получения супер-награды (+15 слотов)
                    rewardEarnedCard
                }
                
                Spacer()
                
                // Нижняя панель
                bottomInfoBar
            }
            .padding(20)
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Subviews
    
    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "infinity")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "0081FB"))
                Text("Реклама от Meta".localized)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
            
            Spacer()
            
            if !isFinished {
                HStack(spacing: 6) {
                    Text("Награда (+15):".localized)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                    
                    Text("\(timeRemaining)с")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.yellow.opacity(0.4), lineWidth: 1))
            } else {
                Button(action: {
                    claimRewardAndDismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }
    
    private var adPlayerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                // Анимированная карточка видео
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "0064E0"), Color(hex: "7C3AED"), Color(hex: "D946EF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 330)
                    .overlay(
                        VStack(spacing: 16) {
                            HStack {
                                HStack(spacing: 5) {
                                    Image(systemName: "infinity")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Meta Audience Network")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                                
                                Spacer()
                                
                                Text("HD • 60 FPS")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            
                            Spacer()
                            
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.22))
                                    .frame(width: 76, height: 76)
                                
                                Image(systemName: adIconName)
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white)
                            }
                            
                            VStack(spacing: 5) {
                                Text(adTitle)
                                    .font(.system(size: 19, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                
                                Text(adSubtitle)
                                    .font(.system(size: 12.5))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.88))
                                    .padding(.horizontal, 20)
                            }
                            
                            HStack(spacing: 12) {
                                Text("★★★★★ 4.9")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.yellow)
                                
                                Text("•")
                                    .foregroundStyle(.white.opacity(0.4))
                                
                                Text("Спонсировано Meta".localized)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            
                            Spacer()
                        }
                    )
            }
            
            // Прогресс-бар видео 30 секунд
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: "0081FB"), Color.yellow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
    
    private var adTitle: String {
        switch adCreativeIndex {
        case 0: return "Sony Alpha & Canon R Series"
        case 1: return "Adobe Creative Cloud Pro"
        default: return "SmartStock AI Max"
        }
    }
    
    private var adSubtitle: String {
        switch adCreativeIndex {
        case 0: return "Премиальная оптика для микростоковых фотографов со скидкой до 30%.".localized
        case 1: return "Нейросетевая ретушь и автоматическая пакетная цветокоррекция фото.".localized
        default: return "Автоматическая выгрузка на 10+ стоков и безлимитные SEO-теги в 1 клик.".localized
        }
    }
    
    private var adIconName: String {
        switch adCreativeIndex {
        case 0: return "camera.aperture"
        case 1: return "paintpalette.fill"
        default: return "sparkles.tv.fill"
        }
    }
    
    private var rewardEarnedCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "gift.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
            }
            
            VStack(spacing: 6) {
                Text("Супер-награда получена! 🎉".localized)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("+15 бонусных слотов начислены в вашу очередь".localized)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
            }
            
            Button(action: {
                claimRewardAndDismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Забрать +15 фото".localized)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [.yellow, Color(hex: "F59E0B")], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.yellow.opacity(0.4), radius: 10, y: 4)
            }
            .padding(.top, 10)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                )
        )
    }
    
    private var bottomInfoBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "infinity")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "0081FB"))
            
            Text("Meta Audience Network • Спонсорское видео (+15 слотов)".localized)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
    
    // MARK: - Helper Methods
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 1 {
                timeRemaining -= 1
                withAnimation(.linear(duration: 1.0)) {
                    progress = Double(30 - timeRemaining) / totalDuration
                }
            } else {
                timeRemaining = 0
                progress = 1.0
                isFinished = true
                timer?.invalidate()
                HapticHelper.notification(.success)
            }
        }
    }
    
    private func claimRewardAndDismiss() {
        guard !isClaimed else { return }
        isClaimed = true
        rewardManager.rewardUser(with: RewardAdManager.superRewardAmount)
        dismiss()
    }
}
