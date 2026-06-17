import Network
import Foundation

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
    
    static func testConnection(host: String, port: Int = 21, username: String, password: String) async throws {
        var ftpHost = host
        if ftpHost.contains("sftp") {
            ftpHost = ftpHost.replacingOccurrences(of: "sftp", with: "ftp")
        } else if ftpHost.contains("ftps") {
            ftpHost = ftpHost.replacingOccurrences(of: "ftps", with: "ftp")
        }
        
        let parameters = NWParameters.tcp
        let customFramerOptions = NWProtocolFramer.Options(definition: FTPESFramer.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(customFramerOptions, at: 0)
        
        let controlConnection = NWConnection(host: NWEndpoint.Host(ftpHost), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: parameters)
        controlConnection.start(queue: DispatchQueue.global())
        
        do {
            try await waitForReady(connection: controlConnection)
            let reader = ConnectionReader(connection: controlConnection)
            
            // 1. Read Banner
            let banner = try await reader.readLine()
            guard banner.hasPrefix("220") else {
                controlConnection.cancel()
                throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка баннера FTP: \(banner)"])
            }
            
            // 2. Send AUTH TLS
            try await sendCommand(connection: controlConnection, cmd: "AUTH TLS\r\n")
            let authResp = try await reader.readLine()
            
            let isTLS: Bool
            if authResp.hasPrefix("234") {
                try await upgradeToTLS(connection: controlConnection)
                isTLS = true
            } else {
                isTLS = false
            }
            
            // 3. Send USER
            try await sendCommand(connection: controlConnection, cmd: "USER \(username)\r\n")
            let userResp = try await reader.readLine()
            guard userResp.hasPrefix("331") || userResp.hasPrefix("230") else {
                controlConnection.cancel()
                throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Пользователь отклонён: \(userResp)"])
            }
            
            // 4. Send PASS if required
            if userResp.hasPrefix("331") {
                try await sendCommand(connection: controlConnection, cmd: "PASS \(password)\r\n")
                let passResp = try await reader.readLine()
                guard passResp.hasPrefix("230") else {
                    controlConnection.cancel()
                    throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка авторизации: \(passResp)"])
                }
            }
            
            // 5. Send PBSZ and PROT if TLS is active
            if isTLS {
                try await sendCommand(connection: controlConnection, cmd: "PBSZ 0\r\n")
                _ = try await reader.readLine()
                try await sendCommand(connection: controlConnection, cmd: "PROT P\r\n")
                _ = try await reader.readLine()
            }
            
            // 6. Send QUIT
            try await sendCommand(connection: controlConnection, cmd: "QUIT\r\n")
            controlConnection.cancel()
        } catch {
            controlConnection.cancel()
            throw error
        }
    }

    static func upload(data: Data, filename: String, host: String, port: Int = 21, username: String, password: String) async throws {
        var ftpHost = host
        if ftpHost.contains("sftp") {
            ftpHost = ftpHost.replacingOccurrences(of: "sftp", with: "ftp")
        } else if ftpHost.contains("ftps") {
            ftpHost = ftpHost.replacingOccurrences(of: "ftps", with: "ftp")
        }
        
        let parameters = NWParameters.tcp
        let customFramerOptions = NWProtocolFramer.Options(definition: FTPESFramer.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(customFramerOptions, at: 0)
        
        let controlConnection = NWConnection(host: NWEndpoint.Host(ftpHost), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: parameters)
        controlConnection.start(queue: DispatchQueue.global())
        
        try await waitForReady(connection: controlConnection)
        let reader = ConnectionReader(connection: controlConnection)
        
        // 1. Read Banner
        let banner = try await reader.readLine()
        guard banner.hasPrefix("220") else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка баннера FTP: \(banner)"])
        }
        
        // 2. Send AUTH TLS
        try await sendCommand(connection: controlConnection, cmd: "AUTH TLS\r\n")
        let authResp = try await reader.readLine()
        
        let isTLS: Bool
        if authResp.hasPrefix("234") {
            try await upgradeToTLS(connection: controlConnection)
            isTLS = true
        } else {
            isTLS = false
        }
        
        // 3. Send USER
        try await sendCommand(connection: controlConnection, cmd: "USER \(username)\r\n")
        let userResp = try await reader.readLine()
        guard userResp.hasPrefix("331") || userResp.hasPrefix("230") else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Пользователь отклонён: \(userResp)"])
        }
        
        // 4. Send PASS if required
        if userResp.hasPrefix("331") {
            try await sendCommand(connection: controlConnection, cmd: "PASS \(password)\r\n")
            let passResp = try await reader.readLine()
            guard passResp.hasPrefix("230") else {
                controlConnection.cancel()
                throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка авторизации: \(passResp)"])
            }
        }
        
        // 5. Send PBSZ and PROT if TLS is active
        if isTLS {
            try await sendCommand(connection: controlConnection, cmd: "PBSZ 0\r\n")
            _ = try await reader.readLine()
            try await sendCommand(connection: controlConnection, cmd: "PROT P\r\n")
            _ = try await reader.readLine()
        }
        
        // 6. Send TYPE I (Binary Mode)
        try await sendCommand(connection: controlConnection, cmd: "TYPE I\r\n")
        let typeResp = try await reader.readLine()
        guard typeResp.hasPrefix("200") else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка установки бинарного режима: \(typeResp)"])
        }
        
        // 7. Send PASV
        try await sendCommand(connection: controlConnection, cmd: "PASV\r\n")
        let pasvResp = try await reader.readLine()
        guard pasvResp.hasPrefix("227") else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка перехода в пассивный режим: \(pasvResp)"])
        }
        
        // Parse IP and Port from 227 Entering Passive Mode (192,168,1,10,192,10)
        let pattern = "\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: pasvResp, range: NSRange(pasvResp.startIndex..., in: pasvResp)),
              let range = Range(match.range(at: 1), in: pasvResp) else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось распарсить ответ PASV: \(pasvResp)"])
        }
        
        let components = String(pasvResp[range]).components(separatedBy: ",")
        guard components.count == 6 else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Некорректный формат адреса PASV"])
        }
        
        let dataIp = components[0...3].joined(separator: ".")
        guard let p1 = Int(components[4]), let p2 = Int(components[5]) else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Некорректный порт PASV"])
        }
        let dataPort = p1 * 256 + p2
        
        // 8. Connect Data Channel (TLS if control connection is TLS)
        let dataParams = isTLS ? NWParameters.tls : NWParameters.tcp
        let dataConnection = NWConnection(host: NWEndpoint.Host(dataIp), port: NWEndpoint.Port(rawValue: UInt16(dataPort))!, using: dataParams)
        dataConnection.start(queue: DispatchQueue.global())
        try await waitForReady(connection: dataConnection)
        
        // 9. Send STOR on Control Channel
        try await sendCommand(connection: controlConnection, cmd: "STOR \(filename)\r\n")
        let storResp = try await reader.readLine()
        guard storResp.hasPrefix("150") || storResp.hasPrefix("125") else {
            dataConnection.cancel()
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка отправки команды STOR: \(storResp)"])
        }
        
        // 10. Send bytes on Data Channel and Close it
        try await send(connection: dataConnection, data: data)
        dataConnection.cancel()
        
        // 11. Read Transfer Complete on Control Channel
        let completeResp = try await reader.readLine()
        guard completeResp.hasPrefix("226") else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка завершения загрузки: \(completeResp)"])
        }
        
        // 12. Send QUIT
        try await sendCommand(connection: controlConnection, cmd: "QUIT\r\n")
        controlConnection.cancel()
    }
    
    private static func upgradeToTLS(connection: NWConnection) async throws {
        let message = NWProtocolFramer.Message(definition: FTPESFramer.definition)
        message["upgradeTLS"] = true
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: nil, contentContext: .init(identifier: "upgrade", metadata: [message]), isComplete: true, completion: .contentProcessed({ error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }))
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
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка кодирования команды"])
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
                    continuation.resume(throwing: NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Соединение отменено"]))
                default:
                    break
                }
            }
        }
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
            
            let message = NWProtocolFramer.Message()
            _ = framer.deliverInputNoCopy(length: parsedCount, message: message, isComplete: true)
        }
        return 0
    }
    
    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        if message["upgradeTLS"] as? Bool == true {
            let tlsOptions = NWProtocolTLS.Options()
            try? framer.prependApplicationProtocol(options: tlsOptions)
            return
        }
        try? framer.writeOutputNoCopy(length: messageLength)
    }
    
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { return true }
    func cleanup(framer: NWProtocolFramer.Instance) {}
}
