import Foundation
import Network
import Security
import Darwin

// MARK: - FTPClient
// Реализация нативного FTP/FTPS-клиента через сокеты NWConnection.
// Решает проблему неработающего URLSession FTP на iOS 16+.
class FTPClient {
    
    // MARK: - Shared TLS Options for Session Resumption
    private static var _sharedTLSOptions: NWProtocolTLS.Options?
    private static let tlsLock = NSLock()
    
    static func setSharedTLSOptions(_ options: NWProtocolTLS.Options) {
        tlsLock.lock()
        defer { tlsLock.unlock() }
        _sharedTLSOptions = options
    }
    
    static func getSharedTLSOptions() -> NWProtocolTLS.Options? {
        tlsLock.lock()
        defer { tlsLock.unlock() }
        return _sharedTLSOptions
    }
    
    static func clearSharedTLSOptions() {
        tlsLock.lock()
        defer { tlsLock.unlock() }
        _sharedTLSOptions = nil
    }
    
    private class ConnectionReader {
        let connection: NWConnection
        var buffer = Data()
        
        init(connection: NWConnection) {
            self.connection = connection
        }
        
        func readLine(timeout: TimeInterval = 10) async throws -> String {
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    while true {
                        try Task.checkCancellation()
                        
                        if let newlineIndex = self.buffer.firstIndex(of: 10) { // 10 is '\n'
                            let lineData = self.buffer.subdata(in: 0..<newlineIndex + 1)
                            self.buffer.removeSubrange(0..<newlineIndex + 1)
                            if let str = String(data: lineData, encoding: .utf8) {
                                await MainActor.run {
                                    FTPTranscriptLogger.shared.logResponse(str)
                                }
                                return str
                            }
                        }
                        
                        let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                            self.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                                if let error = error {
                                    continuation.resume(throwing: error)
                                } else if let data = data, !data.isEmpty {
                                    continuation.resume(returning: data)
                                } else if isComplete {
                                    continuation.resume(throwing: NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Соединение закрыто сервером"]))
                                } else {
                                    continuation.resume(throwing: NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Соединение закрыто сервером"]))
                                }
                            }
                        }
                        self.buffer.append(chunk)
                    }
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Таймаут ожидания ответа от сервера (\(timeout) сек)"])
                }
                
