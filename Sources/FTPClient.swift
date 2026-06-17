import Foundation
import Network

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
        
        func readLine() async throws -> String {
            while true {
                if let newlineIndex = buffer.firstIndex(of: 10) { // 10 is '\n'
                    let lineData = buffer.subdata(in: 0..<newlineIndex + 1)
                    buffer.removeSubrange(0..<newlineIndex + 1)
                    if let str = String(data: lineData, encoding: .utf8) {
                        return str
                    }
                }
                
                let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let data = data {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Соединение закрыто сервером"]))
                        }
                    }
                }
                buffer.append(chunk)
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
            let banner = try await reader.readLine()
            guard banner.hasPrefix("220") else {
                controlConnection.cancel()
                throw ftpError("Ошибка FTP: \(banner)")
            }
            
            // 2. Send AUTH TLS
            try await sendCommand(connection: controlConnection, cmd: "AUTH TLS\r\n")
            let authResp = try await reader.readLine()
            
            let isTLS = authResp.hasPrefix("234")
            if isTLS {
                try await upgradeToTLS(connection: controlConnection)
            }
            
            // 3. Send USER
            try await sendCommand(connection: controlConnection, cmd: "USER \(username)\r\n")
            let userResp = try await reader.readLine()
            
            // 4. Send PASS if required
            if userResp.hasPrefix("331") {
                try await sendCommand(connection: controlConnection, cmd: "PASS \(password)\r\n")
                let passResp = try await reader.readLine()
                guard passResp.hasPrefix("230") else {
                    controlConnection.cancel()
                    throw ftpError("Неверный логин или пароль")
                }
            } else if !userResp.hasPrefix("230") {
                controlConnection.cancel()
                throw ftpError("Неверный ответ сервера авторизации: \(userResp)")
            }
            
            // 5. Send QUIT
            try await sendCommand(connection: controlConnection, cmd: "QUIT\r\n")
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
        
        do {
            try await waitForReady(connection: controlConnection)
            let reader = ConnectionReader(connection: controlConnection)
            
            // 1. Read Banner
            let banner = try await reader.readLine()
            guard banner.hasPrefix("220") else {
                controlConnection.cancel()
                throw ftpError("Ошибка FTP: \(banner)")
            }
            
            // 2. Send AUTH TLS
            try await sendCommand(connection: controlConnection, cmd: "AUTH TLS\r\n")
            let authResp = try await reader.readLine()
            
            let isTLS = authResp.hasPrefix("234")
            if isTLS {
                try await upgradeToTLS(connection: controlConnection)
            }
            
            // 3. Send USER
            try await sendCommand(connection: controlConnection, cmd: "USER \(username)\r\n")
            let userResp = try await reader.readLine()
            
            // 4. Send PASS if required
            if userResp.hasPrefix("331") {
                try await sendCommand(connection: controlConnection, cmd: "PASS \(password)\r\n")
                let passResp = try await reader.readLine()
                guard passResp.hasPrefix("230") else {
                    controlConnection.cancel()
                    throw ftpError("Неверный логин или пароль")
                }
            } else if !userResp.hasPrefix("230") {
                controlConnection.cancel()
                throw ftpError("Ошибка авторизации: \(userResp)")
            }
            
            // 5. Send PBSZ and PROT (устанавливаем PROT C — незашифрованный канал данных)
            // Это решает проблему отсутствия TLS Session Resumption в NWConnection (ошибка NWError 53)
            if isTLS {
                try await sendCommand(connection: controlConnection, cmd: "PBSZ 0\r\n")
                _ = try await reader.readLine()
                
                try await sendCommand(connection: controlConnection, cmd: "PROT C\r\n")
                _ = try await reader.readLine()
            }
            
            // 6. Send TYPE I (Binary Mode)
            try await sendCommand(connection: controlConnection, cmd: "TYPE I\r\n")
            let typeResp = try await reader.readLine()
            guard typeResp.hasPrefix("200") else {
                controlConnection.cancel()
                throw ftpError("Ошибка установки бинарного режима: \(typeResp)")
            }
            
            // 7. Send PASV
            try await sendCommand(connection: controlConnection, cmd: "PASV\r\n")
            let pasvResp = try await reader.readLine()
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
            
            // 8. Connect Data Channel (всегда plain TCP, так как мы отправили PROT C)
            let dataConnection = NWConnection(
                host: NWEndpoint.Host(dataIp),
                port: NWEndpoint.Port(rawValue: UInt16(dataPort))!,
                using: .tcp
            )
            dataConnection.start(queue: DispatchQueue.global())
            try await waitForReady(connection: dataConnection)
            
            // 9. Send STOR on Control Channel
            try await sendCommand(connection: controlConnection, cmd: "STOR \(filename)\r\n")
            let storResp = try await reader.readLine()
            guard storResp.hasPrefix("150") || storResp.hasPrefix("125") else {
                dataConnection.cancel()
                controlConnection.cancel()
                throw ftpError("Ошибка начала передачи STOR: \(storResp)")
            }
            
            // 10. Send bytes on Data Channel and Close it
            try await send(connection: dataConnection, data: data)
            dataConnection.cancel()
            
            // 11. Read Transfer Complete on Control Channel
            let completeResp = try await reader.readLine()
            guard completeResp.hasPrefix("226") else {
                controlConnection.cancel()
                throw ftpError("Ошибка завершения передачи: \(completeResp)")
            }
            
            // 12. Send QUIT
            try await sendCommand(connection: controlConnection, cmd: "QUIT\r\n")
            controlConnection.cancel()
        } catch {
            controlConnection.cancel()
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    private static func upgradeToTLS(connection: NWConnection) async throws {
        let message = NWProtocolFramer.Message(definition: FTPESFramer.definition)
        message["upgradeTLS"] = true
        
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
    
    private static func waitForReady(connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
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
        var h = host
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
            var parsedCount = 0
            let success = framer.parseInput(minimumIncompleteLength: 1, maximumLength: 65536) { buffer in
                guard let buffer = buffer else { return 0 }
                parsedCount = buffer.count
                return buffer.count
            }
            guard success && parsedCount > 0 else { break }
            
            let message = NWProtocolFramer.Message(definition: FTPESFramer.definition)
            _ = framer.deliverInputNoCopy(length: parsedCount, message: message, isComplete: true)
        }
        return 0
    }
    
    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        if message["upgradeTLS"] as? Bool == true {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { (_, _, completionHandler) in
                completionHandler(true)
            }, DispatchQueue.global())
            
            try? framer.prependApplicationProtocol(options: tlsOptions)
            return
        }
        try? framer.writeOutputNoCopy(length: messageLength)
    }
    
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { return true }
    func cleanup(framer: NWProtocolFramer.Instance) {}
}
