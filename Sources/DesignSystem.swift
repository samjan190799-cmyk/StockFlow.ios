import SwiftUI
import UIKit

// MARK: - iOS 2026/2027 Apple HIG Liquid Glass Design System
public struct AppleTheme {
    // Primary Vibrant Gradients
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
    
    public static let aetherGlassGradient = LinearGradient(
        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Solid Accent Tokens
    public static let accentBlue = Color(hex: "007AFF")
    public static let electricIndigo = Color(hex: "6366F1")
    public static let emerald = Color(hex: "10B981")
    public static let amber = Color(hex: "F59E0B")
    public static let crimson = Color(hex: "EF4444")
    public static let slateGray = Color(hex: "8E8E93")
    
    // Background Tokens
    public static let obsidianDark = Color(hex: "0B0C10")
    public static let cardDark = Color(hex: "141620")
    public static let cardLight = Color.white
    public static let borderDark = Color.white.opacity(0.08)
    public static let borderLight = Color.black.opacity(0.06)
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

// MARK: - Clean Solid Background with Ambient Sub-grid
public struct LiquidBackgroundView: View {
    @Environment(\.colorScheme) var colorScheme
    var isAnimated: Bool = false
    
    public init(isAnimated: Bool = false) {
        self.isAnimated = isAnimated
    }
    
    public var body: some View {
        let isDark = colorScheme == .dark
        
        return ZStack {
            let bgColor = isDark ? AppleTheme.obsidianDark : Color(hex: "F4F6F9")
            bgColor
            
            // Тонкая аккуратная системная сетка
            let dotColor: Color = isDark ? Color.white.opacity(0.025) : Color.black.opacity(0.025)
            StaticDotGridView(dotColor: dotColor)
        }
        .ignoresSafeArea()
    }
}

public struct StaticDotGridView: View {
    let dotColor: Color
    
    public var body: some View {
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

// MARK: - 2026/2027 Liquid Glass Card Modifiers
@MainActor
public struct GlassModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    public var cornerRadius: CGFloat
    public var paddingValue: CGFloat
    
    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        
        return content
            .padding(paddingValue)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isDark ? AppleTheme.cardDark.opacity(0.92) : AppleTheme.cardLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                isDark ? Color.white.opacity(0.14) : Color.white,
                                isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.28 : 0.04), radius: 8, x: 0, y: 4)
    }
}

@MainActor
public struct GlassAccentModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    public var accentColor: Color
    public var cornerRadius: CGFloat
    
    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        return content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(accentColor.opacity(isDark ? 0.16 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accentColor.opacity(isDark ? 0.45 : 0.28), lineWidth: 1.0)
            )
    }
}

// MARK: - Floating Glass Bottom Bar Modifier
@MainActor
public struct FloatingGlassBarModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    public var cornerRadius: CGFloat = 26
    
    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        return content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isDark ? Color(hex: "181B26").opacity(0.88) : Color.white.opacity(0.90))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.22 : 0.6),
                                Color.white.opacity(isDark ? 0.05 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.40 : 0.12), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Shimmer AI Scan Animation Modifier
public struct ShimmerScanModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0
    public var isActive: Bool
    
    public func body(content: Content) -> some View {
        if isActive {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                Color.clear,
                                AppleTheme.accentBlue.opacity(0.35),
                                AppleTheme.electricIndigo.opacity(0.45),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .rotationEffect(.degrees(30))
                        .offset(x: phase * geo.size.width * 2)
                    }
                    .mask(content)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        phase = 1.0
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    public func glassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius, paddingValue: padding))
    }
    
    public func glassCardAccent(accentColor: Color = AppleTheme.accentBlue, cornerRadius: CGFloat = 18) -> some View {
        self.modifier(GlassAccentModifier(accentColor: accentColor, cornerRadius: cornerRadius))
    }
    
    public func floatingGlassBar(cornerRadius: CGFloat = 26) -> some View {
        self.modifier(FloatingGlassBarModifier(cornerRadius: cornerRadius))
    }
    
    public func shimmerScan(isActive: Bool) -> some View {
        self.modifier(ShimmerScanModifier(isActive: isActive))
    }
    
    public func ambientShadow(radius: CGFloat = 6, y: CGFloat = 3) -> some View {
        self.shadow(color: Color.black.opacity(0.08), radius: radius, x: 0, y: y)
    }
    
    public func neonShadow(color: Color = .clear, radius: CGFloat = 6, x: CGFloat = 0, y: CGFloat = 3) -> some View {
        self.shadow(color: Color.black.opacity(0.08), radius: radius, x: x, y: y)
    }
    
    public func gradientText(_ gradient: LinearGradient = AppleTheme.primaryGradient) -> some View {
        self.overlay(gradient)
            .mask(self)
    }
}

// MARK: - SwiftUI Vector Glass Logo
public struct SmartStockLogoView: View {
    @Environment(\.colorScheme) var colorScheme
    public var size: CGFloat = 72
    
    public init(size: CGFloat = 72) {
        self.size = size
    }
    
    public var body: some View {
        let isDark = colorScheme == .dark
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(isDark ? Color(hex: "181B26") : Color.white)
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
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.08), radius: 6, x: 0, y: 3)
            
            RotatingApertureView(size: size)
            
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundStyle(AppleTheme.cyanGradient)
                .offset(x: size * 0.18, y: -size * 0.18)
        }
    }
}

public struct RotatingApertureView: View {
    public var size: CGFloat
    @State private var rotateLogo = false
    
    public init(size: CGFloat) {
        self.size = size
    }
    
    public var body: some View {
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
public struct SendableBinding<Value>: @unchecked Sendable {
    public let binding: Binding<Value>
    public init(binding: Binding<Value>) {
        self.binding = binding
    }
}

// MARK: - Apple HIG Tactile Haptic Engine
@MainActor
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
    
    public static func tap() {
        trigger(.light)
    }
    
    public static func success() {
        notification(.success)
    }
    
    public static func warning() {
        notification(.warning)
    }
    
    public static func error() {
        notification(.error)
    }
}

// MARK: - Elastic Premium Spring Button Style
public struct PremiumButtonStyle: ButtonStyle {
    public var isAccent: Bool
    
    public init(isAccent: Bool = false) {
        self.isAccent = isAccent
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if newValue {
                    Task { @MainActor in
                        HapticHelper.trigger(.light)
                    }
                }
            }
    }
}

public struct ScaleButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
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

// MARK: - iOS 2026/2027 Spatial & Liquid Glass Modifiers
@MainActor
public struct Spatial3DTiltModifier: ViewModifier {
    public func body(content: Content) -> some View {
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

@MainActor
public struct LiquidGlassBorderModifier: ViewModifier {
    public var cornerRadius: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.20 : 0.45),
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

// MARK: - Thread-Safe Cached Date Formatters
public enum AppDateFormatters {
    public static let recordFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd MMM HH:mm"
        return formatter
    }()
    
    public static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
    
    public static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "MMM"
        return formatter
    }()
    
    public static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd MMM"
        return formatter
    }()
}
