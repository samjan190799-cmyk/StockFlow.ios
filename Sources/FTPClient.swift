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
        
        let controlConnection = NWConnection(host: NWEndpoint.Host(ftpHost), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
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
            
            // 2. Send USER
            try await sendCommand(connection: controlConnection, cmd: "USER \(username)\r\n")
            let userResp = try await reader.readLine()
            guard userResp.hasPrefix("331") || userResp.hasPrefix("230") else {
                controlConnection.cancel()
                throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Пользователь отклонён: \(userResp)"])
            }
            
            // 3. Send PASS if required
            if userResp.hasPrefix("331") {
                try await sendCommand(connection: controlConnection, cmd: "PASS \(password)\r\n")
                let passResp = try await reader.readLine()
                guard passResp.hasPrefix("230") else {
                    controlConnection.cancel()
                    throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка авторизации: \(passResp)"])
                }
            }
            
            // 4. Send QUIT
            try await sendCommand(connection: controlConnection, cmd: "QUIT\r\n")
            controlConnection.cancel()
        } catch {
            controlConnection.cancel()
            throw error
        }
    }

    static func upload(data: Data, filename: String, host: String, port: Int = 21, username: String, password: String) async throws {
        let controlConnection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
        controlConnection.start(queue: DispatchQueue.global())
        
        try await waitForReady(connection: controlConnection)
        let reader = ConnectionReader(connection: controlConnection)
        
        // 1. Read Banner
        let banner = try await reader.readLine()
        guard banner.hasPrefix("220") else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка баннера FTP: \(banner)"])
        }
        
        // 2. Send USER
        try await sendCommand(connection: controlConnection, cmd: "USER \(username)\r\n")
        let userResp = try await reader.readLine()
        guard userResp.hasPrefix("331") || userResp.hasPrefix("230") else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Пользователь отклонён: \(userResp)"])
        }
        
        // 3. Send PASS if required
        if userResp.hasPrefix("331") {
            try await sendCommand(connection: controlConnection, cmd: "PASS \(password)\r\n")
            let passResp = try await reader.readLine()
            guard passResp.hasPrefix("230") else {
                controlConnection.cancel()
                throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка авторизации: \(passResp)"])
            }
        }
        
        // 4. Send TYPE I (Binary Mode)
        try await sendCommand(connection: controlConnection, cmd: "TYPE I\r\n")
        let typeResp = try await reader.readLine()
        guard typeResp.hasPrefix("200") else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка установки бинарного режима: \(typeResp)"])
        }
        
        // 5. Send PASV
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
        
        // 6. Connect Data Channel
        let dataConnection = NWConnection(host: NWEndpoint.Host(dataIp), port: NWEndpoint.Port(rawValue: UInt16(dataPort))!, using: .tcp)
        dataConnection.start(queue: DispatchQueue.global())
        try await waitForReady(connection: dataConnection)
        
        // 7. Send STOR on Control Channel
        try await sendCommand(connection: controlConnection, cmd: "STOR \(filename)\r\n")
        let storResp = try await reader.readLine()
        guard storResp.hasPrefix("150") || storResp.hasPrefix("125") else {
            dataConnection.cancel()
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка отправки команды STOR: \(storResp)"])
        }
        
        // 8. Send bytes on Data Channel and Close it
        try await send(connection: dataConnection, data: data)
        dataConnection.cancel()
        
        // 9. Read Transfer Complete on Control Channel
        let completeResp = try await reader.readLine()
        guard completeResp.hasPrefix("226") else {
            controlConnection.cancel()
            throw NSError(domain: "FTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка завершения загрузки: \(completeResp)"])
        }
        
        // 10. Send QUIT
        try await sendCommand(connection: controlConnection, cmd: "QUIT\r\n")
        controlConnection.cancel()
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
