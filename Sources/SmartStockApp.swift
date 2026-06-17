import SwiftUI

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
