import SwiftUI
import UIKit
import BackgroundTasks

@main
struct SmartStockApp: App {
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @StateObject private var viewModel = QueueViewModel()
    @StateObject private var authManager = AuthManager.shared
    
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
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ZStack {
                    LiquidBackgroundView(isAnimated: true) // Единый фон на уровне всего приложения
                    
                    if sysLanguage == "English" {
                        tabView(for: "English")
                    } else if sysLanguage == "Հայերեն" {
                        tabView(for: "Հայերեն")
                    } else {
                        tabView(for: "Русский")
                    }
                }
                .preferredColorScheme(colorScheme)
                .tint(Color(hex: "7C3AED"))
            } else {
                AuthView(authManager: authManager)
                    .preferredColorScheme(.dark)
            }
        }
    }
    
    @ViewBuilder
    private func tabView(for lang: String) -> some View {
        TabView {
            UploadQueueView(viewModel: viewModel)
                .tabItem {
                    Label(Localizer.translate("Галерея", to: lang), systemImage: "photo.on.rectangle")
                }
            
            AIAssistantView()
                 .tabItem {
                     Label(Localizer.translate("ИИ", to: lang), systemImage: "brain")
                 }
            
            InsightsView()
                 .tabItem {
                     Label(Localizer.translate("Статистика", to: lang), systemImage: "chart.line.uptrend.xyaxis")
                 }
            
            StockSettingsView()
                .tabItem {
                    Label(Localizer.translate("Агентства", to: lang), systemImage: "arrow.left.and.right")
                }
            
            SystemSettingsView()
                .tabItem {
                    Label(Localizer.translate("Настройки", to: lang), systemImage: "gearshape")
                }
        }
    }
}

