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
        
        // Настройка TabBar для соответствия стилю Glassmorphism в обеих темах
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.3)
        appearance.shadowImage = UIImage()
        
        let activeColor = UIColor(red: 124/255, green: 58/255, blue: 237/255, alpha: 1.0)
        let normalColor = UIColor.secondaryLabel
        
        appearance.stackedLayoutAppearance.selected.iconColor = activeColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: activeColor]
        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
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
    
    /// Применяет ограничение FPS через CADisplayLink preferred frame rate
    private func applyFrameRate(_ fpsSetting: String) {
        let targetFps: Int
        if fpsSetting.contains("120") {
            targetFps = 120
        } else if fpsSetting.contains("30") {
            targetFps = 30
        } else {
            targetFps = 60
        }
        
        // iOS 15+: устанавливаем preferredFrameRateRange для всех окон
        if #available(iOS 15.0, *) {
            let range = CAFrameRateRange(minimum: Float(min(targetFps, 30)),
                                         maximum: Float(targetFps),
                                         preferred: Float(targetFps))
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        window.layer.preferredFrameRateRange = range
                    }
                }
            }
        }
    }
}
