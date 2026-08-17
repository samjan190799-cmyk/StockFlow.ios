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
    /// Время получения baseUrl — для инвалидации (Google Photos baseUrl живёт 60 мин)
    let fetchedAt: Date

    var isVideo: Bool {
        let fn = filename.lowercased()
        let mt = mimeType.lowercased()
        return mt.contains("video") || fn.hasSuffix(".mp4") || fn.hasSuffix(".mov") || fn.hasSuffix(".m4v") || fn.hasSuffix(".avi")
    }

    /// Реальное расширение файла (из filename), для видео — mp4/mov/m4v/avi
    var fileExtension: String {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext.isEmpty {
            return isVideo ? "mp4" : "jpg"
        }
        return ext
    }

    /// Признак того, что baseUrl устарел (> 55 минут)
    var isBaseUrlStale: Bool {
        Date().timeIntervalSince(fetchedAt) > 55 * 60
    }

    var downloadURL: URL? {
        guard !baseUrl.isEmpty else { return nil }
        // Для Drive-файлов webContentLink уже является прямой ссылкой скачивания
        if baseUrl.contains("drive.google.com") || baseUrl.contains("content.googleapis.com") {
            return URL(string: baseUrl)
        }
        let cleanBase = baseUrl.components(separatedBy: "=")[0]
        if isVideo {
            return URL(string: "\(cleanBase)=dv")
        } else {
            return URL(string: "\(cleanBase)=d")
        }
    }

    var thumbnailURL: URL? {
        // Drive: thumbnailLink уже является миниатюрой, доступной с авторизацией
        if let productUrl = productUrl, productUrl.contains("http") {
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

    enum CodingKeys: String, CodingKey {
        case id, filename, mimeType, baseUrl, productUrl, mediaMetadata, fetchedAt
    }

    init(id: String, filename: String, mimeType: String, baseUrl: String, productUrl: String?, mediaMetadata: GoogleMediaMetadata?, fetchedAt: Date = Date()) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.baseUrl = baseUrl
        self.productUrl = productUrl
        self.mediaMetadata = mediaMetadata
        self.fetchedAt = fetchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.filename = (try? container.decode(String.self, forKey: .filename)) ?? "photo.jpg"
        self.mimeType = (try? container.decode(String.self, forKey: .mimeType)) ?? "image/jpeg"
        self.baseUrl = (try? container.decode(String.self, forKey: .baseUrl)) ?? ""
        self.productUrl = try? container.decode(String.self, forKey: .productUrl)
        self.mediaMetadata = try? container.decode(GoogleMediaMetadata.self, forKey: .mediaMetadata)
        self.fetchedAt = (try? container.decode(Date.self, forKey: .fetchedAt)) ?? Date()
    }
}

struct GoogleMediaMetadata: Codable, Sendable {
    let creationTime: String?
    let width: String?
    let height: String?

    enum CodingKeys: String, CodingKey {
        case creationTime, width, height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.creationTime = try? container.decode(String.self, forKey: .creationTime)

        if let wStr = try? container.decode(String.self, forKey: .width) {
            self.width = wStr
        } else if let wInt = try? container.decode(Int.self, forKey: .width) {
            self.width = String(wInt)
        } else {
            self.width = nil
        }

        if let hStr = try? container.decode(String.self, forKey: .height) {
            self.height = hStr
        } else if let hInt = try? container.decode(Int.self, forKey: .height) {
            self.height = String(hInt)
        } else {
            self.height = nil
        }
    }
}

