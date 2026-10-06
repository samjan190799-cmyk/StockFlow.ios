import Foundation

/// Проверка полноты метаданных до отправки. Стоки отклоняют файлы без названия, с короткими описаниями
/// и слишком малым или большим числом ключевых слов, поэтому предупреждаем заранее (отправку это не блокирует).
enum MetadataCheck {
    static let minDescriptionWords = 5
    static let minKeywords = 7
    static let maxKeywords = 50

    /// Что не так с метаданными файла. Пусто, если всё в порядке.
    static func issues(for photo: PhotoMetadata) -> [String] {
        var result: [String] = []

        if photo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append("Нет названия")
        }

        let words = photo.description
            .split(whereSeparator: { $0.isWhitespace })
            .count
        if words < minDescriptionWords {
            result.append("Описание короче 5 слов")
        }

        let keywordCount = photo.keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        if keywordCount < minKeywords {
            result.append("Ключевых слов меньше 7")
        } else if keywordCount > maxKeywords {
            result.append("Ключевых слов больше 50")
        }

        if photo.categories.isEmpty {
            result.append("Не выбрана категория")
        }

        return result
    }

    /// Нужно ли показывать предупреждение на плитке: только для файлов, которые уже обработаны ИИ и готовы к отправке
    static func needsAttention(_ photo: PhotoMetadata) -> Bool {
        photo.status == .ready && !issues(for: photo).isEmpty
    }
}
