import SwiftUI

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

// MARK: - Liquid Ambient Background (Fixed Layout)
struct LiquidBackgroundView: View {
    @State private var animateGlow = false
    
    var body: some View {
        ZStack {
            // Dark elegant base
            Color(.systemBackground)
            
            // Dynamic liquid-like animated blobs - Fixed sizes and bounds to prevent parent container layout shifts
            ZStack {
                // Violet blob top-left
                Circle()
                    .fill(Color(hex: "7C3AED").opacity(0.15))
                    .frame(width: 300, height: 300)
                    .scaleEffect(animateGlow ? 1.2 : 0.85)
                    .blur(radius: 80)
                    .offset(x: -80, y: -120)
                
                // Blue blob center-right
                Circle()
                    .fill(Color(hex: "2563EB").opacity(0.15))
                    .frame(width: 320, height: 320)
                    .scaleEffect(animateGlow ? 0.85 : 1.2)
                    .blur(radius: 90)
                    .offset(x: 100, y: -20)
                
                // Pink blob bottom-left
                Circle()
                    .fill(Color(hex: "DB2777").opacity(0.12))
                    .frame(width: 290, height: 290)
                    .scaleEffect(animateGlow ? 1.15 : 0.9)
                    .blur(radius: 85)
                    .offset(x: -60, y: 160)
            }
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Lock to screen bounds
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animateGlow.toggle()
            }
        }
    }
}

// MARK: - Glassmorphism View Modifier
struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var paddingValue: CGFloat
    
    func body(content: Content) -> some View {
        content
            .padding(paddingValue)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.04),
                                Color.black.opacity(0.02),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        self.modifier(GlassModifier(cornerRadius: cornerRadius, paddingValue: padding))
    }
}

// MARK: - SwiftUI Vector Liquid Glass Logo
struct SmartStockLogoView: View {
    var size: CGFloat = 72
    
    var body: some View {
        ZStack {
            // Background glow matching app theme
            Circle()
                .fill(AppleTheme.primaryGradient)
                .frame(width: size, height: size)
                .blur(radius: size * 0.15)
                .opacity(0.55)
            
            // Glass base panel
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1),
                                    Color.black.opacity(0.1),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: size * 0.08, x: 0, y: size * 0.04)
            
            // Aperture blades & Lens symbol
            Image(systemName: "camera.aperture")
                .font(.system(size: size * 0.46, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            
            // Central glass reflex / Sparkle
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.22, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: size * 0.15, y: -size * 0.15)
        }
    }
}
