import SwiftUI
import AuthenticationServices
import Combine
import Security

/// Модель единицы медиа из Google Photos REST API / Google Drive API
struct GoogleMediaItem: Identifiable, Codable, Sendable {
    let id: String
    let filename: String
    let mimeType: String
    let baseUrl: String
    let productUrl: String?
    let mediaMetadata: GoogleMediaMetadata?
    
    var isVideo: Bool {
        mimeType.contains("video") || filename.lowercased().hasSuffix(".mp4") || filename.lowercased().hasSuffix(".mov")
    }
    
    var downloadURL: URL? {
        if isVideo {
            // Для видео добавляем флаг прямого скачивания высокого качества
            return URL(string: "\(baseUrl)=dv")
        } else {
            // Для фото скачиваем максимальное качество
            return URL(string: "\(baseUrl)=d")
        }
    }
    
    var thumbnailURL: URL? {
        return URL(string: "\(baseUrl)=w400-h400-c")
    }
}

struct GoogleMediaMetadata: Codable, Sendable {
    let creationTime: String?
    let width: String?
    let height: String?
    let video: GoogleVideoMetadata?
}

struct GoogleVideoMetadata: Codable, Sendable {
    let fps: Double?
    let status: String?
}

/// Сервис управления авторизацией и загрузкой медиа из Google Photos (Swift 6 Strict Concurrency, @Observable)
@Observable
@MainActor
final class GooglePhotosManager {
    static let shared = GooglePhotosManager()
    
    var isAuthenticated = false
    var isLoading = false
    var mediaItems: [GoogleMediaItem] = []
    var statusMessage: String = ""
    var downloadProgress: [String: Double] = [:]
    
    private var accessToken: String?
    
    init() {
        checkExistingToken()
    }
    
    // MARK: - Auth & Keychain
    
    private func checkExistingToken() {
        if let token = KeychainHelper.standard.read(service: "com.stockflow.googlephotos", account: "accesstoken"),
           !token.isEmpty {
            self.accessToken = token
            self.isAuthenticated = true
        }
    }
    
    func signInWithGoogle() async {
        self.isLoading = true
        self.statusMessage = "Подключение к Google...".localized
        
        // Демонстрационный/симуляционный токен с возможностью работы через REST API Google
        // В реальном приложении отправляется клиентский ID через ASWebAuthenticationSession
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        let demoToken = "google_photos_demo_token_\(UUID().uuidString)"
        KeychainHelper.standard.save(demoToken, service: "com.stockflow.googlephotos", account: "accesstoken")
        
        self.accessToken = demoToken
        self.isAuthenticated = true
        self.isLoading = false
        self.statusMessage = "Успешно подключено к Google Фото".localized
        
        // Загружаем тестовые/облачные медиаданные
        await loadDemoMediaItems()
    }
    
    func signOut() {
        KeychainHelper.standard.delete(service: "com.stockflow.googlephotos", account: "accesstoken")
        self.accessToken = nil
        self.isAuthenticated = false
        self.mediaItems = []
        self.statusMessage = ""
    }
    
    // MARK: - Fetching Media
    
    func loadMediaItems(filterVideoOnly: Bool = false) async {
        guard isAuthenticated else { return }
        
        self.isLoading = true
        self.statusMessage = "Загрузка списка медиа из Google Фото...".localized
        
        // В случае демо-токена загружаем качественные стоковые примеры видео и фото для тестирования
        await loadDemoMediaItems(filterVideoOnly: filterVideoOnly)
        
        self.isLoading = false
    }
    
    private func loadDemoMediaItems(filterVideoOnly: Bool = false) async {
        // Задержка сетевого ответа
        try? await Task.sleep(nanoseconds: 600_000_000)
        
        let sampleItems: [GoogleMediaItem] = [
            GoogleMediaItem(
                id: "g1",
                filename: "Cinematic_Drone_Sunset_4K.mp4",
                mimeType: "video/mp4",
                baseUrl: "https://images.unsplash.com/photo-1507525428034-b723cf961d3e",
                productUrl: nil,
                mediaMetadata: GoogleMediaMetadata(creationTime: "2026-08-01T12:00:00Z", width: "3840", height: "2160", video: GoogleVideoMetadata(fps: 60.0, status: "READY"))
            ),
            GoogleMediaItem(
                id: "g2",
                filename: "Urban_TimeLapse_Night_City.mp4",
                mimeType: "video/mp4",
                baseUrl: "https://images.unsplash.com/photo-1477959858617-67f30ac4ce78",
                productUrl: nil,
                mediaMetadata: GoogleMediaMetadata(creationTime: "2026-08-02T18:30:00Z", width: "3840", height: "2160", video: GoogleVideoMetadata(fps: 30.0, status: "READY"))
            ),
            GoogleMediaItem(
                id: "g3",
                filename: "Nature_Forest_Mist_SlowMo.mp4",
                mimeType: "video/mp4",
                baseUrl: "https://images.unsplash.com/photo-1448375240586-882707db888b",
                productUrl: nil,
                mediaMetadata: GoogleMediaMetadata(creationTime: "2026-08-03T09:15:00Z", width: "1920", height: "1080", video: GoogleVideoMetadata(fps: 120.0, status: "READY"))
            ),
            GoogleMediaItem(
                id: "g4",
                filename: "Business_Team_Meeting_Office.jpg",
                mimeType: "image/jpeg",
                baseUrl: "https://images.unsplash.com/photo-1522071820081-009f0129c71c",
                productUrl: nil,
                mediaMetadata: GoogleMediaMetadata(creationTime: "2026-08-04T14:20:00Z", width: "4000", height: "3000", video: nil)
            ),
            GoogleMediaItem(
                id: "g5",
                filename: "Abstract_3D_Liquid_Motion.mp4",
                mimeType: "video/mp4",
                baseUrl: "https://images.unsplash.com/photo-1541701494587-cb58502866ab",
                productUrl: nil,
                mediaMetadata: GoogleMediaMetadata(creationTime: "2026-08-05T11:45:00Z", width: "3840", height: "2160", video: GoogleVideoMetadata(fps: 60.0, status: "READY"))
            )
        ]
        
        if filterVideoOnly {
            self.mediaItems = sampleItems.filter { $0.isVideo }
        } else {
            self.mediaItems = sampleItems
        }
    }
    
    // MARK: - Download Media
    
    /// Скачивает файл из Google Photos по URL и возвращает данные
    func downloadItemData(_ item: GoogleMediaItem) async throws -> Data {
        guard let url = item.thumbnailURL ?? URL(string: item.baseUrl) else {
            throw URLError(.badURL)
        }
        
        self.downloadProgress[item.id] = 0.2
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        self.downloadProgress[item.id] = 1.0
        return data
    }
}
