import SwiftUI
import UIKit

@main
struct SmartStockApp: App {
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @AppStorage("sys_fps") private var sysFps: String = "120 FPS (Ультра-плавность)"
    @StateObject private var viewModel = QueueViewModel()
    
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
        
        // Настройка TabBar для соответствия нео-минималистичному стилю
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.12)
        
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
    }
    
    @State private var displayLinkHelper = DisplayLinkHelper()
    
    var body: some Scene {
        WindowGroup {
            // id(sysLanguage) перестраивает всё дерево при смене языка — это единственный
            // надёжный способ перерендерить .tabItem labels, которые вычисляются при инициализации
            TabView {
                UploadQueueView(viewModel: viewModel)
                    .tabItem {
                        Label("Очередь".localized, systemImage: "tray.and.arrow.down")
                    }
                
                AIAssistantView()
                     .tabItem {
                         Label("ИИ-Ассистент".localized, systemImage: "sparkles")
                     }
                
                StockSettingsView()
                    .tabItem {
                        Label("Стоки".localized, systemImage: "network")
                    }
                
                SystemSettingsView()
                    .tabItem {
                        Label("Параметры".localized, systemImage: "gearshape")
                    }
            }
            .id(sysLanguage) // Перестраивает UI при смене языка
            .preferredColorScheme(colorScheme)
            .onChange(of: sysFps) { newFps in
                applyFrameRate(newFps)
            }
            .onAppear {
                applyFrameRate(sysFps)
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
            let minFps = Float(min(fps, 30))
            let maxFps = Float(fps)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: minFps, maximum: maxFps, preferred: maxFps)
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

