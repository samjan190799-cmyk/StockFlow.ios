import SwiftUI
import UIKit

// MARK: - Палитра нового экрана галереи
// Статус различается не только цветом: у каждого этапа свой значок и форма бейджа.
enum GalleryPalette {
    static let accent = Color(hex: "0A6CFF")
    static let accentLight = Color(hex: "6FB0FF")
    static let neutral = Color(hex: "A3A9BD")
    static let amber = Color(hex: "FFB020")
    static let teal = Color(hex: "2DD4BF")
    static let blue = Color(hex: "6FB0FF")
    static let violet = Color(hex: "B794FF")
    static let green = Color(hex: "34D399")
    static let coral = Color(hex: "FF7A7A")

    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "0A6CFF"), Color(hex: "5B5BFF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Зелёный для текста: на светлой теме берём темнее, чтобы хватало контраста.
    static func okText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? green : Color(hex: "15803D")
    }

    /// Красный для текста: на светлой теме берём темнее.
    static func badText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? coral : Color(hex: "B91C1C")
    }
}

// MARK: - Этапы конвейера «Новые → ИИ → Готовы → Очередь → Загружены»
enum GalleryStage: String, CaseIterable, Identifiable {
    case all
    case new
    case analyzing
    case ready
    case queue
    case done
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все".localized
        case .new: return "Новые".localized
        case .analyzing: return "ИИ-анализ".localized
        case .ready: return "Готовы".localized
        case .queue: return "В очереди".localized
        case .done: return "Загружены".localized
        case .failed: return "Ошибки".localized
        }
    }

    /// Цвет точки и сегмента ленты. У «Все» его нет.
    var color: Color? {
        switch self {
        case .all: return nil
        case .new: return GalleryPalette.neutral
        case .analyzing: return GalleryPalette.amber
        case .ready: return GalleryPalette.teal
        case .queue: return GalleryPalette.blue
        case .done: return GalleryPalette.green
        case .failed: return GalleryPalette.coral
        }
    }

    func includes(_ status: PhotoStatus) -> Bool {
        switch self {
        case .all: return true
        case .new: return status == .new
        case .analyzing: return status == .aiAnalyzing
        case .ready: return status == .ready
        case .queue: return status == .inQueue || status == .uploading
        case .done: return status == .success
        case .failed: return status == .error
        }
    }
}

// MARK: - Счётчики по этапам
struct GalleryCounts {
    private var byStage: [GalleryStage: Int] = [:]

    init(_ photos: [PhotoMetadata]) {
        for stage in GalleryStage.allCases {
            byStage[stage] = photos.filter { stage.includes($0.status) }.count
        }
    }

    func count(_ stage: GalleryStage) -> Int {
        byStage[stage] ?? 0
    }

    var total: Int {
        count(.all)
    }
}

// MARK: - Внешний вид статуса на плитке
extension PhotoStatus {
    var galleryColor: Color {
        switch self {
        case .new: return GalleryPalette.neutral
        case .aiAnalyzing: return GalleryPalette.amber
        case .ready: return GalleryPalette.teal
        case .inQueue: return GalleryPalette.blue
        case .uploading: return GalleryPalette.violet
        case .success: return GalleryPalette.green
        case .error: return GalleryPalette.coral
        }
    }

    var gallerySymbol: String {
        switch self {
        case .new: return "circle"
        case .aiAnalyzing: return "sparkles"
        case .ready: return "checkmark"
        case .inQueue: return "clock"
        case .uploading: return "arrow.up"
        case .success: return "checkmark"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
