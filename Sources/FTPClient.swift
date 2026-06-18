import Foundation
import Network
import Security

// MARK: - FTPClient
// Реализация нативного FTP/FTPS-клиента через сокеты NWConnection.
// Решает проблему неработающего URLSession FTP на iOS 16+.
class FTPClient {
    
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
                                return str
                            }
                        }
                        
                        let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                            self.connection.receiveMessage { data, _, _, error in
                                if let error = error {
                                    continuation.resume(throwing: error)
                                } else if let data = data {
                                    continuation.resume(returning: data)
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
        let cleanHost = cleanedHost(host)
        let scheme = schemeFor(host: host)
        
        if scheme == "sftp" {
            // SFTP check is done via NWConnection port 22 check
            try await checkTCPReachability(host: cleanHost, port: port == 21 ? 22 : port)
            return
        }
        
        let parameters = NWParameters.tcp
        let customFramerOptions = NWProtocolFramer.Options(definition: FTPESFramer.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(customFramerOptions, at: 0)
        
        let controlConnection = NWConnection(
            host: NWEndpoint.Host(cleanHost),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: parameters
        )
        controlConnection.start(queue: DispatchQueue.global())
        
        do {
            try await waitForReady(connection: controlConnection)
            let reader = ConnectionReader(connection: controlConnection)
            
            // 1. Read Banner
            let banner: String
            do {
                banner = try await reader.readLine()
            } catch {
                throw ftpError("Ошибка при чтении приветствия сервера (Banner): \(error.localizedDescription)")
            }
            guard banner.hasPrefix("220") else {
                controlConnection.cancel()
                throw ftpError("Ошибка FTP (неверное приветствие): \(banner)")
            }
            
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
        
        if scheme == "sftp" {
            throw ftpError("SFTP не поддерживается. Используйте FTP-хост для \(host).")
        }
        
        let parameters = NWParameters.tcp
        let customFramerOptions = NWProtocolFramer.Options(definition: FTPESFramer.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(customFramerOptions, at: 0)
        
        let controlConnection = NWConnection(
            host: NWEndpoint.Host(cleanHost),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: parameters
        )
        controlConnection.start(queue: DispatchQueue.global())
        
        var dataConnection: NWConnection? = nil
        do {
            try await waitForReady(connection: controlConnection)
            let reader = ConnectionReader(connection: controlConnection)
            
            // 1. Read Banner
            let banner: String
            do {
                banner = try await reader.readLine()
            } catch {
                throw ftpError("Ошибка при чтении приветствия сервера (Banner): \(error.localizedDescription)")
            }
            guard banner.hasPrefix("220") else {
                controlConnection.cancel()
                throw ftpError("Ошибка FTP (неверное приветствие): \(banner)")
            }
            
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
            
            // 5. Send PBSZ and PROT (устанавливаем PROT P — защищенный канал данных)
            do {
                try await sendCommand(connection: controlConnection, cmd: "PBSZ 0\r\n")
                _ = try await reader.readLine()
                
                try await sendCommand(connection: controlConnection, cmd: "PROT P\r\n")
                _ = try await reader.readLine()
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
            
            // 7. Send PASV
            do {
                try await sendCommand(connection: controlConnection, cmd: "PASV\r\n")
            } catch {
                throw ftpError("Ошибка при отправке команды PASV: \(error.localizedDescription)")
            }
            
            let pasvResp: String
            do {
                pasvResp = try await reader.readLine()
            } catch {
                throw ftpError("Ошибка при чтении ответа на PASV: \(error.localizedDescription)")
            }
            guard pasvResp.hasPrefix("227") else {
                controlConnection.cancel()
                throw ftpError("Ошибка пассивного режима: \(pasvResp)")
            }
            
            // Parse IP and Port from 227 Entering Passive Mode (192,168,1,10,192,10)
            let pattern = "\\(([^)]+)\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: pasvResp, range: NSRange(pasvResp.startIndex..., in: pasvResp)),
                  let range = Range(match.range(at: 1), in: pasvResp) else {
                controlConnection.cancel()
                throw ftpError("Ошибка разбора ответа PASV: \(pasvResp)")
            }
            
            let components = String(pasvResp[range]).components(separatedBy: ",")
            guard components.count == 6 else {
                controlConnection.cancel()
                throw ftpError("Ошибка формата ответа PASV")
            }
            
            let dataIp = components[0...3].joined(separator: ".")
            guard let p1 = Int(components[4]), let p2 = Int(components[5]) else {
                controlConnection.cancel()
                throw ftpError("Ошибка разбора порта PASV")
            }
            let dataPort = p1 * 256 + p2
            
            // 8. Connect Data Channel (используем TLS)
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
            sec_protocol_options_set_max_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { (_, _, completionHandler) in
                print("FTPClient (Data): Блок верификации TLS вызван")
                completionHandler(true)
            }, DispatchQueue.main)
            
            // Включаем возобновление TLS-сессий для обхода ошибок TLS Session Resumption, если сервер требует
            sec_protocol_options_set_tls_resumption_enabled(tlsOptions.securityProtocolOptions, true)
            
            let dataParameters = NWParameters(tls: tlsOptions)
            
            let conn = NWConnection(
                host: NWEndpoint.Host(dataIp),
                port: NWEndpoint.Port(rawValue: UInt16(dataPort))!,
                using: dataParameters
            )
            dataConnection = conn
            conn.start(queue: DispatchQueue.global())
            do {
                try await waitForReady(connection: conn)
            } catch {
                throw ftpError("Ошибка при открытии канала данных: \(error.localizedDescription)")
            }
            
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
                try await send(connection: conn, data: data)
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
    
    // MARK: - Private Helpers
    
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
    
    private static func send(connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed({ error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }))
        }
    }
    
    private static func sendCommand(connection: NWConnection, cmd: String) async throws {
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
    
    required init(framer: NWProtocolFramer.Instance) {}
    
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        return .ready
    }
    
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var parsedData: Data? = nil
            let success = framer.parseInput(minimumIncompleteLength: 1, maximumLength: 65536) { buffer, _ in
                guard let buffer = buffer, buffer.count > 0 else { return 0 }
                parsedData = Data(buffer)
                return buffer.count
            }
            guard success, let data = parsedData else {
                return 1
            }
            
            let message = NWProtocolFramer.Message(definition: FTPESFramer.definition)
            _ = framer.deliverInput(data: data, message: message, isComplete: true)
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
                    sec_protocol_options_set_max_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
                    sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { (_, _, completionHandler) in
                        print("FTPESFramer (Control): Блок верификации TLS вызван")
                        completionHandler(true)
                    }, DispatchQueue.main)
                    
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
        try? framer.writeOutputNoCopy(length: messageLength)
    }
    
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { return true }
    func cleanup(framer: NWProtocolFramer.Instance) {}
}