                do {
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                } catch {
                    group.cancelAll()
                    self.connection.cancel()
                    throw error
                }
            }
        }
    }
    
    // MARK: - Test Connection
    static func testConnection(
        host: String,
        port: Int = 21,
        username: String,
        password: String
    ) async throws {
        clearSharedTLSOptions()
        let cleanHost = cleanedHost(host)
        let scheme = schemeFor(host: host)
        
        if scheme == "sftp" {
            // SFTP check is done via NWConnection port 22 check
            try await checkTCPReachability(host: cleanHost, port: port == 21 ? 22 : port)
            return
        }
        
        let resolvedIp = resolveHost(cleanHost) ?? cleanHost
        await MainActor.run { FTPTranscriptLogger.shared.logResponse("[DEBUG] Resolved IP for Control/Data channels: \(resolvedIp)") }
        
        let parameters = NWParameters.tcp
        let customFramerOptions = NWProtocolFramer.Options(definition: FTPESFramer.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(customFramerOptions, at: 0)
        
        let controlConnection = NWConnection(
            host: NWEndpoint.Host(resolvedIp),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: parameters
        )
        controlConnection.start(queue: DispatchQueue.global())
        
        do {
            try await waitForReady(connection: controlConnection)
            let reader = ConnectionReader(connection: controlConnection)
            
            // 3. Send USER
            do {
                try await sendCommand(connection: controlConnection, cmd: "USER \(username)\r\n")
            } catch {
                throw ftpError("Ошибка при отправке имени пользователя (USER): \(error.localizedDescription)")
            }
            
            let userResp: String
            do {
                userResp = try await reader.readLine()
            } catch {
                throw ftpError("Ошибка при чтении ответа на имя пользователя (USER): \(error.localizedDescription)")
            }
            
            // 4. Send PASS if required
            if userResp.hasPrefix("331") {
                do {
                    try await sendCommand(connection: controlConnection, cmd: "PASS \(password)\r\n")
                } catch {
                    throw ftpError("Ошибка при отправке пароля (PASS): \(error.localizedDescription)")
                }
                
                let passResp: String
                do {
                    passResp = try await reader.readLine()
                } catch {
                    throw ftpError("Ошибка при чтении ответа на пароль (PASS): \(error.localizedDescription)")
                }
                guard passResp.hasPrefix("230") else {
                    controlConnection.cancel()
                    throw ftpError("Неверный логин или пароль (код: \(passResp))")
                }
            } else if !userResp.hasPrefix("230") {
                controlConnection.cancel()
                throw ftpError("Неверный ответ сервера авторизации: \(userResp)")
            }
            
            // 5. Send QUIT
            try? await sendCommand(connection: controlConnection, cmd: "QUIT\r\n")
            controlConnection.cancel()
        } catch {
            controlConnection.cancel()
            throw error
        }
    }
    
    // MARK: - DNS Resolver
    private static func resolveHost(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(host, nil, &hints, &res) == 0 {
            defer { freeaddrinfo(res) }
            var ptr = res
            while ptr != nil {
                let info = ptr!.pointee
                var hostname = [CChar](repeating: 0, count: 1025)
                if getnameinfo(info.ai_addr, info.ai_addrlen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipString = String(cString: hostname)
                    if info.ai_family == AF_INET { // Prefer IPv4
                        return ipString
                    }
                }
                ptr = info.ai_next
            }
            if let info = res?.pointee {
                 var hostname = [CChar](repeating: 0, count: 1025)
                 if getnameinfo(info.ai_addr, info.ai_addrlen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                     return String(cString: hostname)
                 }
            }
        }
        return nil
    }
    
    // MARK: - Upload
    static func upload(
        data: Data,
        filename: String,
        host: String,
        port: Int = 21,
        username: String,
        password: String,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        clearSharedTLSOptions()
        let cleanHost = cleanedHost(host)
        let resolvedIp = resolveHost(cleanHost) ?? cleanHost
        
        await MainActor.run { FTPTranscriptLogger.shared.logResponse("[DEBUG] Resolved IP for Control/Data channels: \(resolvedIp)") }
        
        let scheme = schemeFor(host: host)
        
        if scheme == "sftp" {
            throw ftpError("SFTP не поддерживается. Используйте FTP-хост для \(host).")
        }
        
        let parameters = NWParameters.tcp
        let customFramerOptions = NWProtocolFramer.Options(definition: FTPESFramer.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(customFramerOptions, at: 0)
        
        let controlConnection = NWConnection(
            host: NWEndpoint.Host(resolvedIp),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: parameters
        )
        controlConnection.start(queue: DispatchQueue.global())
        
        var dataConnection: NWConnection? = nil
        do {
            try await waitForReady(connection: controlConnection)
            let reader = ConnectionReader(connection: controlConnection)
            
            // 3. Send USER
            do {
                try await sendCommand(connection: controlConnection, cmd: "USER \(username)\r\n")
            } catch {
                throw ftpError("Ошибка при отправке имени пользователя (USER): \(error.localizedDescription)")
            }
            
            let userResp: String
            do {
                userResp = try await reader.readLine()
            } catch {
                throw ftpError("Ошибка при чтении ответа на имя пользователя (USER): \(error.localizedDescription)")
            }
            
            // 4. Send PASS if required
            if userResp.hasPrefix("331") {
                do {
                    try await sendCommand(connection: controlConnection, cmd: "PASS \(password)\r\n")
                } catch {
                    throw ftpError("Ошибка при отправке пароля (PASS): \(error.localizedDescription)")
                }
                
                let passResp: String
                do {
                    passResp = try await reader.readLine()
                } catch {
                    throw ftpError("Ошибка при чтении ответа на пароль (PASS): \(error.localizedDescription)")
                }
                guard passResp.hasPrefix("230") else {
                    controlConnection.cancel()
                    throw ftpError("Неверный логин или пароль (код: \(passResp))")
                }
            } else if !userResp.hasPrefix("230") {
                controlConnection.cancel()
                throw ftpError("Ошибка авторизации: \(userResp)")
            }
            
            // 5. Send PBSZ and PROT (используем PROT C для обхода проблемы TLS Session Resumption)
            var useTlsOnDataChannel = false
            do {
                try await sendCommand(connection: controlConnection, cmd: "PBSZ 0\r\n")
                _ = try await reader.readLine()
                
                try await sendCommand(connection: controlConnection, cmd: "PROT C\r\n")
                let protResp = try await reader.readLine()
                if !protResp.hasPrefix("200") {
                    print("FTPClient: PROT C отклонен (\(protResp)), используем PROT P")
                    try await sendCommand(connection: controlConnection, cmd: "PROT P\r\n")
                    _ = try await reader.readLine()
                    useTlsOnDataChannel = true
                } else {
                    print("FTPClient: Успешно установлен PROT C (открытый канал данных)")
                }
            } catch {
                throw ftpError("Ошибка при настройке параметров защиты (PBSZ/PROT): \(error.localizedDescription)")
            }
            
            // 6. Send TYPE I (Binary Mode)
            do {
                try await sendCommand(connection: controlConnection, cmd: "TYPE I\r\n")
            } catch {
                throw ftpError("Ошибка при отправке команды TYPE I: \(error.localizedDescription)")
            }
            
            let typeResp: String
            do {
                typeResp = try await reader.readLine()
            } catch {
                throw ftpError("Ошибка при чтении ответа на TYPE I: \(error.localizedDescription)")
            }
            guard typeResp.hasPrefix("200") else {
                controlConnection.cancel()
                throw ftpError("Ошибка установки бинарного режима: \(typeResp)")
            }
            
            // 7. Establish Data Connection
            var connectedDataChannel: NWConnection? = nil
            var dataPort: Int = 0
            var dataIp: String = cleanHost
            
            // Сначала пробуем EPSV с коротким таймаутом
            var epsvSuccess = false
            do {
                try await sendCommand(connection: controlConnection, cmd: "EPSV\r\n")
                let epsvResp = try await reader.readLine()
                
                if epsvResp.hasPrefix("229") {
                    let pattern = "\\(\\|\\|\\|(\\d+)\\|\\)"
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: epsvResp, range: NSRange(epsvResp.startIndex..., in: epsvResp)),
                       let range = Range(match.range(at: 1), in: epsvResp),
                       let port = Int(epsvResp[range]) {
                        dataPort = port
                        await MainActor.run { FTPTranscriptLogger.shared.logResponse("[DEBUG] EPSV port: \(dataPort)") }
                        
                        let dataHostEndpoint = NWEndpoint.Host(resolvedIp)
                        await MainActor.run { FTPTranscriptLogger.shared.logResponse("[DEBUG] Attempting EPSV connection to \(resolvedIp):\(dataPort)...") }
                        
                        let dataParameters = setupDataParameters(useTls: useTlsOnDataChannel, cleanHost: cleanHost)
                        let conn = NWConnection(host: dataHostEndpoint, port: NWEndpoint.Port(rawValue: UInt16(dataPort))!, using: dataParameters)
                        conn.start(queue: DispatchQueue.global())
                        
                        // Пробуем подключиться с коротким таймаутом 6 секунд
                        try await waitForReady(connection: conn, timeout: 6)
                        connectedDataChannel = conn
                        epsvSuccess = true
                        await MainActor.run { FTPTranscriptLogger.shared.logResponse("[DEBUG] EPSV connection established successfully.") }
                    }
                }
            } catch {
                await MainActor.run { FTPTranscriptLogger.shared.logResponse("[DEBUG] EPSV connection failed or timed out: \(error.localizedDescription). Falling back to PASV...") }
            }
            
            // Если EPSV не удался, пробуем PASV
            if !epsvSuccess {
                do {
                    try await sendCommand(connection: controlConnection, cmd: "PASV\r\n")
                    let pasvResp = try await reader.readLine()
                    
                    guard pasvResp.hasPrefix("227") else {
                        throw ftpError("Ошибка пассивного режима: \(pasvResp)")
                    }
                    
                    let pattern = "\\(([^)]+)\\)"
                    guard let regex = try? NSRegularExpression(pattern: pattern),
                          let match = regex.firstMatch(in: pasvResp, range: NSRange(pasvResp.startIndex..., in: pasvResp)),
                          let range = Range(match.range(at: 1), in: pasvResp) else {
                        throw ftpError("Ошибка разбора ответа PASV: \(pasvResp)")
                    }
                    
                    let components = String(pasvResp[range]).components(separatedBy: ",")
                    guard components.count == 6 else {
                        throw ftpError("Ошибка формата ответа PASV")
                    }
                    
                    let parsedIp = components[0...3].joined(separator: ".")
                    dataIp = parsedIp
                    if dataIp.hasPrefix("10.") || dataIp.hasPrefix("192.168.") || dataIp.hasPrefix("172.") {
                        dataIp = cleanHost
                    }
                    
                    guard let p1 = Int(components[4]), let p2 = Int(components[5]) else {
                        throw ftpError("Ошибка разбора порта PASV")
                    }
                    dataPort = p1 * 256 + p2
                    
                    let dataHostEndpoint: NWEndpoint.Host
                    if dataIp == cleanHost || dataIp == resolvedIp {
                        dataHostEndpoint = NWEndpoint.Host(resolvedIp)
                    } else {
                        dataHostEndpoint = NWEndpoint.Host(dataIp)
                    }
                    
                    await MainActor.run { FTPTranscriptLogger.shared.logResponse("[DEBUG] Attempting PASV connection to \(dataIp) [\(resolvedIp)]:\(dataPort)...") }
                    
                    let dataParameters = setupDataParameters(useTls: useTlsOnDataChannel, cleanHost: cleanHost)
                    let conn = NWConnection(host: dataHostEndpoint, port: NWEndpoint.Port(rawValue: UInt16(dataPort))!, using: dataParameters)
                    conn.start(queue: DispatchQueue.global())
                    
                    try await waitForReady(connection: conn, timeout: 20)
                    connectedDataChannel = conn
                    await MainActor.run { FTPTranscriptLogger.shared.logResponse("[DEBUG] PASV connection established successfully.") }
                } catch {
                    controlConnection.cancel()
                    throw ftpError("Не удалось установить соединение через EPSV и PASV: \(error.localizedDescription)")
                }
            }
            
            guard let conn = connectedDataChannel else {
                controlConnection.cancel()
                throw ftpError("Не удалось инициализировать канал данных")
            }
            dataConnection = conn
            
            // 9. Send STOR on Control Channel
            do {
                try await sendCommand(connection: controlConnection, cmd: "STOR \(filename)\r\n")
            } catch {
                throw ftpError("Ошибка при отправке команды STOR: \(error.localizedDescription)")
            }
            
            let storResp: String
            do {
                storResp = try await reader.readLine()
            } catch {
                throw ftpError("Ошибка при чтении ответа на STOR: \(error.localizedDescription)")
            }
            guard storResp.hasPrefix("150") || storResp.hasPrefix("125") else {
                conn.cancel()
                controlConnection.cancel()
                throw ftpError("Ошибка начала передачи STOR: \(storResp)")
            }
            
            // 10. Send bytes on Data Channel and Close it
            do {
                try await send(connection: conn, data: data, progress: progress)
            } catch {
                throw ftpError("Ошибка при передаче данных файла: \(error.localizedDescription)")
            }
            conn.cancel()
            dataConnection = nil
            
            // 11. Read Transfer Complete on Control Channel
            let completeResp: String
            do {
                completeResp = try await reader.readLine()
            } catch {
                throw ftpError("Ошибка при чтении подтверждения передачи: \(error.localizedDescription)")
            }
            guard completeResp.hasPrefix("226") else {
                controlConnection.cancel()
                throw ftpError("Ошибка завершения передачи: \(completeResp)")
            }
            
            // 12. Send QUIT
            try? await sendCommand(connection: controlConnection, cmd: "QUIT\r\n")
            controlConnection.cancel()
        } catch {
            dataConnection?.cancel()
            controlConnection.cancel()
            throw error
        }
    }
    
    private static func setupDataParameters(useTls: Bool, cleanHost: String) -> NWParameters {
        if useTls {
            if let sharedOptions = getSharedTLSOptions() {
                print("FTPClient: Использование общих TLS параметров от контрольного канала для Session Resumption")
                return NWParameters(tls: sharedOptions)
            }
            
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { (_, _, completionHandler) in
                completionHandler(true)
            }, DispatchQueue.global())
            sec_protocol_options_set_tls_resumption_enabled(tlsOptions.securityProtocolOptions, true)
            sec_protocol_options_set_tls_tickets_enabled(tlsOptions.securityProtocolOptions, true)
            sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, cleanHost)
            return NWParameters(tls: tlsOptions)
        } else {
            return NWParameters.tcp
        }
    }

    private static func upgradeToTLS(connection: NWConnection, host: String) async throws {
        let message = NWProtocolFramer.Message(definition: FTPESFramer.definition)
        message["upgradeTLS"] = true
        message["peerName"] = host
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: nil,
                contentContext: .init(identifier: "upgrade", metadata: [message]),
                isComplete: true,
                completion: .contentProcessed({ error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            )
        }
    }
    
    private static func send(connection: NWConnection, data: Data, progress: ((Double) -> Void)? = nil) async throws {
        let chunkSize = 65536
        var offset = 0
        let total = data.count
        
        while offset < total {
            let end = min(offset + chunkSize, total)
            let chunk = data.subdata(in: offset..<end)
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: chunk, completion: .contentProcessed({ error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }))
            }
            
            offset = end
            if total > 0 {
                progress?(Double(offset) / Double(total))
            }
        }
    }
    
    private static func sendCommand(connection: NWConnection, cmd: String) async throws {
        await MainActor.run {
            FTPTranscriptLogger.shared.logCommand(cmd)
        }
        guard let data = cmd.data(using: .utf8) else {
            throw ftpError("Ошибка кодирования команды")
        }
        try await send(connection: connection, data: data)
    }
    
    private static func waitForReady(connection: NWConnection, timeout: TimeInterval = 10) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let state = connection.state
                    if state == .ready {
                        continuation.resume()
                        return
                    } else if case .failed(let error) = state {
                        continuation.resume(throwing: error)
                        return
                    } else if state == .cancelled {
                        continuation.resume(throwing: ftpError("Соединение отменено"))
                        return
                    }
                    
                    connection.stateUpdateHandler = { newState in
                        switch newState {
                        case .ready:
                            connection.stateUpdateHandler = nil
                            continuation.resume()
                        case .failed(let error):
                            connection.stateUpdateHandler = nil
                            continuation.resume(throwing: error)
                        case .cancelled:
                            connection.stateUpdateHandler = nil
                            continuation.resume(throwing: ftpError("Соединение отменено"))
                        default:
                            break
                        }
                    }
                }
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ftpError("Превышено время ожидания готовности подключения (\(timeout) сек)")
            }
            
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                connection.cancel()
                throw error
            }
        }
    }
    
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
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["sftp://", "ftps://", "ftp://"] {
            if h.lowercased().hasPrefix(prefix) {
                h = String(h.dropFirst(prefix.count))
            }
        }
        if h.hasSuffix("/") { h = String(h.dropLast()) }
        return h
    }

    private static func ftpError(_ message: String) -> NSError {
        NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - FTPES (Explicit TLS) Framer
class FTPESFramer: NWProtocolFramerImplementation {
    static let label = "FTPESFramer"
    static let definition = NWProtocolFramer.Definition(implementation: FTPESFramer.self)
    
    enum State {
        case waitingForBanner
        case waitingForAuthTLS
        case completed
    }
    
    private var state = State.waitingForBanner
    private var peerName: String?
    
    required init(framer: NWProtocolFramer.Instance) {}
    
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        print("FTPESFramer: start() вызвана, возвращаем .willMarkReady")
        return .willMarkReady
    }
    
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var parsedLine: String? = nil
            var lineLength = 0
            
            let success = framer.parseInput(minimumIncompleteLength: 1, maximumLength: 65536) { buffer, _ in
                guard let buffer = buffer else { return 0 }
                if let index = buffer.firstIndex(of: 10) { // 10 is '\n'
                    let count = index + 1
                    let lineData = Data(buffer[0..<count])
                    parsedLine = String(data: lineData, encoding: .utf8)
                    lineLength = count
                    return count
                }
                return 0
            }
            
            guard success, let line = parsedLine else {
                return 1 // Ждем еще данные
            }
            
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            print("FTPESFramer [Input]: \(trimmedLine)")
            
            switch state {
            case .waitingForBanner:
                if line.hasPrefix("220 ") {
                    print("FTPESFramer: Получено приветствие 220, отправляем AUTH TLS...")
                    if let authData = "AUTH TLS\r\n".data(using: .utf8) {
                        framer.writeOutput(data: authData)
                    }
                    state = .waitingForAuthTLS
                }
            case .waitingForAuthTLS:
                let code = line.prefix(3)
                if code == "234" {
                    print("FTPESFramer: Получен ответ 234. Выполняем переход на TLS...")
                    let tlsOptions = NWProtocolTLS.Options()
                    sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
                    sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { (_, _, completionHandler) in
                        print("FTPESFramer (Control): Блок верификации TLS вызван")
                        completionHandler(true)
                    }, DispatchQueue.global())
                    sec_protocol_options_set_tls_resumption_enabled(tlsOptions.securityProtocolOptions, true)
                    sec_protocol_options_set_tls_tickets_enabled(tlsOptions.securityProtocolOptions, true)
                    if let peer = self.peerName {
                        sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, peer)
                    }
                    
                    // Сохраняем общие TLS параметры
                    FTPClient.setSharedTLSOptions(tlsOptions)
                    
                    do {
                        try framer.prependApplicationProtocol(options: tlsOptions)
                        print("FTPESFramer: TLS протокол успешно добавлен.")
                    } catch {
                        print("FTPESFramer: Ошибка при prependApplicationProtocol: \(error.localizedDescription)")
                        framer.markFailed(error: NWError.posix(.ECONNABORTED))
                        return 0
                    }
                    
                    state = .completed
                    framer.passThroughInput()
                    framer.passThroughOutput()
                    framer.markReady()
                    return 0
                } else if code.count == 3 && code != "220" {
                    print("FTPESFramer: Сервер отклонил TLS (код: \(code)). Продолжаем без шифрования.")
                    state = .completed
                    framer.passThroughInput()
                    framer.passThroughOutput()
                    framer.markReady()
                    return 0
                }
            case .completed:
                // Передаем данные наверх (этот кейс не должен вызываться после passThrough)
                let message = NWProtocolFramer.Message(definition: FTPESFramer.definition)
                _ = framer.deliverInput(data: line.data(using: .utf8) ?? Data(), message: message, isComplete: true)
            }
        }
    }
    
    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        if let peer = message["peerName"] as? String {
            self.peerName = peer
        }
        try? framer.writeOutputNoCopy(length: messageLength)
    }
    
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { return true }
    func cleanup(framer: NWProtocolFramer.Instance) {}
}
