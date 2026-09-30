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
    /// true — файл лежит на Google Диске, false — выбран через Google Photos Picker
    let isFromDrive: Bool

    var isVideo: Bool {
        let fn = filename.lowercased()
        let mt = mimeType.lowercased()
        return mt.contains("video") || fn.hasSuffix(".mp4") || fn.hasSuffix(".mov") || fn.hasSuffix(".m4v") || fn.hasSuffix(".avi") || fn.hasSuffix(".mkv") || fn.hasSuffix(".webm") || fn.hasSuffix(".3gp")
    }

    /// Проверка, является ли файл реальным медиа (фото или видео), исключая системные/исполняемые файлы
    static func isSupportedMedia(filename: String, mimeType: String) -> Bool {
        let fn = filename.lowercased()
        let mt = mimeType.lowercased()

        // Черный список расширений (системные файлы, исполняемые, архивы, документы)
        let ignoredExtensions = [
            ".ini", ".exe", ".dll", ".bat", ".cmd", ".sh", ".zip", ".rar", ".7z", ".tar", ".gz",
            ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".txt", ".json", ".xml",
            ".plist", ".dmg", ".pkg", ".apk", ".ipa", ".iso", ".html", ".htm", ".css", ".js",
            ".py", ".swift", ".kt", ".java", ".c", ".cpp", ".h", ".log", ".db", ".sqlite", ".dat"
        ]
        if ignoredExtensions.contains(where: { fn.hasSuffix($0) }) {
            return false
        }

        // Допустимые MIME-типы
        if mt.starts(with: "image/") || mt.starts(with: "video/") {
            return true
        }

        // Белый список расширений
        let mediaExtensions = [
            ".jpg", ".jpeg", ".png", ".heic", ".heif", ".dng", ".webp", ".tiff", ".tif",
            ".raw", ".cr2", ".cr3", ".nef", ".arw", ".bmp", ".gif", ".svg",
            ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm", ".3gp"
        ]
        return mediaExtensions.contains(where: { fn.hasSuffix($0) })
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
        // 1. Google Drive thumbnailLink
        if let productUrl = productUrl, !productUrl.isEmpty, productUrl.hasPrefix("http") {
            if productUrl.contains("=s") {
                let upgraded = productUrl.replacingOccurrences(of: "=s220", with: "=s400")
                return URL(string: upgraded) ?? URL(string: productUrl)
            }
            return URL(string: productUrl)
        }

        // 2. Drive прямая ссылка на миниатюру по id
        if baseUrl.contains("drive.google.com") || baseUrl.contains("googleusercontent.com/drive") {
            return URL(string: "https://drive.google.com/thumbnail?id=\(id)&sz=w400")
        }

        guard !baseUrl.isEmpty else { return nil }

        // 3. Google Photos API baseUrl
        let cleanBase = baseUrl.components(separatedBy: "=")[0]
        guard !cleanBase.isEmpty else { return nil }
        return URL(string: "\(cleanBase)=w400-h400-c")
    }

    var previewURL: URL? {
        if let productUrl = productUrl, !productUrl.isEmpty, productUrl.hasPrefix("http") {
            if productUrl.contains("=s") {
                let upgraded = productUrl.replacingOccurrences(of: "=s220", with: "=s1200")
                return URL(string: upgraded) ?? URL(string: productUrl)
            }
        }

        if baseUrl.contains("drive.google.com") || baseUrl.contains("googleusercontent.com/drive") {
            return URL(string: "https://drive.google.com/thumbnail?id=\(id)&sz=w1200")
        }

        guard !baseUrl.isEmpty else { return nil }
        let cleanBase = baseUrl.components(separatedBy: "=")[0]
        guard !cleanBase.isEmpty else { return nil }
        return URL(string: "\(cleanBase)=w1200-h1200")
    }

    enum CodingKeys: String, CodingKey {
        case id, filename, mimeType, baseUrl, productUrl, mediaMetadata, fetchedAt, isFromDrive
    }

    init(id: String, filename: String, mimeType: String, baseUrl: String, productUrl: String?, mediaMetadata: GoogleMediaMetadata?, fetchedAt: Date = Date(), isFromDrive: Bool = false) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.baseUrl = baseUrl
        self.productUrl = productUrl
        self.mediaMetadata = mediaMetadata
        self.fetchedAt = fetchedAt
        self.isFromDrive = isFromDrive
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
        self.isFromDrive = (try? container.decode(Bool.self, forKey: .isFromDrive)) ?? false
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

