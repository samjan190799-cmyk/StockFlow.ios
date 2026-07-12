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
    var isAnimated: Bool = false
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        return ZStack {
            if isAnimated {
                let bgColor = isDark ? Color(hex: "060608") : Color(hex: "F8F9FA")
                bgColor
                
                // Анимированные сферы (вынесены в отдельный View для изоляции 120 FPS анимации)
                AnimatedBlobsView(isDark: isDark)
                
                // Статическая сетка (никогда не перерисовывается, экономя CPU)
                let dotColor: Color = isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)
                StaticDotGridView(dotColor: dotColor)
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Вспомогательные оптимизированные подпредставления фона
struct AnimatedBlobsView: View {
    let isDark: Bool
    @State private var animateBlobs = false
    
    var body: some View {
        ZStack {
            if isDark {
                Circle()
                    .fill(Color(hex: "EC4899").opacity(0.06))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: animateBlobs ? 100 : -90, y: animateBlobs ? 90 : -110)
            } else {
                Circle()
                    .fill(Color(hex: "FBCFE8").opacity(0.04))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: animateBlobs ? 90 : -80, y: animateBlobs ? 80 : -100)
            }
        }
        .drawingGroup()
        .onAppear {
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                animateBlobs = true
            }
        }
    }
}

struct StaticDotGridView: View {
    let dotColor: Color
    
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let dotSize: CGFloat = 1.2
            let spacing: CGFloat = 18.0
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


// MARK: - Premium Neo-Minimalist Card Modifier
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
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.22 : 0.50),
                                Color.white.opacity(isDark ? 0.06 : 0.15),
                                Color.black.opacity(isDark ? 0.05 : 0.02),
                                Color.white.opacity(isDark ? 0.12 : 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.22 : 0.06), radius: 10, x: 0, y: 5)
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
// MARK: - SwiftUI Vector 3D Glass Logo
struct SmartStockLogoView: View {
    @Environment(\.colorScheme) var colorScheme
    var size: CGFloat = 72
    
    var body: some View {
        let isDark = colorScheme == .dark
        return ZStack {
            // Glass base panel (статичный размытый контейнер, не перерисовывается при вращении)
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.22 : 0.45),
                                    Color.white.opacity(isDark ? 0.06 : 0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: Color.black.opacity(isDark ? 0.20 : 0.06), radius: 8, x: 0, y: 4)
            
            // Анимированный вращающийся элемент (вынесен отдельно, чтобы не ререндерить ultraThinMaterial)
            RotatingApertureView(size: size)
            
            // Central Sparkle
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.24, weight: .semibold))
                .foregroundStyle(Color(hex: "F59E0B"))
                .offset(x: size * 0.16, y: -size * 0.16)
        }
    }
}

struct RotatingApertureView: View {
    var size: CGFloat
    @State private var rotateLogo = false
    
    var body: some View {
        Image(systemName: "camera.aperture")
            .font(.system(size: size * 0.48, weight: .light))
            .foregroundStyle(AppleTheme.primaryGradient)
            .rotationEffect(Angle(degrees: rotateLogo ? 360 : 0))
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

// MARK: - iOS Compatibility View Modifiers & Futuristic Effects
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
    
    public func spatial3DTilt() -> some View {
        self.modifier(Spatial3DTiltModifier())
    }
    
    public func quantumNeonBorder(cornerRadius: CGFloat = 18) -> some View {
        self.modifier(QuantumNeonBorderModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - iOS 26 Quantum & Spatial Modifiers
struct Spatial3DTiltModifier: ViewModifier {
    @State private var tiltAngleX: Double = 0.0
    @State private var tiltAngleY: Double = 0.0
    @State private var scale: CGFloat = 1.0
    @State private var size: CGSize = .zero
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(tiltAngleX), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(tiltAngleY), axis: (x: 0, y: 1, z: 0))
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            self.size = geo.size
                        }
                        .onChange(of: geo.size) { newSize in
                            self.size = newSize
                        }
                }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width = size.width > 0 ? size.width : 340.0
                        let height = size.height > 0 ? size.height : 220.0
                        
                        let dx = value.location.x - (width / 2)
                        let dy = value.location.y - (height / 2)
                        
                        let maxTilt: Double = 10.0
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                            scale = 0.97
                            tiltAngleY = Double(max(-1.0, min(1.0, dx / (width / 2)))) * maxTilt
                            tiltAngleX = -Double(max(-1.0, min(1.0, dy / (height / 2)))) * maxTilt
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                            scale = 1.0
                            tiltAngleX = 0.0
                            tiltAngleY = 0.0
                        }
                    }
            )
    }
}

struct QuantumNeonBorderModifier: ViewModifier {
    var cornerRadius: CGFloat
    @State private var animateGlow = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "4F46E5"),
                                Color(hex: "7C3AED"),
                                Color(hex: "EC4899"),
                                Color(hex: "4F46E5")
                            ],
                            startPoint: animateGlow ? .topLeading : .bottomTrailing,
                            endPoint: animateGlow ? .bottomTrailing : .topLeading
                        ),
                        lineWidth: 1.4
                    )
            )
            .shadow(
                color: Color(hex: "7C3AED").opacity(animateGlow ? 0.28 : 0.12),
                radius: animateGlow ? 10 : 5,
                x: 0,
                y: animateGlow ? 4 : 2
            )
            .onAppear {
                withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: true)) {
                    animateGlow = true
                }
            }
    }
}


