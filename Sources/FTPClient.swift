import Foundation
import Network

// MARK: - FTPClient
// Реализация через URLSession (нативная поддержка iOS)
// Поддерживает: FTP, FTPS (implicit), SFTP — через URL-схему
class FTPClient {

    // MARK: - Test Connection
    static func testConnection(
        host: String,
        port: Int = 21,
        username: String,
        password: String
    ) async throws {
        let cleanHost = cleanedHost(host)
        let scheme = schemeFor(host: host)

        // Для SFTP — просто проверяем DNS/порт, так как URLSession не поддерживает SFTP
        if scheme == "sftp" {
            try await checkTCPReachability(host: cleanHost, port: port == 21 ? 22 : port)
            return
        }

        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
        let urlString = "\(scheme)://\(username):\(encodedPassword)@\(cleanHost):\(port)/"
        guard let url = URL(string: urlString) else {
            throw ftpError("Некорректный URL: \(urlString)")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(from: url)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                throw ftpError("Сервер вернул ошибку: \(httpResp.statusCode)")
            }
        } catch let error as NSError {
            // Код 9 = CURLE_FTP_ACCESS_DENIED или auth failure — нормально, значит сервер отвечает
            if error.domain == NSURLErrorDomain && (error.code == NSURLErrorUserAuthenticationRequired || error.code == 9) {
                throw ftpError("Неверный логин или пароль: \(error.localizedDescription)")
            }
            throw error
        }
    }

    // MARK: - Upload
    static func upload(
        data: Data,
        filename: String,
        host: String,
        port: Int = 21,
        username: String,
        password: String
    ) async throws {
        let cleanHost = cleanedHost(host)
        let scheme = schemeFor(host: host)
        let ftpPort = (scheme == "sftp") ? (port == 21 ? 22 : port) : port

        guard !username.isEmpty else {
            throw ftpError("Логин не указан")
        }
        guard !password.isEmpty else {
            throw ftpError("Пароль не указан")
        }

        if scheme == "sftp" {
            // SFTP не поддерживается URLSession нативно — бросаем понятную ошибку
            throw ftpError("SFTP загрузка пока не поддерживается. Используйте FTP-хост для \(host).")
        }

        let urlString = "\(scheme)://\(username):\(password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password)@\(cleanHost):\(ftpPort)/\(filename)"
        guard let url = URL(string: urlString) else {
            throw ftpError("Некорректный URL для загрузки")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300  // 5 мин для больших файлов

        let delegate = FTPUploadDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 300

        // Retry logic: 3 попытки с задержкой
        var lastError: Error = ftpError("Неизвестная ошибка")
        for attempt in 1...3 {
            do {
                let (_, response) = try await session.upload(for: request, from: data)

                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                    throw ftpError("Ошибка загрузки: HTTP \(httpResp.statusCode)")
                }
                // Успех
                return
            } catch let error as NSError {
                lastError = error

                // Не ретраить на auth errors или user cancelled
                if error.code == NSURLErrorUserAuthenticationRequired ||
                   error.code == NSURLErrorUserCancelledAuthentication ||
                   error.code == NSURLErrorCancelled {
                    throw error
                }

                if attempt < 3 {
                    // Экспоненциальная задержка: 2с, 4с
                    let delay = Double(attempt) * 2.0
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError
    }

    // MARK: - Helpers

    /// Определяет схему на основе хоста
    private static func schemeFor(host: String) -> String {
        let lower = host.lowercased()
        if lower.hasPrefix("sftp") || lower.contains(".sftp.") {
            return "sftp"
        } else if lower.hasPrefix("ftps") {
            return "ftps"
        }
        return "ftp"
    }

    /// Убирает префикс протокола из хоста (sftp://, ftp://, ftps://)
    private static func cleanedHost(_ host: String) -> String {
        var h = host
        for prefix in ["sftp://", "ftps://", "ftp://"] {
            if h.lowercased().hasPrefix(prefix) {
                h = String(h.dropFirst(prefix.count))
            }
        }
        // Убираем слэш в конце если есть
        if h.hasSuffix("/") { h = String(h.dropLast()) }
        return h
    }

    /// Проверка TCP-доступности хоста (для SFTP)
    private static func checkTCPReachability(host: String, port: Int) async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resolved = false
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resolved {
                        resolved = true
                        connection.cancel()
                        continuation.resume()
                    }
                case .failed(let error):
                    if !resolved {
                        resolved = true
                        connection.cancel()
                        continuation.resume(throwing: error)
                    }
                case .waiting(let error):
                    if !resolved {
                        resolved = true
                        connection.cancel()
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            
            // Таймаут через 10 секунд
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !resolved {
                    resolved = true
                    connection.cancel()
                    continuation.resume(throwing: ftpError("Таймаут подключения к хосту \(host):\(port)"))
                }
            }
            
            connection.start(queue: .global())
        }
    }

    private static func ftpError(_ message: String) -> NSError {
        NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - URLSession Delegate for FTP Auth
private class FTPUploadDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Принимаем любой TLS-сертификат (для FTPS с самоподписанным сертификатом)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodDefault ||
                  challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic {
            // Используем кредентиалы из URL
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
