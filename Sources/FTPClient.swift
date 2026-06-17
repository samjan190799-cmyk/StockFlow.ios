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

                            if scheme == "sftp" {
                                                throw ftpError("SFTP \u{442}\u{435}\u{441}\u{442} \u{441}\u{43e}\u{435}\u{434}\u{438}\u{43d}\u{435}\u{43d}\u{438}\u{44f} \u{43d}\u{435} \u{43f}\u{43e}\u{434}\u{434}\u{435}\u{440}\u{436}\u{438}\u{432}\u{430}\u{435}\u{442}\u{441}\u{44f} \u{43d}\u{430}\u{43f}\u{440}\u{44f}\u{43c}\u{443}.")
                            }

                            let urlString = "\(scheme)://\(cleanHost):\(port)/"
                            guard let url = URL(string: urlString) else {
                                                throw ftpError("\u{41d}\u{435}\u{43a}\u{43e}\u{440}\u{440}\u{435}\u{43a}\u{442}\u{43d}\u{44b}\u{439} URL: \(urlString)")
                            }

                            let config = URLSessionConfiguration.default
                            config.timeoutIntervalForRequest = 20
                            config.timeoutIntervalForResource = 30
                            let session = URLSession(configuration: config)
                            defer { session.invalidateAndCancel() }

                            do {
                                                let (_, _) = try await session.data(from: url)
                            } catch let error as NSError {
                                                if error.code == NSURLErrorUserAuthenticationRequired {
                                                                        throw ftpError("\u{41d}\u{435}\u{432}\u{435}\u{440}\u{43d}\u{44b}\u{439} \u{43b}\u{43e}\u{433}\u{438}\u{43d} \u{438}\u{43b}\u{438} \u{43f}\u{430}\u{440}\u{43e}\u{43b}\u{44c}")
                                                }
                                                // Connection reached server - credentials may be wrong but server is reachable
                                                if error.domain == NSURLErrorDomain {
                                                                        throw error
                                                }
                            }
            }

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

                            guard !username.isEmpty else {
                                                throw ftpError("\u{41b}\u{43e}\u{433}\u{438}\u{43d} \u{43d}\u{435} \u{443}\u{43a}\u{430}\u{437}\u{430}\u{43d}")
                            }

                            guard !password.isEmpty else {
                                                throw ftpError("\u{41f}\u{430}\u{440}\u{43e}\u{43b}\u{44c} \u{43d}\u{435} \u{443}\u{43a}\u{430}\u{437}\u{430}\u{43d}")
                            }

                            if scheme == "sftp" {
                                                throw ftpError("SFTP \u{43d}\u{435} \u{43f}\u{43e}\u{434}\u{434}\u{435}\u{440}\u{436}\u{438}\u{432}\u{430}\u{435}\u{442}\u{441}\u{44f}. \u{418}\u{441}\u{43f}\u{43e}\u{43b}\u{44c}\u{437}\u{443}\u{439}\u{442}\u{435} FTP-\u{430}\u{434}\u{440}\u{435}\u{441} \u{434}\u{43b}\u{44f} \(host).")
                            }

                            let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
                            let urlString = "\(scheme)://\(username):\(encodedPassword)@\(cleanHost):\(port)/\(filename)"
                            guard let url = URL(string: urlString) else {
                                                throw ftpError("\u{41d}\u{435}\u{43a}\u{43e}\u{440}\u{440}\u{435}\u{43a}\u{442}\u{43d}\u{44b}\u{439} URL \u{434}\u{43b}\u{44f} \u{437}\u{430}\u{433}\u{440}\u{443}\u{437}\u{43a}\u{438}")
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

                            var lastError: Error = ftpError("\u{41d}\u{435}\u{438}\u{437}\u{432}\u{435}\u{441}\u{442}\u{43d}\u{430}\u{44f} \u{43e}\u{448}\u{438}\u{431}\u{43a}\u{430}")
                            for attempt in 1...3 {
                                                do {
                                                                        let (_, response) = try await session.upload(for: request, from: data)
                                                                        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                                                                                                    throw ftpError("\u{41e}\u{448}\u{438}\u{431}\u{43a}\u{430} \u{441}\u{435}\u{440}\u{432}\u{435}\u{440}\u{430}: HTTP \(httpResp.statusCode)")
                                                                        }
                                                                        return
                                                } catch let error as NSError {
                                                                        lastError = error
                                                                        if error.code == NSURLErrorUserAuthenticationRequired ||
                                                                           error.code == NSURLErrorCancelled {
                                                                                                       throw error
                                                                           }

                                                                        if attempt < 3 {
                                                                                                    try await Task.sleep(nanoseconds: UInt64(Double(attempt) * 2_000_000_000))
                                                                        }
                                                }
                            }
                            throw lastError
            }

            private static func schemeFor(host: String) -> String {
                            let lower = host.lowercased()
                            if lower.hasPrefix("sftp") || lower.contains(".sftp.") { return "sftp" }
                            if lower.hasPrefix("ftps") { return "ftps" }
                            return "ftp"
            }

            private static func cleanedHost(_ host: String) -> String {
                            var h = host
                            for prefix in ["sftp://", "ftps://", "ftp://"] {
                                                if h.lowercased().hasPrefix(prefix) { h = String(h.dropFirst(prefix.count)) }
                            }
                            if h.hasSuffix("/") { h = String(h.dropLast()) }
                            return h
            }

            private static func ftpError(_ message: String) -> NSError {
                            NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            }
}

private class FTPUploadDelegate: NSObject, URLSessionTaskDelegate {
            func urlSession(
                            _ session: URLSession,
                            task: URLSessionTask,
                            didReceive challenge: URLAuthenticationChallenge,
                            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
            ) {
                            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                               let serverTrust = challenge.protectionSpace.serverTrust {
                                                   completionHandler(.useCredential, URLCredential(trust: serverTrust))
                               } else {
                                                   completionHandler(.performDefaultHandling, nil)
                               }
            }
}