// MARK: - Ошибки Google Фото / Диска

enum GooglePhotosError: LocalizedError {
    case notAuthenticated
    case reauthRequired
    case apiDisabled(String)
    case http(Int, String)
    case badResponse
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Сначала войдите в Google.".localized
        case .reauthRequired:
            return "Google не принял доступ. Выйдите и войдите снова — так приложение получит новые права на выбор фото.".localized
        case .apiDisabled(let apiName):
            return "В вашем проекте Google Cloud не включён".localized + " \(apiName). " + "Включите его в APIs & Services → Library и повторите.".localized
        case .http(let code, let message):
            return "Google вернул ошибку".localized + " \(code)" + (message.isEmpty ? "" : ": \(message)")
        case .badResponse:
            return "Не удалось разобрать ответ Google.".localized
        case .timedOut:
            return "Время ожидания выбора истекло. Попробуйте ещё раз.".localized
        case .cancelled:
            return "Выбор отменён.".localized
        }
    }
}

/// Сессия выбора в Google Photos Picker API
struct GooglePickerSession: Sendable {
    let id: String
    let pickerURL: URL
    let pollInterval: TimeInterval
    let timeout: TimeInterval
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
    /// Последняя ошибка обращения к Google — показывается пользователю вместо пустого экрана
    @Published var lastError: String?

    private(set) var accessToken: String?
    /// Активная сессия Google Photos Picker (нужна, чтобы обновить ссылки на файлы и удалить сессию после импорта)
    private var activePickerSessionId: String?
    private var pickedItemsById: [String: GoogleMediaItem] = [:]

    /// Версия набора прав. Google закрыл чтение всей библиотеки (photoslibrary.readonly) — теперь нужен Picker API.
    /// Токены, выданные со старыми правами, не работают, поэтому при смене версии просим войти заново.
    private static let scopeVersionKey = "google_photos_scope_version"
    private static let currentScopeVersion = 2
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

    private func clearStoredCredentials() {
        KeychainHelper.shared.delete(for: "com.stockflow.googlephotos")
        KeychainHelper.shared.delete(for: "com.stockflow.googlephotos.refresh")
        UserDefaults.standard.removeObject(forKey: "google_photos_user_email")
        UserDefaults.standard.removeObject(forKey: Self.scopeVersionKey)
        self.accessToken = nil
        self.userEmail = ""
        self.isAuthenticated = false
    }

    private func checkExistingToken() {
        let hasStoredToken = (KeychainHelper.shared.read(for: "com.stockflow.googlephotos") ?? "").isEmpty == false
            || (KeychainHelper.shared.read(for: "com.stockflow.googlephotos.refresh") ?? "").isEmpty == false
        if hasStoredToken && UserDefaults.standard.integer(forKey: Self.scopeVersionKey) != Self.currentScopeVersion {
            // Вход был выполнен со старыми правами (чтение всей библиотеки) — Google их больше не принимает
            clearStoredCredentials()
            self.statusMessage = "Права Google Фото изменились. Войдите заново.".localized
            return
        }

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

        // Picker API: пользователь сам выбирает файлы в окне Google Фото (чтение всей библиотеки Google отключил)
        let scopes = [
            "https://www.googleapis.com/auth/photospicker.mediaitems.readonly",
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
                UserDefaults.standard.set(Self.currentScopeVersion, forKey: Self.scopeVersionKey)
                self.lastError = nil
                self.isAuthenticated = true
                self.statusMessage = "Успешная авторизация в Google".localized

                await fetchUserProfile()
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
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var details = ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                details = (json["error_description"] as? String) ?? (json["error"] as? String) ?? ""
            }
            throw GooglePhotosError.http(status, details)
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
        clearStoredCredentials()
        self.activePickerSessionId = nil
        self.pickedItemsById = [:]
        self.lastError = nil
        self.mediaItems = []
        self.statusMessage = "Отключено от Google Фото".localized
        // Очищаем кеш миниатюр при выходе
        GoogleImageCache.clearAll()
    }


