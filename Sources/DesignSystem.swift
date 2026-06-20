import SwiftUI
import UIKit


// MARK: - Premium Color Palette
struct AppleTheme {
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "4F46E5"), Color(hex: "7C3AED"), Color(hex: "EC4899")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let glassBorder = Color.white.opacity(0.18)
    static let glassBorderDark = Color.white.opacity(0.10)
    
    static let glowStart = Color(hex: "6366F1")
    static let glowEnd = Color(hex: "A855F7")
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

// MARK: - Liquid Ambient Background (Fixed Layout with Drifting Blobs & Grid Texture)
struct LiquidBackgroundView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var animateGlow = false
    @State private var driftOffset1 = CGSize.zero
    @State private var driftOffset2 = CGSize.zero
    @State private var driftOffset3 = CGSize.zero
    @State private var driftOffset4 = CGSize.zero
    
    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            // Dark elegant base
            Color(.systemBackground)
            
            // Dynamic liquid-like animated blobs
            ZStack {
                // Violet blob top-left
                Circle()
                    .fill(Color(hex: "7C3AED").opacity(isDark ? 0.16 : 0.08))
                    .frame(width: 320, height: 320)
                    .scaleEffect(animateGlow ? 1.25 : 0.85)
                    .blur(radius: 80)
                    .offset(x: -90 + driftOffset1.width, y: -130 + driftOffset1.height)
                
                // Blue blob center-right
                Circle()
                    .fill(Color(hex: "2563EB").opacity(isDark ? 0.16 : 0.08))
                    .frame(width: 340, height: 340)
                    .scaleEffect(animateGlow ? 0.85 : 1.2)
                    .blur(radius: 90)
                    .offset(x: 110 + driftOffset2.width, y: -30 + driftOffset2.height)
                
                // Pink blob bottom-left
                Circle()
                    .fill(Color(hex: "DB2777").opacity(isDark ? 0.14 : 0.07))
                    .frame(width: 300, height: 300)
                    .scaleEffect(animateGlow ? 1.15 : 0.9)
                    .blur(radius: 85)
                    .offset(x: -70 + driftOffset3.width, y: 170 + driftOffset3.height)
                
                // Amber blob bottom-right (New 4th blob for richer ambient)
                Circle()
                    .fill(Color(hex: "F59E0B").opacity(isDark ? 0.09 : 0.05))
                    .frame(width: 280, height: 280)
                    .scaleEffect(animateGlow ? 0.9 : 1.15)
                    .blur(radius: 75)
                    .offset(x: 80 + driftOffset4.width, y: 200 + driftOffset4.height)
            }
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Retro dot-grid texture overlay for premium cinematic feel
            Canvas { context, size in
                let dotSize: CGFloat = 1.2
                let spacing: CGFloat = 18.0
                let dotColor = isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)
                for x in stride(from: 0, to: size.width, by: spacing) {
                    for y in stride(from: 0, to: size.height, by: spacing) {
                        context.fill(Path(CGRect(x: x, y: y, width: dotSize, height: dotSize)), with: .color(dotColor))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animateGlow.toggle()
            }
            withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                driftOffset1 = CGSize(width: 40, height: -30)
            }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                driftOffset2 = CGSize(width: -50, height: 40)
            }
            withAnimation(.easeInOut(duration: 13).repeatForever(autoreverses: true)) {
                driftOffset3 = CGSize(width: 30, height: -40)
            }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                driftOffset4 = CGSize(width: -35, height: -25)
            }
        }
    }
}


// MARK: - Glassmorphism 2.0 View Modifier
struct GlassModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var cornerRadius: CGFloat
    var paddingValue: CGFloat
    
    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .padding(paddingValue)
            .background(
                ZStack {
                    // Soft glass tint base
                    if isDark {
                        Color.black.opacity(0.22)
                    } else {
                        Color.white.opacity(0.45)
                    }
                    // System frosted blur
                    Rectangle().fill(.ultraThinMaterial)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isDark ? [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.06),
                                Color.black.opacity(0.04),
                                Color.white.opacity(0.16)
                            ] : [
                                Color.white.opacity(0.65),
                                Color.white.opacity(0.25),
                                Color.black.opacity(0.08),
                                Color.white.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: isDark ? Color.black.opacity(0.12) : Color.gray.opacity(0.12), radius: 14, x: 0, y: 7)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius, paddingValue: padding))
    }
    
    // Custom Multi-layered Neon Shadow for 3D glow effect
    func neonShadow(color: Color, radius: CGFloat = 8, x: CGFloat = 0, y: CGFloat = 4) -> some View {
        self
            .shadow(color: color.opacity(0.22), radius: radius, x: x, y: y)
            .shadow(color: color.opacity(0.12), radius: radius / 2, x: x, y: y / 2)
    }
}

// MARK: - SwiftUI Vector 3D Glass Logo
struct SmartStockLogoView: View {
    var size: CGFloat = 72
    @State private var rotateLogo = false
    
    var body: some View {
        ZStack {
            // Background glow matching app theme
            Circle()
                .fill(AppleTheme.primaryGradient)
                .frame(width: size * 1.1, height: size * 1.1)
                .blur(radius: size * 0.2)
                .opacity(0.45)
            
            // Glass base panel with double-layered frosted borders
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.white.opacity(0.12),
                                    Color.black.opacity(0.15),
                                    Color.white.opacity(0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.black.opacity(0.18), radius: size * 0.1, x: 0, y: size * 0.05)
            
            // Aperture blades & Lens symbol with soft shadow
            Image(systemName: "camera.aperture")
                .font(.system(size: size * 0.48, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(Angle(degrees: rotateLogo ? 360 : 0))
                .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
            
            // Central glass reflex / Sparkle
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.24, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "F59E0B"), .white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .neonShadow(color: Color(hex: "F59E0B"), radius: 4)
                .offset(x: size * 0.16, y: -size * 0.16)
        }
        .onAppear {
            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                rotateLogo = true
            }
        }
    }
}

// MARK: - Safe Sendable Binding Wrapper for Strict Concurrency
struct SendableBinding<Value>: @unchecked Sendable {
    let binding: Binding<Value>
}

// MARK: - Premium Tactile Haptic Helper
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
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - iOS Compatibility View Modifiers
extension View {
    @ViewBuilder
    public func applyScrollTransitionIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1.0 : 0.8)
                    .scaleEffect(phase.isIdentity ? 1.0 : 0.95)
            }
        } else {
            self
        }
    }
}


