import SwiftUI
import UIKit
import BackgroundTasks

@main
struct SmartStockApp: App {
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @AppStorage("sys_fps") private var sysFps: String = "120 FPS (Ультра-плавность)"
    @StateObject private var viewModel = QueueViewModel()
    @StateObject private var authManager = AuthManager.shared
    @State private var tabViewID = UUID()
    
    var colorScheme: ColorScheme? {
        switch sysTheme {
        case "Темная": return .dark
        case "Светлая": return .light
        default: return nil
        }
    }
    
    init() {
        // Pre-configure initial state of platforms in UserDefaults if not present
        if UserDefaults.standard.data(forKey: "stock_platforms") == nil {
            if let encoded = try? JSONEncoder().encode(StockPlatform.defaults) {
                UserDefaults.standard.set(encoded, forKey: "stock_platforms")
            }
        }
        
        // Настройка TabBar в стеклянном стиле (полупрозрачный blur)
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)
        
        let activeColor = UIColor(red: 124/255, green: 58/255, blue: 237/255, alpha: 1.0)
        let normalColor = UIColor.secondaryLabel
        
        appearance.stackedLayoutAppearance.selected.iconColor = activeColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: activeColor]
        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        
        // Запрос авторизации для уведомлений при запуске
        if UserDefaults.standard.bool(forKey: "sys_notifications") {
            NotificationHelper.requestAuthorization()
        }
        
        // Регистрация фонового планировщика
        SchedulerManager.shared.registerBackgroundTask()
    }
    
    @State private var displayLinkHelper = DisplayLinkHelper()
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                // id(sysLanguage) перестраивает всё дерево при смене языка — это единственный
                // надёжный способ перерендерить .tabItem labels, которые вычисляются при инициализации
                TabView {
                    UploadQueueView(viewModel: viewModel)
                        .tabItem {
                            Label("Галерея".localized, systemImage: "photo.on.rectangle")
                        }
                    
                    AIAssistantView()
                         .tabItem {
                             Label("ИИ".localized, systemImage: "brain")
                         }
                    
                    InsightsView()
                         .tabItem {
                             Label("Статистика".localized, systemImage: "chart.line.uptrend.xyaxis")
                         }
                    
                    StockSettingsView()
                        .tabItem {
                            Label("Агентства".localized, systemImage: "arrow.left.and.right")
                        }
                    
                    SystemSettingsView()
                        .tabItem {
                            Label("Настройки".localized, systemImage: "gearshape")
                        }
                }
                .id(tabViewID) // Перестраивает UI при смене языка
                .preferredColorScheme(colorScheme)
                .tint(Color(hex: "7C3AED"))
                .onChange(of: sysLanguage) { _ in
                    DispatchQueue.main.async {
                        tabViewID = UUID()
                    }
                }
                .onChange(of: sysFps) { newFps in
                    applyFrameRate(newFps)
                }
                .onAppear {
                    applyFrameRate(sysFps)
                }
            } else {
                AuthView(authManager: authManager)
                    .preferredColorScheme(.dark)
            }
        }
    }
    
    /// Применяет ограничение FPS через CADisplayLink
    private func applyFrameRate(_ fpsSetting: String) {
        let targetFps: Int
        if fpsSetting.contains("120") {
            targetFps = 120
        } else if fpsSetting.contains("30") {
            targetFps = 30
        } else {
            targetFps = 60
        }
        
        displayLinkHelper.setup(fps: targetFps)
    }
}

// MARK: - DisplayLinkHelper
/// Вспомогательный класс для динамической адаптации частоты кадров (ProMotion) на iOS
final class DisplayLinkHelper: NSObject {
    private var displayLink: CADisplayLink?
    
    func setup(fps: Int) {
        displayLink?.invalidate()
        
        let link = CADisplayLink(target: self, selector: #selector(step))
        if #available(iOS 15.0, *) {
            let rate = Float(fps)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        } else {
            link.preferredFramesPerSecond = fps
        }
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }
    
    @objc private func step() {
        // Пустая функция-обработчик
    }
    
    deinit {
        displayLink?.invalidate()
    }
}

