import SwiftUI
import UIKit

// MARK: - iOS 2026 Liquid Minimalist Design System
public struct AppleTheme {
    public static let primaryGradient = LinearGradient(
        colors: [Color(hex: "007AFF"), Color(hex: "6366F1")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let indigoGradient = LinearGradient(
        colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let emeraldGradient = LinearGradient(
        colors: [Color(hex: "10B981"), Color(hex: "059669")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let sunsetGradient = LinearGradient(
        colors: [Color(hex: "FF6B6B"), Color(hex: "FF8E53")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let cyanGradient = LinearGradient(
        colors: [Color(hex: "06B6D4"), Color(hex: "3B82F6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let accentBlue = Color(hex: "007AFF")
    public static let electricIndigo = Color(hex: "6366F1")
    public static let emerald = Color(hex: "10B981")
    public static let slateGray = Color(hex: "8E8E93")
    
    public static let glassBorder = Color.white.opacity(0.16)
    public static let glassBorderDark = Color.white.opacity(0.09)
}

// MARK: - Hex Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Clean Solid Background (No Glows)
struct LiquidBackgroundView: View {
    @Environment(\.colorScheme) var colorScheme
    var isAnimated: Bool = false
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        return ZStack {
            // Чистый плоский цвет фона без светящихся пятен и градиентных шаров
            let bgColor = isDark ? Color(hex: "0D0E12") : Color(hex: "F2F4F7")
            bgColor
            
            // Легкая аккуратная текстурная сетка точек
            let dotColor: Color = isDark ? Color.white.opacity(0.025) : Color.black.opacity(0.025)
            StaticDotGridView(dotColor: dotColor)
        }
        .ignoresSafeArea()
    }
}

struct StaticDotGridView: View {
    let dotColor: Color
    
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let dotSize: CGFloat = 1.0
            let spacing: CGFloat = 22.0
            for x in stride(from: 0, to: size.width, by: spacing) {
                for y in stride(from: 0, to: size.height, by: spacing) {
                    path.addRect(CGRect(x: x, y: y, width: dotSize, height: dotSize))
                }
            }
            context.fill(path, with: .color(dotColor))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Clean Flat & Glass Card Modifiers
struct GlassModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var cornerRadius: CGFloat
    var paddingValue: CGFloat
    
    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        
        return content
            .padding(paddingValue)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isDark ? Color(hex: "151821") : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.04), radius: 6, x: 0, y: 3)
    }
}

struct GlassAccentModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var accentColor: Color
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        return content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(accentColor.opacity(isDark ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accentColor.opacity(isDark ? 0.40 : 0.25), lineWidth: 1.0)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius, paddingValue: padding))
    }
    
    func glassCardAccent(accentColor: Color = AppleTheme.accentBlue, cornerRadius: CGFloat = 18) -> some View {
        self.modifier(GlassAccentModifier(accentColor: accentColor, cornerRadius: cornerRadius))
    }
    
    func ambientShadow(radius: CGFloat = 6, y: CGFloat = 3) -> some View {
        self.shadow(color: Color.black.opacity(0.08), radius: radius, x: 0, y: y)
    }
    
    // Безопасный метод без неонового свечения (чистая строгая тень)
    func neonShadow(color: Color = .clear, radius: CGFloat = 6, x: CGFloat = 0, y: CGFloat = 3) -> some View {
        self.shadow(color: Color.black.opacity(0.08), radius: radius, x: x, y: y)
    }
    
    func gradientText(_ gradient: LinearGradient = AppleTheme.primaryGradient) -> some View {
        self.overlay(gradient)
            .mask(self)
    }
}

// MARK: - SwiftUI Vector Glass Logo
struct SmartStockLogoView: View {
    @Environment(\.colorScheme) var colorScheme
    var size: CGFloat = 72
    
    var body: some View {
        let isDark = colorScheme == .dark
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(isDark ? Color(hex: "181B26").opacity(0.8) : Color.white.opacity(0.9))
                .background(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )
                .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.08), radius: 8, x: 0, y: 4)
            
            RotatingApertureView(size: size)
            
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundStyle(AppleTheme.cyanGradient)
                .offset(x: size * 0.18, y: -size * 0.18)
        }
    }
}

struct RotatingApertureView: View {
    var size: CGFloat
    @State private var rotateLogo = false
    
    var body: some View {
        Image(systemName: "camera.aperture")
            .font(.system(size: size * 0.46, weight: .regular))
            .foregroundStyle(AppleTheme.primaryGradient)
            .rotationEffect(Angle(degrees: rotateLogo ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                    rotateLogo = true
                }
            }
    }
}

// MARK: - Safe Sendable Binding Wrapper
struct SendableBinding<Value>: @unchecked Sendable {
    let binding: Binding<Value>
}

// MARK: - Tactile Haptic Helper
public struct HapticHelper {
    public static func trigger(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    public static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
    
    public static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

// MARK: - Elastic Premium Button Style
public struct PremiumButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - iOS View Modifiers & Clean Glass Borders
extension View {
    @ViewBuilder
    public func applyScrollTransitionIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1.0 : 0.88)
                    .scaleEffect(phase.isIdentity ? 1.0 : 0.97)
            }
        } else {
            self
        }
    }
    
    public func spatial3DTilt() -> some View {
        self.modifier(Spatial3DTiltModifier())
    }
    
    public func quantumNeonBorder(cornerRadius: CGFloat = 20) -> some View {
        self.modifier(LiquidGlassBorderModifier(cornerRadius: cornerRadius))
    }
    
    public func liquidGlassBorder(cornerRadius: CGFloat = 20) -> some View {
        self.modifier(LiquidGlassBorderModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - iOS 2026 Spatial & Liquid Glass Modifiers
struct Spatial3DTiltModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .scrollTransition(.animated(.spring(response: 0.35, dampingFraction: 0.8))) { view, phase in
                    view
                        .scaleEffect(phase.isIdentity ? 1.0 : 0.97)
                        .rotation3DEffect(
                            .degrees(phase.value * -3.5),
                            axis: (x: 1, y: 0, z: 0),
                            perspective: 0.8
                        )
                }
        } else {
            content
        }
    }
}

struct LiquidGlassBorderModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.18 : 0.40),
                                Color.white.opacity(isDark ? 0.05 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
    }
}

