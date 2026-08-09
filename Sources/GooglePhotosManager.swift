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
            return URL(string: "\(baseUrl)=dv")
        } else {
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

// MARK: - OAuth Web Session Context Provider
final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if Thread.isMainThread {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return ASPresentationAnchor()
    }
}

/// Сервис управления авторизацией и загрузкой медиа из Google Photos / Drive (Swift Concurrency, ObservableObject)
@MainActor
final class GooglePhotosManager: ObservableObject {
    static let shared = GooglePhotosManager()
    
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var mediaItems: [GoogleMediaItem] = []
    @Published var statusMessage: String = ""
    @Published var downloadProgress: [String: Double] = [:]
    @Published var userEmail: String = ""
    
    private var accessToken: String?
    private var webAuthContextProvider = WebAuthContextProvider()
    
    // Google OAuth 2.0 Configuration
    private let clientID = "1084227092144-stockflow.apps.googleusercontent.com"
    private let redirectScheme = "com.samvel.smartstock"
    
    init() {
        checkExistingToken()
    }
    
    // MARK: - Auth & Keychain
    
    private func checkExistingToken() {
        if let token = KeychainHelper.shared.read(for: "com.stockflow.googlephotos"),
           !token.isEmpty {
            self.accessToken = token
            self.isAuthenticated = true
            self.userEmail = UserDefaults.standard.string(forKey: "google_photos_user_email") ?? "Пользователь Google"
            self.statusMessage = "Подключено к Google Фото".localized
        }
    }
    
    func signInWithGoogle() async {
        self.isLoading = true
        self.statusMessage = "Открытие окна авторизации Google...".localized
        
        let scopes = [
            "https://www.googleapis.com/auth/photoslibrary.readonly",
            "https://www.googleapis.com/auth/userinfo.email"
        ].joined(separator: " ")
        
        let redirectURI = "\(redirectScheme):/oauth2redirect"
        guard let encodedRedirect = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedScope = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?response_type=token&client_id=\(clientID)&redirect_uri=\(encodedRedirect)&scope=\(encodedScope)") else {
            self.isLoading = false
            self.statusMessage = "Ошибка формирования URL авторизации".localized
            return
        }
        
        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectScheme) { callbackURL, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let callbackURL = callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                session.presentationContextProvider = self.webAuthContextProvider
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }
            
            // Парсим access_token из фрагмента редиректа (#access_token=...)
            if let fragment = callbackURL.fragment, let token = extractQueryParam("access_token", from: fragment) {
                self.accessToken = token
                KeychainHelper.shared.save(password: token, for: "com.stockflow.googlephotos")
                self.isAuthenticated = true
                self.statusMessage = "Успешная авторизация в Google".localized
                
                // Получаем email пользователя из Google API
                await fetchUserProfile()
                await loadMediaItems()
            } else {
                throw URLError(.cannotParseResponse)
            }
        } catch {
            self.statusMessage = "Авторизация отменена или завершилась ошибкой: \(error.localizedDescription)".localized
        }
        
        self.isLoading = false
    }
    
    private func extractQueryParam(_ param: String, from string: String) -> String? {
        let pairs = string.components(separatedBy: "&")
        for pair in pairs {
            let keyVal = pair.components(separatedBy: "=")
            if keyVal.count == 2, keyVal[0] == param {
                return keyVal[1].removingPercentEncoding
            }
        }
        return nil
    }
    
    private func fetchUserProfile() async {
        guard let token = accessToken,
              let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                self.userEmail = email
                UserDefaults.standard.set(email, forKey: "google_photos_user_email")
            }
        } catch {
            print("Failed to fetch Google profile: \(error)")
        }
    }
    
    func signOut() {
        KeychainHelper.shared.delete(for: "com.stockflow.googlephotos")
        UserDefaults.standard.removeObject(forKey: "google_photos_user_email")
        self.accessToken = nil
        self.userEmail = ""
        self.isAuthenticated = false
        self.mediaItems = []
        self.statusMessage = "Отключено от Google Фото".localized
    }
    
    // MARK: - Fetching Media from Google API
    
    func loadMediaItems(filterVideoOnly: Bool = false) async {
        guard isAuthenticated, let token = accessToken else { return }
        
        self.isLoading = true
        self.statusMessage = "Загрузка медиафайлов из Google Фото...".localized
        
        guard let url = URL(string: "https://photoslibrary.googleapis.com/v1/mediaItems?pageSize=100") else {
            self.isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                // Если с токеном проблема — пробуем обновить авторизацию
                if (response as? HTTPURLResponse)?.statusCode == 401 {
                    self.statusMessage = "Сессия истекла. Войдите заново.".localized
                    signOut()
                }
                self.isLoading = false
                return
            }
            
            struct GooglePhotosListResponse: Codable {
                let mediaItems: [GoogleMediaItem]?
            }
            
            let result = try JSONDecoder().decode(GooglePhotosListResponse.self, from: data)
            let items = result.mediaItems ?? []
            
            if filterVideoOnly {
                self.mediaItems = items.filter { $0.isVideo }
            } else {
                self.mediaItems = items
            }
            self.statusMessage = "Загружено элементов: \(self.mediaItems.count)".localized
        } catch {
            self.statusMessage = "Ошибка получения медиафайлов: \(error.localizedDescription)".localized
        }
        
        self.isLoading = false
    }
    
    // MARK: - Download Media
    
    /// Скачивает реальный медиафайл из Google Photos по URL
    func downloadItemData(_ item: GoogleMediaItem) async throws -> Data {
        guard let url = item.downloadURL ?? URL(string: item.baseUrl) else {
            throw URLError(.badURL)
        }
        
        self.downloadProgress[item.id] = 0.2
        
        var request = URLRequest(url: url)
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        self.downloadProgress[item.id] = 1.0
        return data
    }
}

