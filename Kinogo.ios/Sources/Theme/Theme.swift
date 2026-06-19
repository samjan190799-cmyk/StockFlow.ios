import SwiftUI

// Дизайн-система Theme для KinogoVOD (Стиль 2026: спокойный минимализм, теплые тона, обилие пространства)
public enum Theme {
    
    // Цветовая палитра
    public enum Colors {
        // Основной фон - мягкий глубокий угольный цвет (Warm Charcoal)
        public static let background = Color(red: 0.08, green: 0.08, blue: 0.09)
        
        // Вторичный фон для карточек и панелей - теплый темно-серый (Warm Slate)
        public static let surface = Color(red: 0.13, green: 0.13, blue: 0.14)
        
        // Основной текст - нежный цвет шампанского / песочный (Champagne / Sand)
        public static let primaryText = Color(red: 0.95, green: 0.92, blue: 0.88)
        
        // Вторичный текст - приглушенный теплый серый
        public static let secondaryText = Color(red: 0.60, green: 0.58, blue: 0.56)
        
        // Цвет тонких разделителей и границ (Fine Border) - очень мягкий серый
        public static let border = Color(red: 0.22, green: 0.21, blue: 0.20)
        
        // Акцентный цвет для кнопок воспроизведения и активных элементов (приглушенный оливково-золотой / мускатный)
        public static let accent = Color(red: 0.82, green: 0.74, blue: 0.65)
    }
    
    // Настройки скруглений углов
    public enum Radius {
        public static let small: CGFloat = 6
        public static let card: CGFloat = 12
        public static let button: CGFloat = 20
        public static let large: CGFloat = 24
    }
    
    // Конфигурации анимаций (плавные и незаметные в духе 2026 года)
    public enum Animations {
        public static let swiftTransition = Animation.spring(response: 0.4, dampingFraction: 0.85, blendDuration: 0)
        public static let slowFade = Animation.easeInOut(duration: 0.3)
    }
    
    // Тонкие рамки для карточек и кнопок
    public static func fineBorder() -> some ViewModifier {
        FineBorderModifier()
    }
}

// Модификатор для создания ультратонких спокойных рамок
struct FineBorderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Colors.border, lineWidth: 0.5)
            )
    }
}
