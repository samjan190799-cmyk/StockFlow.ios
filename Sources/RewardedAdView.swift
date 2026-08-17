import SwiftUI

/// Интерактивный экран просмотра рекламы за вознаграждение (Google AdMob Rewarded Simulator)
@MainActor
public struct RewardedAdView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var rewardManager = RewardAdManager.shared
    
    @State private var timeRemaining: Int = 15
    @State private var isFinished: Bool = false
    @State private var timer: Timer? = nil
    @State private var progress: Double = 0.0
    @State private var isClaimed: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Верхний бар с таймером и кнопкой закрытия
                topBar
                
                Spacer()
                
                if !isFinished {
                    // Видео-плеер рекламы
                    adPlayerCard
                } else {
                    // Экран получения награды
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
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.yellow)
                Text("Спонсорский ролик".localized)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
            
            Spacer()
            
            if !isFinished {
                HStack(spacing: 6) {
                    Text("Награда через:".localized)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Text("\(timeRemaining)с")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.4))
                .clipShape(Capsule())
            } else {
                Button(action: {
                    claimRewardAndDismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.8))
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
                            colors: [Color(hex: "4F46E5"), Color(hex: "7C3AED"), Color(hex: "DB2777")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 320)
                    .overlay(
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "sparkles.tv.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white)
                            }
                            
                            VStack(spacing: 4) {
                                Text("SmartStock AI Studio")
                                    .font(.system(size: 20, weight: .heavy))
                                    .foregroundStyle(.white)
                                
                                Text("Автоматическая выгрузка на 10+ стоков и безлимитные теги ИИ".localized)
                                    .font(.system(size: 13))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 20)
                            }
                            
                            HStack(spacing: 12) {
                                Text("★★★★★ 4.9")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.yellow)
                                
                                Text("•")
                                    .foregroundStyle(.white.opacity(0.4))
                                
                                Text("100K+ Загрузок".localized)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    )
            }
            
            // Прогресс-бар видео
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                }
            }
            .frame(height: 6)
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
                Text("Награда получена! 🎉".localized)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("+5 бонусных фото начислены в вашу очередь".localized)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
            }
            
            Button(action: {
                claimRewardAndDismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Забрать +5 фото".localized)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.yellow)
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
        HStack {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
            
            Text("Google AdMob Rewarded • Смотрите видео для бесплатных слотов".localized)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
    
    // MARK: - Helper Methods
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 1 {
                timeRemaining -= 1
                withAnimation(.linear(duration: 1.0)) {
                    progress = Double(15 - timeRemaining) / 15.0
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
        rewardManager.rewardUser(with: 5)
        dismiss()
    }
}
