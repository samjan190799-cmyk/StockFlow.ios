import SwiftUI
import UIKit

// MARK: - iOS 26 Liquid Minimalist Theme
struct AppleTheme {
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "007AFF"), Color(hex: "5E5CE6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let accentBlue = Color(hex: "007AFF")
    static let slateGray = Color(hex: "8E8E93")
    
    static let glassBorder = Color.white.opacity(0.12)
    static let glassBorderDark = Color.white.opacity(0.08)
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

// MARK: - Liquid Ambient Background (Clean Deep Space / Snow)
struct LiquidBackgroundView: View {
    @Environment(\.colorScheme) var colorScheme
    var isAnimated: Bool = false
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        return ZStack {
            if isAnimated {
                let bgColor = isDark ? Color(hex: "0B0C0E") : Color(hex: "F6F7FA")
                bgColor
                
                // Мягкий невидимый свет без неона
                AnimatedBlobsView(isDark: isDark)
                
                // Легкая текстурированная точка
                let dotColor: Color = isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.03)
                StaticDotGridView(dotColor: dotColor)
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea()
    }
}

struct AnimatedBlobsView: View {
    let isDark: Bool
    
    var body: some View {
        ZStack {
            if isDark {
                Circle()
                    .fill(Color(hex: "007AFF").opacity(0.025))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
            } else {
                Circle()
                    .fill(Color(hex: "007AFF").opacity(0.015))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
            }
        }
        .allowsHitTesting(false)
    }
}

struct StaticDotGridView: View {
    let dotColor: Color
    
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let dotSize: CGFloat = 1.0
            let spacing: CGFloat = 20.0
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

// MARK: - Liquid Minimalist Glass Card Modifier
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
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color.white.opacity(isDark ? 0.12 : 0.35),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.15 : 0.04), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius, paddingValue: padding))
    }
    
    // Мягкая натуральная тень без ядовитого свечения
    func ambientShadow(radius: CGFloat = 8, y: CGFloat = 4) -> some View {
        self.shadow(color: Color.black.opacity(0.12), radius: radius, x: 0, y: y)
    }
    
    func neonShadow(color: Color = .clear, radius: CGFloat = 8, x: CGFloat = 0, y: CGFloat = 4) -> some View {
        self.shadow(color: Color.black.opacity(0.08), radius: max(2, radius / 2), x: x, y: y / 2)
    }
}

// MARK: - SwiftUI Vector Glass Logo
struct SmartStockLogoView: View {
    @Environment(\.colorScheme) var colorScheme
    var size: CGFloat = 72
    
    var body: some View {
        let isDark = colorScheme == .dark
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .stroke(
                            Color.white.opacity(isDark ? 0.14 : 0.35),
                            lineWidth: 1.0
                        )
                )
                .shadow(color: Color.black.opacity(isDark ? 0.15 : 0.05), radius: 6, x: 0, y: 3)
            
            RotatingApertureView(size: size)
            
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.22, weight: .semibold))
                .foregroundStyle(Color(hex: "007AFF"))
                .offset(x: size * 0.16, y: -size * 0.16)
        }
    }
}

struct RotatingApertureView: View {
    var size: CGFloat
    @State private var rotateLogo = false
    
    var body: some View {
        Image(systemName: "camera.aperture")
            .font(.system(size: size * 0.46, weight: .light))
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
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - iOS View Modifiers & Clean Glass Borders
extension View {
    @ViewBuilder
    public func applyScrollTransitionIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1.0 : 0.85)
                    .scaleEffect(phase.isIdentity ? 1.0 : 0.97)
            }
        } else {
            self
        }
    }
    
    public func spatial3DTilt() -> some View {
        self.modifier(Spatial3DTiltModifier())
    }
    
    public func quantumNeonBorder(cornerRadius: CGFloat = 18) -> some View {
        self.modifier(LiquidGlassBorderModifier(cornerRadius: cornerRadius))
    }
    
    public func liquidGlassBorder(cornerRadius: CGFloat = 18) -> some View {
        self.modifier(LiquidGlassBorderModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - iOS 26 Spatial & Liquid Glass Modifiers
struct Spatial3DTiltModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .scrollTransition(.animated(.spring(response: 0.35, dampingFraction: 0.8))) { view, phase in
                    view
                        .scaleEffect(phase.isIdentity ? 1.0 : 0.97)
                        .rotation3DEffect(
                            .degrees(phase.value * -4.0),
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
                        Color.white.opacity(isDark ? 0.12 : 0.35),
                        lineWidth: 1.0
                    )
            )
    }
}
