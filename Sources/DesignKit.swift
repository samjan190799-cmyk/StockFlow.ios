import SwiftUI
import UIKit

// MARK: - Единый язык интерфейса
// Палитра и статусы живут в GalleryModel.swift (GalleryPalette). Здесь — строительные блоки
// для всех экранов: поверхность карточки, секции, строки настроек, поля, кнопки, плашки.

typealias AppPalette = GalleryPalette

// MARK: - Поверхность карточки

struct AppCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func appCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        modifier(AppCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Оттенки для статусов и плашек (с запасом контраста на светлой теме)

enum AppTone {
    case success
    case warning
    case danger
    case info
    case neutral

    func foreground(_ scheme: ColorScheme) -> Color {
        switch self {
        case .success: return scheme == .dark ? Color(hex: "34D399") : Color(hex: "15803D")
        case .warning: return scheme == .dark ? Color(hex: "FFB020") : Color(hex: "B45309")
        case .danger: return scheme == .dark ? Color(hex: "FF7A7A") : Color(hex: "B91C1C")
        case .info: return scheme == .dark ? Color(hex: "6FB0FF") : Color(hex: "1D4ED8")
        case .neutral: return Color.secondary
        }
    }

    var fill: Color {
        switch self {
        case .success: return Color(hex: "34D399").opacity(0.16)
        case .warning: return Color(hex: "FFB020").opacity(0.18)
        case .danger: return Color(hex: "FF7A7A").opacity(0.16)
        case .info: return Color(hex: "6FB0FF").opacity(0.18)
        case .neutral: return Color.primary.opacity(0.08)
        }
    }
}

// MARK: - Контейнер экрана: фон, прокрутка, читаемая ширина (на iPad не растягиваем)

struct AppScreen<Content: View>: View {
    private let maxWidth: CGFloat
    private let content: Content

    init(maxWidth: CGFloat = 720, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        ZStack {
            LiquidBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Секция: заголовок с иконкой, карточка с рядами, подпись снизу

struct AppSection<Content: View>: View {
    private let title: String?
    private let symbol: String?
    private let tint: Color
    private let footer: String?
    private let content: Content

    init(
        _ title: String? = nil,
        symbol: String? = nil,
        tint: Color = AppPalette.accent,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 8) {
                    if let symbol {
                        AppSymbolTile(symbol: symbol, tint: tint, size: 26)
                    }
                    Text(title)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(padding: 0)

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Иконка в цветной плитке

struct AppSymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(tint.opacity(0.16))
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Разделитель рядов внутри карточки

struct AppDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

// MARK: - Ряд-контейнер с единым отступом

struct AppRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}

// MARK: - Ряд с переключателем

struct AppToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var tint: Color = AppPalette.accent

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Ряд с выбором из списка (меню)

struct AppPickerRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
            Spacer(minLength: 8)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        HapticHelper.selection()
                        selection = option
                    } label: {
                        if option == selection {
                            Label(label(option), systemImage: "checkmark")
                        } else {
                            Text(label(option))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(label(selection))
                        .font(.body)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(AppPalette.accentLight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Подписанное текстовое поле

struct AppTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var monospaced: Bool = false
    var contentType: UITextContentType? = nil

    private var fieldFont: Font {
        monospaced ? Font.system(.subheadline, design: .monospaced) : Font.subheadline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(fieldFont)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        }
    }
}

// MARK: - Строка-ссылка или строка-действие (иконка, заголовок, подзаголовок, стрелка)

struct AppNavRowLabel: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var trailingSymbol: String = "chevron.right"

    var body: some View {
        HStack(spacing: 12) {
            AppSymbolTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: trailingSymbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Плашка статуса

struct AppChip: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    var symbol: String? = nil
    var tone: AppTone = .neutral

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tone.foreground(scheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(tone.fill))
    }
}

// MARK: - Стили кнопок

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppPalette.primaryGradient))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.bold))
            .foregroundStyle(AppTone.danger.foreground(scheme))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(AppTone.danger.fill))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

struct AppCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = AppPalette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(tint))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

extension ButtonStyle where Self == AppPrimaryButtonStyle {
    static var appPrimary: AppPrimaryButtonStyle { AppPrimaryButtonStyle() }
}

extension ButtonStyle where Self == AppSecondaryButtonStyle {
    static var appSecondary: AppSecondaryButtonStyle { AppSecondaryButtonStyle() }
}

extension ButtonStyle where Self == AppDestructiveButtonStyle {
    static var appDestructive: AppDestructiveButtonStyle { AppDestructiveButtonStyle() }
}

extension ButtonStyle where Self == AppCapsuleButtonStyle {
    static var appCapsule: AppCapsuleButtonStyle { AppCapsuleButtonStyle() }

    static func appCapsule(tint: Color) -> AppCapsuleButtonStyle {
        AppCapsuleButtonStyle(tint: tint)
    }
}

// MARK: - Шрифт фиксированного размера с учётом размера текста в настройках iOS (Dynamic Type)

struct ScaledFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        // Рост ограничен 1.6x, чтобы крупный текст не ломал плотные плашки
        let scaled = min(UIFontMetrics(forTextStyle: .body).scaledValue(for: size), size * 1.6)
        return content.font(.system(size: scaled, weight: weight))
    }
}

extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight))
    }
}