// MARK: - OAuth Web Session Context Provider
final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                    return keyWindow
                }
                if let firstWindow = windowScene.windows.first {
                    return firstWindow
                }
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
        return savedKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
                } else {
                    self.isAuthenticated = false
                }
            }
        }
    }

    func signInWithGoogle() async {
        self.isLoading = true
        self.statusMessage = "Открытие окна авторизации Google...".localized

        let currentKey = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentKey.isEmpty else {
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
            URLQueryItem(name: "prompt", value: "consent select_account")
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
                session.prefersEphemeralWebBrowserSession = true
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
                await loadMediaItems(forceReload: true)
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
        KeychainHelper.shared.delete(for: "com.stockflow.googlephotos.refresh")
        UserDefaults.standard.removeObject(forKey: "google_photos_user_email")
        self.accessToken = nil
        self.userEmail = ""
        self.isAuthenticated = false
        self.mediaItems = []
        self.statusMessage = "Отключено от Google Фото".localized
        // Очищаем кеш миниатюр при выходе
        GoogleImageCache.clearAll()
    }

    // MARK: - Fetching Media from Google API

    /// Загружает список медиафайлов.
    /// - Parameters:
    ///   - forceReload: если `false` и список уже загружен — возвращается без запросов к API.
    ///   - filterVideoOnly: фильтровать только видео.
    func loadMediaItems(forceReload: Bool = false, filterVideoOnly: Bool = false) async {
        guard isAuthenticated, let token = accessToken else { return }

        // Если список уже загружен и обновление не требуется — не нагружаем API
        if !forceReload && !mediaItems.isEmpty {
            return
        }

        self.isLoading = true
        self.statusMessage = "Загрузка всех медиафайлов из Google Фото и Диска...".localized

        var fetchedItems: [GoogleMediaItem] = []
        var pageCount = 0
        let maxPages = 200 // До 20 000 объектов (200 страниц × 100)
        let now = Date()

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
                            parsePhotosResponse(retryData, into: &fetchedItems, pageToken: &photosPageToken, fetchedAt: now)
                        } else {
                            photosPageToken = nil
                        }
                    } else {
                        photosPageToken = nil
                    }
                } else if httpResp.statusCode == 200 {
                    parsePhotosResponse(data, into: &fetchedItems, pageToken: &photosPageToken, fetchedAt: now)
                } else {
                    photosPageToken = nil
                }
            } else {
                photosPageToken = nil
            }

            self.statusMessage = "Загрузка Google Фото... Найдено: \(fetchedItems.count)"

        } while photosPageToken != nil && pageCount < maxPages

        // 2. Циклическая загрузка из Google Drive API (по nextPageToken)
        let currentToken = accessToken ?? token
        var drivePageToken: String? = nil
        let driveQuery = "(mimeType contains 'image/' or mimeType contains 'video/' or name contains '.jpg' or name contains '.jpeg' or name contains '.png' or name contains '.heic' or name contains '.heif' or name contains '.dng' or name contains '.webp' or name contains '.mov' or name contains '.mp4') and trashed = false"

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
            request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResp = response as? HTTPURLResponse {
                let targetData: Data?
                if httpResp.statusCode == 401 {
                    if await refreshAccessTokenIfNeeded(), let newToken = accessToken {
                        var retryReq = URLRequest(url: driveURL)
                        retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        if let (retryData, retryResp) = try? await URLSession.shared.data(for: retryReq),
                           (retryResp as? HTTPURLResponse)?.statusCode == 200 {
                            targetData = retryData
                        } else {
                            targetData = nil
                        }
                    } else {
                        targetData = nil
                    }
                } else if httpResp.statusCode == 200 {
                    targetData = data
                } else {
                    targetData = nil
                }

                if let responseData = targetData,
                   let jsonDict = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                    if let rawFiles = jsonDict["files"] as? [[String: Any]] {
                        for fileDict in rawFiles {
                            let id = (fileDict["id"] as? String) ?? ""
                            let name = (fileDict["name"] as? String) ?? "file.jpg"
                            let mimeType = (fileDict["mimeType"] as? String) ?? "image/jpeg"
                            let thumbnailLink = fileDict["thumbnailLink"] as? String
                            let webContentLink = fileDict["webContentLink"] as? String

                            guard !id.isEmpty else { continue }

                            if !fetchedItems.contains(where: { $0.id == id }) {
                                let item = GoogleMediaItem(
                                    id: id,
                                    filename: name,
                                    mimeType: mimeType,
                                    baseUrl: webContentLink ?? thumbnailLink ?? "",
                                    productUrl: thumbnailLink,
                                    mediaMetadata: nil,
                                    fetchedAt: now
                                )
                                fetchedItems.append(item)
                            }
                        }
                    }
                    drivePageToken = jsonDict["nextPageToken"] as? String
                } else {
                    drivePageToken = nil
                }
            } else {
                drivePageToken = nil
            }

            self.statusMessage = "Поиск медиафайлов... Загружено: \(fetchedItems.count)"
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

    /// Вспомогательный парсер ответа Google Photos List API
    private func parsePhotosResponse(_ data: Data, into items: inout [GoogleMediaItem], pageToken: inout String?, fetchedAt: Date) {
        struct GooglePhotosListResponse: Codable {
            let mediaItems: [RawMediaItem]?
            let nextPageToken: String?

            struct RawMediaItem: Codable {
                let id: String?
                let filename: String?
                let mimeType: String?
                let baseUrl: String?
                let productUrl: String?
                let mediaMetadata: GoogleMediaMetadata?
            }
        }
        if let result = try? JSONDecoder().decode(GooglePhotosListResponse.self, from: data) {
            if let rawItems = result.mediaItems {
                for raw in rawItems {
                    guard let id = raw.id, !id.isEmpty else { continue }
                    guard !items.contains(where: { $0.id == id }) else { continue }
                    let item = GoogleMediaItem(
                        id: id,
                        filename: raw.filename ?? "photo.jpg",
                        mimeType: raw.mimeType ?? "image/jpeg",
                        baseUrl: raw.baseUrl ?? "",
                        productUrl: raw.productUrl,
                        mediaMetadata: raw.mediaMetadata,
                        fetchedAt: fetchedAt
                    )
                    items.append(item)
                }
            }
            pageToken = result.nextPageToken
        } else {
            pageToken = nil
        }
    }

    // MARK: - Refresh single item's baseUrl (anti-stale)

    /// Получает свежий baseUrl для одного элемента Google Photos (живёт 60 мин).
    /// Вызывается перед скачиванием, если item.isBaseUrlStale == true.
    func refreshedItem(_ item: GoogleMediaItem) async -> GoogleMediaItem {
        guard !item.id.isEmpty,
              // Drive-элементы не протухают (webContentLink стабилен)
              !item.baseUrl.contains("drive.google.com"),
              !item.baseUrl.contains("content.googleapis.com"),
              item.isBaseUrlStale,
              let token = accessToken else {
            return item
        }

        guard let url = URL(string: "https://photoslibrary.googleapis.com/v1/mediaItems/\(item.id)") else {
            return item
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let json = try? JSONDecoder().decode(GoogleMediaItem.self, from: data) {
            // Обновляем в общем списке тоже
            if let idx = mediaItems.firstIndex(where: { $0.id == item.id }) {
                mediaItems[idx] = json
            }
            return json
        }

        // Retry после refresh токена
        if await refreshAccessTokenIfNeeded(), let newToken = accessToken {
            var retryReq = URLRequest(url: url)
            retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            if let (retryData, retryResp) = try? await URLSession.shared.data(for: retryReq),
               (retryResp as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONDecoder().decode(GoogleMediaItem.self, from: retryData) {
                if let idx = mediaItems.firstIndex(where: { $0.id == item.id }) {
                    mediaItems[idx] = json
                }
                return json
            }
        }

        return item
    }

    // MARK: - Download Media

    /// Скачивает реальный медиафайл из Google Photos по URL.
    /// Автоматически обновляет baseUrl если он устарел (> 55 мин).
    func downloadItemData(_ item: GoogleMediaItem) async throws -> Data {
        // Получаем свежий item если baseUrl протух
        let freshItem = await refreshedItem(item)

        guard let url = freshItem.downloadURL ?? URL(string: freshItem.baseUrl) else {
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
