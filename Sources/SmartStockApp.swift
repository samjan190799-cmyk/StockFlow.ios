import SwiftUI
import UIKit
import BackgroundTasks

@main
struct SmartStockApp: App {
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @StateObject private var viewModel = QueueViewModel()
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var colorScheme: ColorScheme? {
        switch sysTheme {
        case "Темная": return .dark
        case "Светлая": return .light
        default: return nil
        }
    }
    
    init() {
        // Регистрация базовых дефолтных настроек системы
        UserDefaults.standard.register(defaults: [
            "sys_language": "Русский",
            "sys_theme": "Темная",
            "sys_bg_scheduler": false,
            "sys_scheduler_interval_hours": 1,
            "sys_auto_upscale": false,
            "sys_upscale_threshold": "Меньше 4 МБ (Рекомендуется)",
            "sys_upscale_factor": "Увеличение 2x (Бикубическое)",
            "sys_parallel_streams": 1,
            "sys_seq_video": true,
            "sys_seq_photo": true,
            "sys_retry_on_fail": true,
            "sys_compress_jpeg": false,
            "sys_notifications": true,
            "sys_no_cache_mode": true,
            "sys_pc_server_enabled": false,
            "sys_pc_server_address": "192.168.1.50:5000"
        ])
        
        // Pre-configure initial state of platforms in UserDefaults if not present
        if UserDefaults.standard.data(forKey: "stock_platforms") == nil {
            if let encoded = try? JSONEncoder().encode(StockPlatform.defaults) {
                UserDefaults.standard.set(encoded, forKey: "stock_platforms")
            }
        }
        
        // Настройка TabBar в стеклянном стиле (полупрозрачный blur). На iOS 26+ остаётся системный Liquid Glass.
        if #unavailable(iOS 26.0) {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)
        
        let activeColor = UIColor(red: 10/255, green: 108/255, blue: 255/255, alpha: 1.0)
        let normalColor = UIColor.secondaryLabel
        
        appearance.stackedLayoutAppearance.selected.iconColor = activeColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: activeColor]
        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        
        // Запрос авторизации для уведомлений при запуске
        if UserDefaults.standard.bool(forKey: "sys_notifications") {
            NotificationHelper.requestAuthorization()
        }
        
        // Регистрация фонового планировщика
        SchedulerManager.shared.registerBackgroundTask()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                LiquidBackgroundView(isAnimated: true) // Единый фон на уровне всего приложения
                
                TabView(selection: $router.selectedTab) {
                    GalleryView(viewModel: viewModel)
                        .tabItem {
                            Label("Очередь".localized, systemImage: "photo.on.rectangle")
                        }
                        .tag(AppRouter.Tab.queue)
                    
                    AIAssistantView()
                         .tabItem {
                             Label("Промпт".localized, systemImage: "text.bubble")
                         }
                         .tag(AppRouter.Tab.prompt)
                    
                    StockSettingsView()
                        .tabItem {
                            Label("Агентства".localized, systemImage: "building.2")
                        }
                        .tag(AppRouter.Tab.agencies)
                    
                    SystemSettingsView()
                        .tabItem {
                            Label("Настройки".localized, systemImage: "gearshape")
                        }
                        .tag(AppRouter.Tab.settings)
                }
            }
            .preferredColorScheme(colorScheme)
            .tint(AppPalette.accent)
            .onChange(of: scenePhase) { phase in
                FTPTranscriptLogger.shared.logLifecycle(phase)
                // Подписка могла закончиться или продлиться, пока приложение было в фоне
                if phase == .active {
                    Task { await StoreManager.shared.updateCustomerProductStatus() }
                }
            }
        }
    }
}

