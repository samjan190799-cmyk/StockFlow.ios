import SwiftUI

@main
struct SmartStockApp: App {
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @State private var photos: [PhotoMetadata] = []
    
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
                UploadQueueView(photos: $photos)
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
            .onAppear(perform: loadMockPhotos)
        }
    }
    
    private func loadMockPhotos() {
        // Prepopulate with a few demo photos so the app isn't blank on startup
        photos = [
            PhotoMetadata(
                filename: "2025_01_19_16_42_IMG_0876.JPG",
                fileSize: "2.34 МБ",
                title: "Flock of Birds Soaring in Overcast Grey Sky",
                keywords: ["птицы", "стая", "небо", "полет", "серое небо", "пасмурно"],
                description: "Стая птиц летит в пасмурном сером небе, минималистичный кадр.",
                status: .ready
            ),
            PhotoMetadata(
                filename: "2025_02_04_00_22_IMG_5830.JPG",
                fileSize: "0.34 МБ",
                title: "Deep Blue Sunset Sky with Silhouetted Trees",
                keywords: ["закат", "деревья", "силуэт", "синее небо", "вечер"],
                description: "Яркий закат переходящий в глубокий синий цвет с силуэтами деревьев на переднем плане.",
                status: .ready
            ),
            PhotoMetadata(
                filename: "2025_02_07_09_33_IMG_1382.JPG",
                fileSize: "2.37 МБ",
                title: "Industrial Landscape under Warm Sunrise Light",
                keywords: ["промзона", "рассвет", "завод", "трубы", "дым", "солнце"],
                description: "Индустриальный пейзаж на рассвете, заводы и трубы в лучах утреннего солнца.",
                status: .new
            )
        ]
    }
}
