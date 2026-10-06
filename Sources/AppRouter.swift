import SwiftUI

/// Переключение вкладок из любого экрана (например, из вводной карточки на пустой очереди).
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Tab: Int, Hashable {
        case queue
        case prompt
        case agencies
        case settings
    }

    @Published var selectedTab: Tab = .queue

    private init() {}
}
