import Foundation

// Модель жанра фильма
public struct Genre: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// Модель фильма
public struct Movie: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String // Название на русском
    public let originalTitle: String // Оригинальное название
    public let description: String // Описание сюжета
    public let rating: Double // Рейтинг (0.0 - 10.0)
    public let year: Int // Год выпуска
    public let duration: String // Продолжительность (например, "1 ч 54 мин")
    public let genres: [String] // Список жанров
    public let director: String // Режиссер
    public let actors: [String] // Актеры
    public let posterURL: String // Ссылка на постер
    public let videoURL: String // Ссылка на видеопоток (HLS m3u8 или MP4)
    public let isFeatured: Bool // Флаг для отображения на главном баннере
    
    public init(
        id: String,
        title: String,
        originalTitle: String,
        description: String,
        rating: Double,
        year: Int,
        duration: String,
        genres: [String],
        director: String,
        actors: [String],
        posterURL: String,
        videoURL: String,
        isFeatured: Bool = false
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.description = description
        self.rating = rating
        self.year = year
        self.duration = duration
        self.genres = genres
        self.director = director
        self.actors = actors
        self.posterURL = posterURL
        self.videoURL = videoURL
        self.isFeatured = isFeatured
    }
}