    // MARK: - Обращения к Google API (с обновлением токена и понятными ошибками)

    private static let pickerAPIName = "Google Photos Picker API"
    private static let driveAPIName = "Google Drive API"
    private static let pickerBase = "https://photospicker.googleapis.com/v1"

    /// Переводит ответ Google с ошибкой в понятную пользователю причину
    private static func mapError(status: Int, data: Data, apiName: String) -> GooglePhotosError {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let lower = raw.lowercased()
        var message = ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? [String: Any] {
            message = (err["message"] as? String) ?? ""
        }
        if status == 401 {
            return .reauthRequired
        }
        if status == 403 {
            if lower.contains("service_disabled") || lower.contains("has not been used in project") || lower.contains("it is disabled") {
                return .apiDisabled(apiName)
            }
            if lower.contains("insufficient") || lower.contains("scope") {
                return .reauthRequired
            }
        }
        return .http(status, String(message.prefix(200)))
    }

    private func authorizedData(url: URL, method: String = "GET", jsonBody: Data? = nil, apiName: String) async throws -> Data {
        func attempt() async throws -> (Data, Int) {
            guard let token = accessToken else { throw GooglePhotosError.notAuthenticated }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body = jsonBody {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        var (data, status) = try await attempt()
        if status == 401, await refreshAccessTokenIfNeeded() {
            (data, status) = try await attempt()
        }
        guard (200..<300).contains(status) else {
            throw Self.mapError(status: status, data: data, apiName: apiName)
        }
        return data
    }

    private static func parseSeconds(_ value: Any?) -> TimeInterval? {
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: CharacterSet(charactersIn: "s ")))
        }
        if let number = value as? Double {
            return number
        }
        return nil
    }

    // MARK: - Google Photos Picker API (выбор фото и видео в окне Google Фото)

    /// Создаёт сессию выбора. Адрес `pickerURL` нужно открыть пользователю — там он отмечает файлы.
    func createPickerSession(maxItems: Int = 2000) async throws -> GooglePickerSession {
        guard let url = URL(string: "\(Self.pickerBase)/sessions") else { throw GooglePhotosError.badResponse }
        let body = try JSONSerialization.data(withJSONObject: ["pickingConfig": ["maxItemCount": String(maxItems)]])
        let data = try await authorizedData(url: url, method: "POST", jsonBody: body, apiName: Self.pickerAPIName)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let uriString = json["pickerUri"] as? String,
              let pickerURL = URL(string: uriString) else {
            throw GooglePhotosError.badResponse
        }

        let polling = json["pollingConfig"] as? [String: Any]
        let interval = Self.parseSeconds(polling?["pollInterval"]) ?? 5
        let timeout = Self.parseSeconds(polling?["timeoutIn"]) ?? 600

        activePickerSessionId = id
        pickedItemsById = [:]
        return GooglePickerSession(
            id: id,
            pickerURL: pickerURL,
            pollInterval: max(2, min(interval, 15)),
            timeout: min(max(timeout, 60), 1800)
        )
    }

    /// true — пользователь закончил выбор и нажал «Готово» в Google Фото
    func isPickerSelectionReady(sessionId: String) async throws -> Bool {
        guard let url = URL(string: "\(Self.pickerBase)/sessions/\(sessionId)") else { throw GooglePhotosError.badResponse }
        let data = try await authorizedData(url: url, apiName: Self.pickerAPIName)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["mediaItemsSet"] as? Bool) ?? false
    }

    private struct PickerItemsPage: Decodable {
        let mediaItems: [PickerItem]?
        let nextPageToken: String?

        struct PickerItem: Decodable {
            let id: String?
            let type: String?
            let mediaFile: PickerMediaFile?
        }

        struct PickerMediaFile: Decodable {
            let baseUrl: String?
            let mimeType: String?
            let filename: String?
            let mediaFileMetadata: GoogleMediaMetadata?
        }
    }

    /// Получает список файлов, которые пользователь выбрал в этой сессии
    func fetchPickedItems(sessionId: String, onProgress: ((Int) -> Void)? = nil) async throws -> [GoogleMediaItem] {
        var result: [GoogleMediaItem] = []
        var seen = Set<String>()
        var pageToken: String? = nil
        let now = Date()

        repeat {
            var components = URLComponents(string: "\(Self.pickerBase)/mediaItems")
            var queryItems = [
                URLQueryItem(name: "sessionId", value: sessionId),
                URLQueryItem(name: "pageSize", value: "100")
            ]
            if let token = pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }
            components?.queryItems = queryItems
            guard let url = components?.url else { throw GooglePhotosError.badResponse }

            let data = try await authorizedData(url: url, apiName: Self.pickerAPIName)
            guard let page = try? JSONDecoder().decode(PickerItemsPage.self, from: data) else {
                throw GooglePhotosError.badResponse
            }

            for raw in page.mediaItems ?? [] {
                guard let id = raw.id, !id.isEmpty, !seen.contains(id),
                      let file = raw.mediaFile, let baseUrl = file.baseUrl, !baseUrl.isEmpty else { continue }
                seen.insert(id)

                let mimeType = file.mimeType ?? ""
                let isVideo = (raw.type ?? "").uppercased() == "VIDEO" || mimeType.lowercased().hasPrefix("video/")
                let rawName = file.filename ?? ""
                let filename = rawName.isEmpty ? "\(id.prefix(8)).\(isVideo ? "mp4" : "jpg")" : rawName

                result.append(GoogleMediaItem(
                    id: id,
                    filename: filename,
                    mimeType: mimeType.isEmpty ? (isVideo ? "video/mp4" : "image/jpeg") : mimeType,
                    baseUrl: baseUrl,
                    productUrl: nil,
                    mediaMetadata: file.mediaFileMetadata,
                    fetchedAt: now,
                    isFromDrive: false
                ))
            }

            pageToken = page.nextPageToken
            onProgress?(result.count)
        } while pageToken != nil

        pickedItemsById = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return result
    }

    /// Закрывает сессию выбора (Google хранит её, пока не удалить)
    func endPickerSession() async {
        guard let id = activePickerSessionId else { return }
        activePickerSessionId = nil
        pickedItemsById = [:]
        if let url = URL(string: "\(Self.pickerBase)/sessions/\(id)") {
            _ = try? await authorizedData(url: url, method: "DELETE", apiName: Self.pickerAPIName)
        }
    }

    /// Ссылки на файлы из Picker живут около часа. Длинный импорт обновляет их повторным запросом списка сессии.
    private func refreshedPickerItem(_ item: GoogleMediaItem) async -> GoogleMediaItem {
        guard !item.isFromDrive, item.isBaseUrlStale else { return item }
        if let cached = pickedItemsById[item.id], !cached.isBaseUrlStale {
            return cached
        }
        guard let sessionId = activePickerSessionId,
              let fresh = try? await fetchPickedItems(sessionId: sessionId),
              let updated = fresh.first(where: { $0.id == item.id }) else {
            return item
        }
        return updated
    }

    // MARK: - Google Диск (список фото и видео, хранящихся на Диске)

    /// Загружает фото и видео с Google Диска. Фото из Google Фото здесь не появляются — для них есть Picker.
    func loadDriveItems(forceReload: Bool = false) async {
        guard isAuthenticated else { return }
        if !forceReload && !mediaItems.isEmpty { return }

        isLoading = true
        lastError = nil
        statusMessage = "Поиск медиафайлов на Google Диске...".localized

        var fetched: [GoogleMediaItem] = []
        var seen = Set<String>()
        var pageToken: String? = nil
        var pageCount = 0
        let now = Date()
        let query = "(mimeType contains 'image/' or mimeType contains 'video/' or name contains '.jpg' or name contains '.jpeg' or name contains '.png' or name contains '.heic' or name contains '.heif' or name contains '.dng' or name contains '.webp' or name contains '.mov' or name contains '.mp4') and trashed = false"

        do {
            repeat {
                pageCount += 1
                var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")
                var queryItems = [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "pageSize", value: "1000"),
                    URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,thumbnailLink,webContentLink)")
                ]
                if let token = pageToken {
                    queryItems.append(URLQueryItem(name: "pageToken", value: token))
                }
                components?.queryItems = queryItems
                guard let url = components?.url else { throw GooglePhotosError.badResponse }

                let data = try await authorizedData(url: url, apiName: Self.driveAPIName)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw GooglePhotosError.badResponse
                }

                for file in (json["files"] as? [[String: Any]]) ?? [] {
                    let id = (file["id"] as? String) ?? ""
                    let name = (file["name"] as? String) ?? "file.jpg"
                    let mimeType = (file["mimeType"] as? String) ?? "image/jpeg"
                    guard !id.isEmpty, !seen.contains(id),
                          GoogleMediaItem.isSupportedMedia(filename: name, mimeType: mimeType) else { continue }
                    seen.insert(id)

                    let thumbnailLink = file["thumbnailLink"] as? String
                    let webContentLink = file["webContentLink"] as? String
                    fetched.append(GoogleMediaItem(
                        id: id,
                        filename: name,
                        mimeType: mimeType,
                        baseUrl: webContentLink ?? thumbnailLink ?? "",
                        productUrl: thumbnailLink,
                        mediaMetadata: nil,
                        fetchedAt: now,
                        isFromDrive: true
                    ))
                }

                pageToken = json["nextPageToken"] as? String
                statusMessage = "Поиск медиафайлов... Загружено: \(fetched.count)"
            } while pageToken != nil && pageCount < 100
        } catch {
            lastError = error.localizedDescription
        }

        mediaItems = fetched
        if fetched.isEmpty {
            statusMessage = "На Google Диске не найдено фото и видео.".localized
        } else {
            statusMessage = "Найдено медиафайлов: \(fetched.count)"
        }
        isLoading = false
    }

    // MARK: - Скачивание

    /// Скачивает файл во временный файл (а не в память — видео бывают очень большими).
    /// Вызывающий обязан перенести или удалить полученный файл.
    func downloadItemFile(_ item: GoogleMediaItem) async throws -> URL {
        downloadProgress[item.id] = 0.1
        defer { downloadProgress[item.id] = nil }

        if item.isFromDrive {
            guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(item.id)?alt=media") else {
                throw GooglePhotosError.badResponse
            }
            return try await downloadFile(from: url, apiName: Self.driveAPIName)
        }

        let fresh = await refreshedPickerItem(item)
        guard let url = fresh.downloadURL else { throw GooglePhotosError.badResponse }
        return try await downloadFile(from: url, apiName: Self.pickerAPIName)
    }

    private func downloadFile(from url: URL, apiName: String) async throws -> URL {
        for attempt in 0..<2 {
            guard let token = accessToken else { throw GooglePhotosError.notAuthenticated }
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            // Ссылки Picker API работают только с токеном в заголовке
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (tempURL, response) = try await URLSession.shared.download(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if (200..<300).contains(status) {
                // Системный временный файл удаляется сразу после возврата — переносим в свой
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent("gp_\(UUID().uuidString)")
                try FileManager.default.moveItem(at: tempURL, to: destination)
                return destination
            }

            if status == 401, attempt == 0, await refreshAccessTokenIfNeeded() {
                try? FileManager.default.removeItem(at: tempURL)
                continue
            }

            let body = (try? Data(contentsOf: tempURL)) ?? Data()
            try? FileManager.default.removeItem(at: tempURL)
            throw Self.mapError(status: status, data: body, apiName: apiName)
        }
        throw GooglePhotosError.badResponse
    }
}
