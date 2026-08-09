import SwiftUI
import AuthenticationServices
import Combine
import Security
import CryptoKit

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
        guard !baseUrl.isEmpty else { return nil }
        let cleanBase = baseUrl.components(separatedBy: "=")[0]
        if isVideo {
            return URL(string: "\(cleanBase)=dv")
        } else {
            return URL(string: "\(cleanBase)=d")
        }
    }
    
    var thumbnailURL: URL? {
        if let productUrl = productUrl, productUrl.contains("http") && !productUrl.contains("drive.google.com") {
            return URL(string: productUrl)
        }
        guard !baseUrl.isEmpty else { return nil }
        
        if baseUrl.contains("drive.google.com") || baseUrl.contains("googleusercontent.com/drive") {
            if baseUrl.contains("?") || baseUrl.contains("=") {
                return URL(string: baseUrl)
            }
            return URL(string: "\(baseUrl)?sz=w400")
        }
        
        let cleanBase = baseUrl.components(separatedBy: "=")[0]
        guard !cleanBase.isEmpty else { return nil }
        return URL(string: "\(cleanBase)=w400-h400-c")
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
    
    private(set) var accessToken: String?
    private var webAuthContextProvider = WebAuthContextProvider()
    
    // Google OAuth 2.0 Configuration
    var clientID: String {
        let savedKey = UserDefaults.standard.string(forKey: "google_oauth_client_id") ?? ""
        let trimmed = savedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "1084227092144-stockflow.apps.googleusercontent.com" : trimmed
    }
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
        } else {
            Task {
                if await refreshAccessTokenIfNeeded() {
                    self.isAuthenticated = true
                    self.userEmail = UserDefaults.standard.string(forKey: "google_photos_user_email") ?? "Пользователь Google"
                    self.statusMessage = "Подключено к Google Фото".localized
                }
            }
        }
    }
    
    func signInWithGoogle() async {
        self.isLoading = true
        self.statusMessage = "Открытие окна авторизации Google...".localized
        
        let currentKey = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentKey.isEmpty, !currentKey.contains("stockflow.apps.googleusercontent.com") else {
            self.isLoading = false
            self.statusMessage = "Пожалуйста, введите ваш Google Client ID в параметрах системы.".localized
            return
        }
        
        let scopes = [
            "https://www.googleapis.com/auth/photoslibrary.readonly",
            "https://www.googleapis.com/auth/drive.readonly",
            "https://www.googleapis.com/auth/userinfo.email"
        ].joined(separator: " ")
        
        let callbackScheme: String
        let redirectURI: String
        if currentKey.contains(".apps.googleusercontent.com") {
            let keyPrefix = currentKey.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
            callbackScheme = "com.googleusercontent.apps.\(keyPrefix)"
            redirectURI = "\(callbackScheme):/oauth2redirect"
        } else {
            callbackScheme = redirectScheme
            redirectURI = "\(redirectScheme):/oauth2redirect"
        }
        
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        var urlComponents = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        urlComponents?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: currentKey),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = urlComponents?.url else {
            self.isLoading = false
            self.statusMessage = "Ошибка формирования URL авторизации".localized
            return
        }
        
        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { callbackURL, error in
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
            
            var obtainedToken: String? = nil
            
            // 1. Проверяем наличие 'code' в query параметрах (Authorization Code Flow with PKCE)
            if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let code = queryItems.first(where: { $0.name == "code" })?.value {
                self.statusMessage = "Обмен кода авторизации...".localized
                obtainedToken = try await exchangeCodeForToken(code: code, clientID: currentKey, redirectURI: redirectURI, codeVerifier: codeVerifier)
            }
            // 2. Резервный вариант: парсим 'access_token' из фрагмента (#access_token=...)
            else if let fragment = callbackURL.fragment, let token = extractQueryParam("access_token", from: fragment) {
                obtainedToken = token
            }
            
            if let token = obtainedToken, !token.isEmpty {
                self.accessToken = token
                KeychainHelper.shared.save(password: token, for: "com.stockflow.googlephotos")
                self.isAuthenticated = true
                self.statusMessage = "Успешная авторизация в Google".localized
                
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
    
    private func exchangeCodeForToken(code: String, clientID: String, redirectURI: String, codeVerifier: String) async throws -> String {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyComponents = [
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)",
            "grant_type=authorization_code",
            "code_verifier=\(codeVerifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? codeVerifier)"
        ]
        request.httpBody = bodyComponents.joined(separator: "&").data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let refresh_token: String?
        }
        
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let refreshToken = decoded.refresh_token, !refreshToken.isEmpty {
            KeychainHelper.shared.save(password: refreshToken, for: "com.stockflow.googlephotos.refresh")
        }
        return decoded.access_token
    }
    
    func refreshAccessTokenIfNeeded() async -> Bool {
        guard let refreshToken = KeychainHelper.shared.read(for: "com.stockflow.googlephotos.refresh"),
              !refreshToken.isEmpty else {
            return false
        }
        
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            return false
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let currentKey = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyComponents = [
            "client_id=\(currentKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? currentKey)",
            "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)",
            "grant_type=refresh_token"
        ]
        request.httpBody = bodyComponents.joined(separator: "&").data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            
            struct RefreshResponse: Codable {
                let access_token: String
            }
            
            let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
            self.accessToken = decoded.access_token
            KeychainHelper.shared.save(password: decoded.access_token, for: "com.stockflow.googlephotos")
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - PKCE Helpers
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
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
        self.statusMessage = "Загрузка всех медиафайлов из Google Фото и Диска...".localized
        
        var fetchedItems: [GoogleMediaItem] = []
        var pageCount = 0
        let maxPages = 50 // До 5000+ объектов
        
        // 1. Циклическая загрузка из Google Photos API (по nextPageToken)
        var photosPageToken: String? = nil
        repeat {
            pageCount += 1
            var components = URLComponents(string: "https://photoslibrary.googleapis.com/v1/mediaItems")
            var queryItems = [URLQueryItem(name: "pageSize", value: "100")]
            if let pageToken = photosPageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components?.queryItems = queryItems
            
            guard let photosURL = components?.url else { break }
            
            var request = URLRequest(url: photosURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResp = response as? HTTPURLResponse {
                if httpResp.statusCode == 401 {
                    if await refreshAccessTokenIfNeeded(), let newToken = accessToken {
                        var retryReq = URLRequest(url: photosURL)
                        retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        if let (retryData, retryResp) = try? await URLSession.shared.data(for: retryReq),
                           (retryResp as? HTTPURLResponse)?.statusCode == 200 {
                            struct GooglePhotosListResponse: Codable {
                                let mediaItems: [GoogleMediaItem]?
                                let nextPageToken: String?
                            }
                            if let result = try? JSONDecoder().decode(GooglePhotosListResponse.self, from: retryData) {
                                if let items = result.mediaItems {
                                    fetchedItems.append(contentsOf: items)
                                }
                                photosPageToken = result.nextPageToken
                            } else {
                                photosPageToken = nil
                            }
                        } else {
                            photosPageToken = nil
                        }
                    } else {
                        photosPageToken = nil
                    }
                } else if httpResp.statusCode == 200 {
                    struct GooglePhotosListResponse: Codable {
                        let mediaItems: [GoogleMediaItem]?
                        let nextPageToken: String?
                    }
                    if let result = try? JSONDecoder().decode(GooglePhotosListResponse.self, from: data) {
                        if let items = result.mediaItems {
                            fetchedItems.append(contentsOf: items)
                        }
                        photosPageToken = result.nextPageToken
                    } else {
                        photosPageToken = nil
                    }
                } else {
                    photosPageToken = nil
                }
            } else {
                photosPageToken = nil
            }
            
            self.statusMessage = "Загрузка Google Фото... Найдено: \(fetchedItems.count)".localized
        } while photosPageToken != nil && pageCount < maxPages
        
        // 2. Циклическая загрузка из Google Drive API (по nextPageToken)
        var drivePageToken: String? = nil
        let driveQuery = "(mimeType contains 'image/' or mimeType contains 'video/') and trashed = false"
        
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")
            var queryItems = [
                URLQueryItem(name: "q", value: driveQuery),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,thumbnailLink,webContentLink)")
            ]
            if let pageToken = drivePageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components?.queryItems = queryItems
            
            guard let driveURL = components?.url else { break }
            
            var request = URLRequest(url: driveURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResp = response as? HTTPURLResponse {
                if httpResp.statusCode == 401 {
                    if await refreshAccessTokenIfNeeded(), let newToken = accessToken {
                        var retryReq = URLRequest(url: driveURL)
                        retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        if let (retryData, retryResp) = try? await URLSession.shared.data(for: retryReq),
                           (retryResp as? HTTPURLResponse)?.statusCode == 200 {
                            struct DriveFile: Codable {
                                let id: String
                                let name: String
                                let mimeType: String
                                let thumbnailLink: String?
                                let webContentLink: String?
                            }
                            struct DriveListResponse: Codable {
                                let files: [DriveFile]?
                                let nextPageToken: String?
                            }
                            if let driveResult = try? JSONDecoder().decode(DriveListResponse.self, from: retryData) {
                                if let files = driveResult.files {
                                    for file in files {
                                        if !fetchedItems.contains(where: { $0.id == file.id }) {
                                            let item = GoogleMediaItem(
                                                id: file.id,
                                                filename: file.name,
                                                mimeType: file.mimeType,
                                                baseUrl: file.webContentLink ?? file.thumbnailLink ?? "",
                                                productUrl: file.thumbnailLink,
                                                mediaMetadata: nil
                                            )
                                            fetchedItems.append(item)
                                        }
                                    }
                                }
                                drivePageToken = driveResult.nextPageToken
                            } else {
                                drivePageToken = nil
                            }
                        } else {
                            drivePageToken = nil
                        }
                    } else {
                        drivePageToken = nil
                    }
                } else if httpResp.statusCode == 200 {
                    struct DriveFile: Codable {
                        let id: String
                        let name: String
                        let mimeType: String
                        let thumbnailLink: String?
                        let webContentLink: String?
                    }
                    struct DriveListResponse: Codable {
                        let files: [DriveFile]?
                        let nextPageToken: String?
                    }
                    
                    if let driveResult = try? JSONDecoder().decode(DriveListResponse.self, from: data) {
                        if let files = driveResult.files {
                            for file in files {
                                if !fetchedItems.contains(where: { $0.id == file.id }) {
                                    let item = GoogleMediaItem(
                                        id: file.id,
                                        filename: file.name,
                                        mimeType: file.mimeType,
                                        baseUrl: file.webContentLink ?? file.thumbnailLink ?? "",
                                        productUrl: file.thumbnailLink,
                                        mediaMetadata: nil
                                    )
                                    fetchedItems.append(item)
                                }
                            }
                        }
                        drivePageToken = driveResult.nextPageToken
                    } else {
                        drivePageToken = nil
                    }
                } else {
                    drivePageToken = nil
                }
            } else {
                drivePageToken = nil
            }
            
            self.statusMessage = "Поиск медиафайлов... Загружено: \(fetchedItems.count)".localized
        } while drivePageToken != nil
        
        if filterVideoOnly {
            self.mediaItems = fetchedItems.filter { $0.isVideo }
        } else {
            self.mediaItems = fetchedItems
        }
        
        if self.mediaItems.isEmpty {
            self.statusMessage = "Файлов не найдено. Проверьте, включен ли Photos/Drive API в Google Cloud.".localized
        } else {
            self.statusMessage = "Найдено медиафайлов: \(self.mediaItems.count)".localized
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
        
        var (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 401 {
            if await refreshAccessTokenIfNeeded(), let newToken = accessToken {
                request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                data = retryData
                response = retryResponse
            }
        }
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        self.downloadProgress[item.id] = 1.0
        return data
    }
}

