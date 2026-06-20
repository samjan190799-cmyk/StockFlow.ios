import SwiftUI
import UIKit

@main
struct SmartStockApp: App {
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
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
            TabView {
                UploadQueueView(viewModel: viewModel)
                    .tabItem {
                        Label("Очередь", systemImage: "tray.and.arrow.down")
                    }
                
                AIAssistantView()
                    .tabItem {
                        Label("ИИ-Ассистент", systemImage: "sparkles")
                    }
                
                StockSettingsView()
                    .tabItem {
                        Label("Стоки", systemImage: "network")
                    }
                
                SystemSettingsView()
                    .tabItem {
                        Label("Параметры", systemImage: "gearshape")
                    }
            }
            .preferredColorScheme(colorScheme)
        }
    }
}
