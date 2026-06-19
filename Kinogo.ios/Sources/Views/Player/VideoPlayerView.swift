import SwiftUI
import AVKit

// Полноэкранный видеоплеер с кастомным минималистичным UI (Стиль 2026: деликатный песочный оверлей, автоскрытие)
public struct VideoPlayerView: View {
    let videoURL: URL
    let movieTitle: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showControls = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isDraggingSlider = false
    
    // Таймер для автоматического скрытия интерфейса управления
    @State private var controlsTimer: Task<Void, Never>? = nil
    
    public init(videoURL: URL, movieTitle: String) {
        self.videoURL = videoURL
        self.movieTitle = movieTitle
    }
    
    public var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()
            
            // Нативный проигрыватель видео, скрытый за кастомным интерфейсом
            if let player = player {
                CustomAVPlayerRepresentable(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(Theme.Animations.swiftTransition) {
                            showControls.toggle()
                        }
                        if showControls {
                            resetControlsTimer()
                        }
                    }
            } else {
                ProgressView()
                    .tint(Theme.Colors.accent)
            }
            
            // Кастомный оверлей управления (дизайн 2026 года - тонкий, без подложек, песочный акцент)
            if showControls {
                ZStack {
                    // Задний фон для лучшей читаемости поверх видео (мягкий градиент сверху и снизу)
                    VStack {
                        // Верхняя панель
                        HStack {
                            Button(action: {
                                player?.pause()
                                dismiss()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 18, weight: .light))
                                    Text("Назад")
                                        .font(.system(size: 16, weight: .light))
                                }
                                .foregroundColor(Theme.Colors.primaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.Colors.surface.opacity(0.6))
                                .cornerRadius(Theme.Radius.button)
                                .modifier(FineBorderModifier())
                            }
                            
                            Spacer()
                            
                            Text(movieTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Theme.Colors.primaryText)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.Colors.surface.opacity(0.6))
                                .cornerRadius(Theme.Radius.button)
                                .modifier(FineBorderModifier())
                            
                            Spacer()
                            
                            // Заглушка для баланса
                            Spacer()
                                .frame(width: 80)
                        }
                        .padding(.top, 16)
                        .padding(.horizontal)
                        
                        Spacer()
                        
                        // Центральная кнопка воспроизведения (крупная, но легкая и тонкая)
                        Button(action: togglePlayPause) {
                            Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                                .font(.system(size: 72, weight: .ultraLight))
                                .foregroundColor(Theme.Colors.accent)
                        }
                        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                        
                        Spacer()
                        
                        // Нижняя панель (слайдер времени и кнопки)
                        VStack(spacing: 12) {
                            // Слайдер прогресса
                            HStack(spacing: 12) {
                                Text(formatTime(currentTime))
                                    .font(.system(size: 12, weight: .light, design: .monospaced))
                                    .foregroundColor(Theme.Colors.secondaryText)
                                
                                Slider(value: $currentTime, in: 0...max(1, duration), onEditingChanged: { editing in
                                    isDraggingSlider = editing
                                    if !editing {
                                        seekToTime(currentTime)
                                    }
                                })
                                .tint(Theme.Colors.accent)
                                
                                Text(formatTime(duration))
                                    .font(.system(size: 12, weight: .light, design: .monospaced))
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            
                            // Дополнительные кнопки (15 сек назад/вперед)
                            HStack(spacing: 40) {
                                Button(action: { skip(-15) }) {
                                    Image(systemName: "gobackward.15")
                                        .font(.system(size: 24, weight: .light))
                                }
                                
                                Button(action: togglePlayPause) {
                                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 26, weight: .light))
                                }
                                
                                Button(action: { skip(15) }) {
                                    Image(systemName: "goforward.15")
                                        .font(.system(size: 24, weight: .light))
                                }
                            }
                            .foregroundColor(Theme.Colors.primaryText)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background(Theme.Colors.surface.opacity(0.8))
                        .cornerRadius(Theme.Radius.large)
                        .modifier(FineBorderModifier())
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
                .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .statusBarHidden(!showControls)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            controlsTimer?.cancel()
        }
    }
    
    private func setupPlayer() {
        let playerItem = AVPlayerItem(url: videoURL)
        let newPlayer = AVPlayer(playerItem: playerItem)
        self.player = newPlayer
        
        // Отслеживание времени воспроизведения
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if !isDraggingSlider {
                self.currentTime = time.seconds
            }
            if let durationTime = newPlayer.currentItem?.duration.seconds, !durationTime.isNaN {
                self.duration = durationTime
            }
        }
        
        // Автоматическое воспроизведение
        newPlayer.play()
        isPlaying = true
        resetControlsTimer()
    }
    
    private func togglePlayPause() {
        resetControlsTimer()
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    private func seekToTime(_ time: Double) {
        resetControlsTimer()
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime)
    }
    
    private func skip(_ seconds: Double) {
        resetControlsTimer()
        let targetTime = currentTime + seconds
        let clampedTime = max(0, min(duration, targetTime))
        seekToTime(clampedTime)
    }
    
    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 секунды
            if !Task.isCancelled && isPlaying && !isDraggingSlider {
                withAnimation(Theme.Animations.slowFade) {
                    showControls = false
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "00:00" }
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// SwiftUI-обертка для AVPlayer
struct CustomAVPlayerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false // Скрываем нативный UI
        controller.videoGravity = .resizeAspect
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
