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

// MARK: - Liquid Ambient Background
struct LiquidBackgroundView: View {
    @State private var animateGlow = false
    
    var body: some View {
        ZStack {
            // Dark elegant base
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // Dynamic liquid-like animated blobs
            ZStack {
                // Violet blob top-left
                Circle()
                    .fill(Color(hex: "7C3AED").opacity(0.18))
                    .frame(width: animateGlow ? 360 : 300, height: animateGlow ? 360 : 300)
                    .blur(radius: 80)
                    .offset(x: animateGlow ? -50 : -90, y: animateGlow ? -40 : -100)
                
                // Blue blob center-right
                Circle()
                    .fill(Color(hex: "2563EB").opacity(0.18))
                    .frame(width: animateGlow ? 280 : 340, height: animateGlow ? 280 : 340)
                    .blur(radius: 90)
                    .offset(x: animateGlow ? 120 : 60, y: animateGlow ? -60 : 20)
                
                // Pink blob bottom-left
                Circle()
                    .fill(Color(hex: "DB2777").opacity(0.15))
                    .frame(width: 320, height: 320)
                    .blur(radius: 85)
                    .offset(x: animateGlow ? -80 : 20, y: animateGlow ? 180 : 120)
                
                // Cyan blob bottom-right
                Circle()
                    .fill(Color(hex: "06B6D4").opacity(0.12))
                    .frame(width: 300, height: 300)
                    .blur(radius: 90)
                    .offset(x: animateGlow ? 140 : 100, y: animateGlow ? 160 : 220)
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                    animateGlow.toggle()
                }
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
