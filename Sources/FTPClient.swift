import Foundation

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

        // FTP/FTPS — пробуем листинг корневой директории
        let urlString = "\(scheme)://\(cleanHost):\(port)/"
        guard let url = URL(string: urlString) else {
            throw ftpError("Некорректный URL: \(urlString)")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        // Встроенная auth через URL
        let credential = URLCredential(user: username, password: password, persistence: .none)
        let protectionSpace = URLProtectionSpace(
            host: cleanHost,
            port: port,
            protocol: scheme == "ftps" ? "ftps" : "ftp",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodDefault
        )

        let storage = URLCredentialStorage.shared
        storage.setDefaultCredential(credential, forProtectionSpace: protectionSpace)

        do {
            let (_, response) = try await session.data(from: url)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                throw ftpError("Сервер вернул ошибку: \(httpResp.statusCode)")
            }
            storage.removeDefaultCredential(credential, forProtectionSpace: protectionSpace)
        } catch let error as NSError {
            storage.removeDefaultCredential(credential, forProtectionSpace: protectionSpace)
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var sockaddr = sockaddr_in()
            sockaddr.sin_family = sa_family_t(AF_INET)
            sockaddr.sin_port = in_port_t(port).bigEndian

            guard inet_pton(AF_INET, host, &sockaddr.sin_addr) == 1 ||
                  host.contains(".") else {
                continuation.resume(throwing: ftpError("Не удалось разрешить хост: \(host)"))
                return
            }

            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else {
                continuation.resume(throwing: ftpError("Ошибка создания сокета"))
                return
            }

            // Неблокирующий режим
            fcntl(sock, F_SETFL, O_NONBLOCK)

            withUnsafePointer(to: &sockaddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                    _ = connect(sock, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            var fdset = fd_set()
            fdset.__fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            var timeout = timeval(tv_sec: 10, tv_usec: 0)
            let result = withUnsafeMutablePointer(to: &fdset) { fdPtr in
                select(sock + 1, nil, fdPtr, nil, &timeout)
            }

            close(sock)

            if result > 0 {
                continuation.resume()
            } else {
                continuation.resume(throwing: ftpError("Хост \(host):\(port) недоступен (таймаут)"))
            }
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
