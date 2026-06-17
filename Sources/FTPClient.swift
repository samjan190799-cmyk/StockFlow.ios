import Foundation

// MARK: - FTPClient
class FTPClient {
        static func testConnection(
                    host: String,
                    port: Int = 21,
                    username: String,
                    password: String
        ) async throws {
                    let cleanHost = cleanedHost(host)
                    let scheme = schemeFor(host: host)

                    // For SFTP - just check DNS/port, as URLSession does not support SFTP
                    if scheme == "sftp" {
                                    try await checkTCPReachability(host: cleanHost, port: port == 21 ? 22 : port)
                                    return
                    }

                    // FTP/FTPS - try listing the root directory
                    let urlString = "\(scheme)://\(cleanHost):\(port)/"
                    guard let url = URL(string: urlString) else {
                                    throw ftpError("Invalid URL: \(urlString)")
                    }

                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 20
                    config.timeoutIntervalForResource = 30
                    let session = URLSession(configuration: config)
                    defer { session.invalidateAndCancel() }

                    var request = URLRequest(url: url)
                    request.timeoutInterval = 20

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
                                                        throw ftpError("Server returned error: \(httpResp.statusCode)")
                                    }
                                    storage.removeDefaultCredential(credential, forProtectionSpace: protectionSpace)
                    } catch let error as NSError {
                                    storage.removeDefaultCredential(credential, forProtectionSpace: protectionSpace)
                                    if error.domain == NSURLErrorDomain && (error.code == NSURLErrorUserAuthenticationRequired || error.code == 9) {
                                                        throw ftpError("Invalid username or password: \(error.localizedDescription)")
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
                                    throw ftpError("Username not specified")
                    }
                    guard !password.isEmpty else {
                                    throw ftpError("Password not specified")
                    }

                    if scheme == "sftp" {
                                    throw ftpError("SFTP upload is not supported yet. Use FTP host for \(host).")
                    }

                    let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
                    let urlString = "\(scheme)://\(username):\(encodedPassword)@\(cleanHost):\(ftpPort)/\(filename)"
                    guard let url = URL(string: urlString) else {
                                    throw ftpError("Invalid upload URL")
                    }

                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 60
                    config.timeoutIntervalForResource = 300

                    let delegate = FTPUploadDelegate()
                    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
                    defer { session.invalidateAndCancel() }

                    var request = URLRequest(url: url)
                    request.httpMethod = "PUT"
                    request.timeoutInterval = 300

                    var lastError: Error = ftpError("Unknown error")
                    for attempt in 1...3 {
                                    do {
                                                        let (_, response) = try await session.upload(for: request, from: data)
                                                        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                                                                                throw ftpError("Upload error: HTTP \(httpResp.statusCode)")
                                                        }
                                                        return
                                    } catch let error as NSError {
                                                        lastError = error
                                                        if error.code == NSURLErrorUserAuthenticationRequired ||
                                                           error.code == NSURLErrorUserCancelledAuthentication ||
                                                           error.code == NSURLErrorCancelled {
                                                                                   throw error
                                                           }
                                                        if attempt < 3 {
                                                                                let delay = Double(attempt) * 2.0
                                                                                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                                        }
                                    }
                    }
                    throw lastError
        }

        // MARK: - Helpers

        private static func schemeFor(host: String) -> String {
                    let lower = host.lowercased()
                    if lower.hasPrefix("sftp") || lower.contains(".sftp.") {
                                    return "sftp"
                    } else if lower.hasPrefix("ftps") {
                                    return "ftps"
                    }
                    return "ftp"
        }

        private static func cleanedHost(_ host: String) -> String {
                    var h = host
                    for prefix in ["sftp://", "ftps://", "ftp://"] {
                                    if h.lowercased().hasPrefix(prefix) {
                                                        h = String(h.dropFirst(prefix.count))
                                    }
                    }
                    if h.hasSuffix("/") { h = String(h.dropLast()) }
                    return h
        }

        private static func checkTCPReachability(host: String, port: Int) async throws {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                                                                           var sockaddr = sockaddr_in()
                                                                           sockaddr.sin_family = sa_family_t(AF_INET)
                                                                           sockaddr.sin_port = in_port_t(port).bigEndian

                                                                           guard inet_pton(AF_INET, host, &sockaddr.sin_addr) == 1 || host.contains(".") else {
                                                                                               continuation.resume(throwing: ftpError("Could not resolve host: \(host)"))
                                                                                               return
                                                                           }

                                                                           let sock = socket(AF_INET, SOCK_STREAM, 0)
                                                                           guard sock >= 0 else {
                                                                                               continuation.resume(throwing: ftpError("Socket creation error"))
                                                                                               return
                                                                           }

                                                                           fcntl(sock, F_SETFL, O_NONBLOCK)
                                                                           withUnsafePointer(to: &sockaddr) {
                                                                                               $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                                                                                                                                                                         _ = connect(sock, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                                                                                                                                                    }
                                                                           }

                                                                           var fdset = fd_set()
                                                                           fdset.__fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                                                                           var timeout = timeval(tv_sec: 10, tv_usec: 0)
                                                                           let result = withUnsafeMutablePointer(to: &fdset) { fdPtr in
                                                                                                                                              select(sock + 1, nil, fdPtr, nil, &timeout)
                                                                                                                             }
                                                                           close(sock)

                                                                           if result > 0 {
                                                                                               continuation.resume()
                                                                           } else {
                                                                                               continuation.resume(throwing: ftpError("Host \(host):\(port) unreachable (timeout)"))
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
                    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                       let serverTrust = challenge.protectionSpace.serverTrust {
                                       let credential = URLCredential(trust: serverTrust)
                                       completionHandler(.useCredential, credential)
                       } else {
                                       completionHandler(.performDefaultHandling, nil)
                       }
        }
}
