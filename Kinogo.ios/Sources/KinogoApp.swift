import SwiftUI

// Точка входа в iOS-приложение KinogoVOD
@main
struct KinogoApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark) // Принудительно устанавливаем темную тему для атмосферы кинозала
        }
    }
}
