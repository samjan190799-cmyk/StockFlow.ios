import SwiftUI
import UIKit
import BackgroundTasks

@main
struct SmartStockApp: App {
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @StateObject private var viewModel = QueueViewModel()
    
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
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                LiquidBackgroundView(isAnimated: true) // Единый фон на уровне всего приложения
                
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
                .id(sysLanguage)
            }
            .preferredColorScheme(colorScheme)
            .tint(Color(hex: "007AFF"))
        }
    }
}

