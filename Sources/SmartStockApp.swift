import SwiftUI
import UIKit
import BackgroundTasks

@main
struct SmartStockApp: App {
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @StateObject private var viewModel = QueueViewModel()
    @StateObject private var authManager = AuthManager.shared
    @State private var tabViewID = UUID()
    @State private var isReloadingLanguage = false
    
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
            if isReloadingLanguage {
                ZStack {
                    LiquidBackgroundView()
                    VStack(spacing: 20) {
                        SmartStockLogoView(size: 80)
                        ProgressView()
                            .tint(Color(hex: "7C3AED"))
                    }
                }
                .preferredColorScheme(colorScheme)
                .transition(.opacity)
            } else if authManager.isAuthenticated {
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isReloadingLanguage = true
                    }
                    // Даем 0.35 секунды на закрытие системного меню и плавную анимацию скрытия TabView
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        tabViewID = UUID()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isReloadingLanguage = false
                        }
                    }
                }
            } else {
                AuthView(authManager: authManager)
                    .preferredColorScheme(.dark)
            }
        }
    }
}

