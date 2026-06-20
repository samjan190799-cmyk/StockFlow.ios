import Foundation
import Security
import CommonCrypto

// MARK: - FTPSecureClient
// Нативный FTPS-клиент на базе BSD-сокетов + SecureTransport.
//
// ЗАЧЕМ: Network.framework (NWConnection/NWProtocolTLS) кеширует TLS-сессии
// по ключу (хост, порт). Контрольный канал FTPS работает на порту 21,
// а канал данных — на случайном порту. iOS считает их разными серверами
// и НЕ передаёт TLS Session Ticket. Shutterstock (AWS Transfer Family)
// жёстко требует Session Resumption → рукопожатие зависает → таймаут.
//
// РЕШЕНИЕ: SecureTransport + SSLSetPeerID() — вручную назначаем одинаковый
// идентификатор сессии обоим каналам. SecureTransport находит кешированную
// сессию и передаёт Session Ticket в ClientHello канала данных.
//
// SecureTransport помечен Apple как deprecated с iOS 13, но полностью
// работоспособен на iOS 16–18. Apple не удалила эти API из SDK.

class FTPSecureClient {

    // MARK: - Public Upload API

    /// Загрузка файла по FTPS (Explicit TLS) с поддержкой Session Resumption.
    /// Полностью работает на устройстве без ПК.
    static func upload(
        data: Data,
        filename: String,
        host: String,
        port: Int = 21,
        username: String,
        password: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // Блокирующие сокеты выполняются в фоновом потоке
        try await Task.detached(priority: .userInitiated) {
            try Self.performUpload(
                data: data,
                filename: filename,
                host: host,
                port: port,
                username: username,
                password: password,
                progress: progress
            )
        }.value
    }

    // MARK: - Core Upload Logic (выполняется в фоновом потоке)

    private static func performUpload(
        data: Data,
        filename: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        progress: (@Sendable (Double) -> Void)?
    ) throws {
        let cleanHost = cleanedHost(host)
        let resolvedIp = resolveHost(cleanHost) ?? cleanHost

        logMsg("[SecureTransport] Подключение к \(cleanHost) [\(resolvedIp)]:\(port)")

        // Логируем хэш исходных данных для контроля целостности
        let originalSha256 = sha256String(for: data)
        logMsg("[Diagnostic] Исходный файл: \(filename), размер: \(data.count) байт, SHA-256: \(originalSha256)")

        // Уникальный PeerID для общего кеша TLS-сессий между каналами
        let peerId = "ftps-\(cleanHost)".data(using: .utf8)!

        // === ШАГ 1: TCP подключение к контрольному каналу ===
        let controlSock = try tcpConnect(host: resolvedIp, port: port, timeoutSec: 15)
        setSocketTimeout(controlSock, seconds: 15)
        setNoSigPipe(controlSock)

        var controlSSL: SSLContext?
        var dataSock: Int32 = -1
        var dataSSL: SSLContext?

        // Гарантированная очистка ресурсов (LIFO: data → control)
        defer { Darwin.close(controlSock) }
        defer { if let ssl = controlSSL { secureSSLClose(context: ssl, sock: controlSock); controlSSL = nil } }
        defer { if dataSock >= 0 { Darwin.close(dataSock); dataSock = -1 } }
        defer { if let ssl = dataSSL { secureSSLClose(context: ssl, sock: dataSock); dataSSL = nil } }

        // === ШАГ 2: Чтение баннера (plain text) ===
        var plainBuf = Data()
        let banner = try plainReadResponse(sock: controlSock, buffer: &plainBuf)
        guard banner.hasPrefix("220") else {
            throw ftpError("Неожиданный баннер сервера: \(banner)")
        }

        // === ШАГ 3: AUTH TLS ===
        try plainWrite(sock: controlSock, cmd: "AUTH TLS\r\n")
        let authResp = try plainReadResponse(sock: controlSock, buffer: &plainBuf)
        guard authResp.hasPrefix("234") else {
            throw ftpError("AUTH TLS отклонен сервером: \(authResp)")
        }

        // === ШАГ 4: Upgrade контрольного канала на TLS ===
        let requireValidCert = cleanHost.contains("shutterstock.com") || cleanHost.contains("gettyimages.com")
        controlSSL = try createSSLContext(sock: controlSock, peerName: cleanHost, peerId: peerId, requireValidCertificate: requireValidCert)
        try performSSLHandshake(context: controlSSL!, requireValidCertificate: requireValidCert)
        logMsg("[SecureTransport] ✅ TLS handshake контрольного канала завершён")

        // === ШАГ 5: Авторизация ===
        var sslBuf = Data()
        try sslWriteCmd(context: controlSSL!, cmd: "USER \(username)\r\n")
        let userResp = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)

        if userResp.hasPrefix("331") {
            try sslWriteCmd(context: controlSSL!, cmd: "PASS \(password)\r\n")
            let passResp = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)
            guard passResp.hasPrefix("230") else {
                throw ftpError("Неверный логин или пароль: \(passResp)")
            }
        } else if !userResp.hasPrefix("230") {
            throw ftpError("Ошибка авторизации: \(userResp)")
        }
        logMsg("[SecureTransport] ✅ Авторизация успешна")

        // === ШАГ 6: PBSZ + PROT P ===
        try sslWriteCmd(context: controlSSL!, cmd: "PBSZ 0\r\n")
        _ = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)

        // Сначала пробуем PROT C (открытый канал данных) — проще, не требует Session Resumption
        try sslWriteCmd(context: controlSSL!, cmd: "PROT C\r\n")
        let protCResp = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)
        let useTlsDataChannel: Bool
        if protCResp.hasPrefix("200") {
            logMsg("[SecureTransport] PROT C принят — канал данных без шифрования")
            useTlsDataChannel = false
        } else {
            logMsg("[SecureTransport] PROT C отклонен (\(protCResp)), используем PROT P")
            try sslWriteCmd(context: controlSSL!, cmd: "PROT P\r\n")
            let protPResp = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)
            guard protPResp.hasPrefix("200") else {
                throw ftpError("PROT P отклонен: \(protPResp)")
            }
            useTlsDataChannel = true
        }

        // === ШАГ 7: TYPE I (бинарный режим) ===
        try sslWriteCmd(context: controlSSL!, cmd: "TYPE I\r\n")
        let typeResp = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)
        guard typeResp.hasPrefix("200") else {
            throw ftpError("TYPE I ошибка: \(typeResp)")
        }

        // === ШАГ 8: EPSV / PASV ===
        var dataPort = 0
        var epsvOk = false

        try sslWriteCmd(context: controlSSL!, cmd: "EPSV\r\n")
        let epsvResp = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)
        if epsvResp.hasPrefix("229"), let port = parseEPSVPort(epsvResp) {
            dataPort = port
            epsvOk = true
            logMsg("[SecureTransport] EPSV port: \(dataPort)")
        }

        if !epsvOk {
            logMsg("[SecureTransport] EPSV не удался, пробуем PASV...")
            try sslWriteCmd(context: controlSSL!, cmd: "PASV\r\n")
            let pasvResp = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)
            guard pasvResp.hasPrefix("227") else {
                throw ftpError("PASV ошибка: \(pasvResp)")
            }
            dataPort = try parsePASVPort(pasvResp)
            logMsg("[SecureTransport] PASV port: \(dataPort)")
        }

        // === ШАГ 9: TCP подключение канала данных ===
        dataSock = try tcpConnect(host: resolvedIp, port: dataPort, timeoutSec: 20)
        setSocketTimeout(dataSock, seconds: 60)
        setNoSigPipe(dataSock)

        // === ШАГ 10: Отправка команды STOR на контрольном канале ===
        try sslWriteCmd(context: controlSSL!, cmd: "STOR \(filename)\r\n")
        let storResp = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)
        guard storResp.hasPrefix("150") || storResp.hasPrefix("125") else {
            throw ftpError("STOR ошибка: \(storResp)")
        }

        // === ШАГ 11: TLS на канале данных (с ТЕМ ЖЕ PeerID → Session Resumption!) ===
        // Рукопожатие запускается строго после того, как сервер подтвердил команду STOR (ответ 150/125).
        // Это предотвращает дедлок, так как AWS Transfer Family ожидает привязки команды до начала TLS-сессии.
        if useTlsDataChannel {
            logMsg("[SecureTransport] TLS канала данных (Session Resumption через SSLSetPeerID)...")
            dataSSL = try createSSLContext(sock: dataSock, peerName: cleanHost, peerId: peerId, requireValidCertificate: requireValidCert)
            try performSSLHandshake(context: dataSSL!, requireValidCertificate: requireValidCert)
            logMsg("[SecureTransport] ✅ TLS канала данных УСПЕХ — Session Resumption работает!")
        }

        // === ШАГ 12: Передача данных ===
        if let ssl = dataSSL {
            try sslWriteData(context: ssl, sock: dataSock, data: data, progress: progress)
        } else {
            try plainWriteData(sock: dataSock, data: data, progress: progress)
        }

        // === ШАГ 13: Закрытие канала данных ===
        if let ssl = dataSSL {
            secureSSLClose(context: ssl, sock: dataSock)
            dataSSL = nil
        }
        Darwin.close(dataSock)
        dataSock = -1

        // === ШАГ 14: Чтение подтверждения «226 Transfer complete» ===
        setSocketTimeout(controlSock, seconds: 60)
        let completeResp = try sslReadResponse(context: controlSSL!, buffer: &sslBuf)
        guard completeResp.hasPrefix("226") else {
            throw ftpError("Ошибка завершения передачи: \(completeResp)")
        }

        logMsg("[SecureTransport] ✅ Файл \(filename) успешно загружен!")

        // === ШАГ 15: QUIT ===
        try? sslWriteCmd(context: controlSSL!, cmd: "QUIT\r\n")
        // defer закроет SSLClose + close
    }

    // MARK: - TCP Layer

    /// Создание TCP-сокета с подключением и таймаутом через poll()
    private static func tcpConnect(host: String, port: Int, timeoutSec: Int) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let gaiStatus = getaddrinfo(host, String(port), &hints, &result)
        guard gaiStatus == 0, let addrInfo = result else {
            throw ftpError("DNS ошибка для \(host): \(gaiStatus)")
        }
        defer { freeaddrinfo(result) }

        let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
        guard sock >= 0 else {
            throw ftpError("Ошибка создания сокета: errno \(errno)")
        }

        // Non-blocking connect для таймаута
        var flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        let connectResult = Darwin.connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)
        if connectResult < 0 && errno != EINPROGRESS {
            let err = errno
            Darwin.close(sock)
            throw ftpError("Ошибка подключения к \(host):\(port) — errno \(err)")
        }

        // Ожидание подключения через poll
        var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pollFd, 1, Int32(timeoutSec * 1000))

        if pollResult <= 0 {
            Darwin.close(sock)
            throw ftpError("Таймаут подключения к \(host):\(port) (\(timeoutSec) сек)")
        }

        // Проверка ошибок
        var optError: Int32 = 0
        var optLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &optError, &optLen)
        if optError != 0 {
            Darwin.close(sock)
            throw ftpError("Ошибка TCP подключения: \(optError)")
        }

        // Обратно в блокирующий режим
        flags = fcntl(sock, F_GETFL, 0)
        let fcntlStatus = fcntl(sock, F_SETFL, flags & ~O_NONBLOCK)
        if fcntlStatus < 0 {
            logMsg("[WARNING] fcntl F_SETFL failed, errno: \(errno)")
        }

        return sock
    }

    private static func setSocketTimeout(_ sock: Int32, seconds: Int) {
        var timeout = timeval()
        timeout.tv_sec = seconds
        timeout.tv_usec = 0
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func setNoSigPipe(_ sock: Int32) {
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    }

    // MARK: - Plain-text I/O (до AUTH TLS)

    /// Чтение одной строки из сокета (до \n)
    private static func plainReadLine(sock: Int32, buffer: inout Data) throws -> String {
        while true {
            if let nlIdx = buffer.firstIndex(of: 0x0A) {
                let lineData = Data(buffer[buffer.startIndex...nlIdx])
                buffer.removeSubrange(buffer.startIndex...nlIdx)
                if let str = String(data: lineData, encoding: .utf8) {
                    return str
                }
            }

            var chunk = [UInt8](repeating: 0, count: 4096)
            let bytesRead = recv(sock, &chunk, chunk.count, 0)
            if bytesRead > 0 {
                buffer.append(contentsOf: chunk[0..<bytesRead])
            } else if bytesRead == 0 {
                throw ftpError("Соединение закрыто сервером")
            } else {
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK {
                    throw ftpError("Таймаут чтения данных")
                }
                throw ftpError("Ошибка чтения: errno \(err)")
            }
        }
    }

    /// Чтение FTP-ответа (с поддержкой multi-line: "NNN-" → "NNN ")
    private static func plainReadResponse(sock: Int32, buffer: inout Data) throws -> String {
        while true {
            let line = try plainReadLine(sock: sock, buffer: &buffer)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                FTPTranscriptLogger.shared.logResponse(trimmed)
            }

            // Финальная строка: "NNN " (3 цифры + пробел)
            if trimmed.count >= 4,
               trimmed.prefix(3).allSatisfy({ $0.isNumber }),
               trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)] == " " {
                return trimmed
            }
            // "NNN-" — продолжение, читаем дальше
        }
    }

    /// Отправка данных в сокет (plain text)
    private static func plainWrite(sock: Int32, cmd: String) throws {
        DispatchQueue.main.async {
            FTPTranscriptLogger.shared.logCommand(cmd)
        }

        guard let data = cmd.data(using: .utf8) else {
            throw ftpError("Ошибка кодирования команды")
        }

        try data.withUnsafeBytes { buffer in
            var totalSent = 0
            while totalSent < data.count {
                let ptr = buffer.baseAddress!.advanced(by: totalSent)
                let remaining = data.count - totalSent
                let sent = send(sock, ptr, remaining, 0)
                if sent > 0 {
                    totalSent += sent
                } else {
                    throw ftpError("Ошибка отправки: errno \(errno)")
                }
            }
        }
    }

    /// Отправка бинарных данных через plain-text сокет (PROT C)
    private static func plainWriteData(sock: Int32, data: Data, progress: (@Sendable (Double) -> Void)?) throws {
        let chunkSize = 65536
        var offset = 0
        let total = data.count

        while offset < total {
            let end = min(offset + chunkSize, total)
            let chunk = Data(data[offset..<end])

            try chunk.withUnsafeBytes { buffer in
                var totalSent = 0
                while totalSent < chunk.count {
                    let ptr = buffer.baseAddress!.advanced(by: totalSent)
                    let remaining = chunk.count - totalSent
                    let sent = send(sock, ptr, remaining, 0)
                    if sent > 0 {
                        totalSent += sent
                    } else {
                        let err = errno
                        if err == EAGAIN || err == EWOULDBLOCK {
                            var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                            let pollResult = poll(&pollFd, 1, 10000) // ждем до 10 сек
                            if pollResult <= 0 {
                                throw ftpError("Таймаут передачи данных: errno \(err)")
                            }
                            continue
                        }
                        throw ftpError("Ошибка передачи данных: errno \(err)")
                    }
                }
            }

            offset = end
            if total > 0 { progress?(Double(offset) / Double(total)) }
        }
    }

    // MARK: - SecureTransport SSL Layer

    /// Создание SSLContext с привязкой к BSD-сокету и установкой PeerID.
    ///
    /// SSLSetPeerID — КЛЮЧЕВОЙ ВЫЗОВ:
    /// SecureTransport использует PeerID как ключ кеша TLS-сессий.
    /// Если контрольный канал и канал данных имеют одинаковый PeerID,
    /// SecureTransport автоматически выполняет Session Resumption.
    ///
    /// ВАЖНО: SSLSetPeerID работает ТОЛЬКО с TLS 1.2 (Session ID resumption, RFC 5077).
    /// TLS 1.3 использует PSK-тикеты (RFC 8446), несовместимые с этим механизмом.
    /// Принудительно фиксируем TLS 1.2 на обоих каналах.
    private static func createSSLContext(sock: Int32, peerName: String, peerId: Data, requireValidCertificate: Bool) throws -> SSLContext {
        guard let context = SSLCreateContext(nil, .clientSide, .streamType) else {
            throw ftpError("Ошибка создания SSLContext")
        }

        // I/O callback: чтение из BSD-сокета
        SSLSetIOFuncs(context,
            // Read
            { (connection: SSLConnectionRef, data: UnsafeMutableRawPointer, dataLength: UnsafeMutablePointer<Int>) -> OSStatus in
                let sockFd = Int32(Int(bitPattern: connection))
                let bytesRead = recv(sockFd, data, dataLength.pointee, 0)
                if bytesRead > 0 {
                    dataLength.pointee = bytesRead
                    return noErr
                } else if bytesRead == 0 {
                    dataLength.pointee = 0
                    return errSSLClosedGraceful
                } else {
                    dataLength.pointee = 0
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        return errSSLWouldBlock
                    }
                    return errSecIO
                }
            },
            // Write
            { (connection: SSLConnectionRef, data: UnsafeRawPointer, dataLength: UnsafeMutablePointer<Int>) -> OSStatus in
                let sockFd = Int32(Int(bitPattern: connection))
                let bytesWritten = send(sockFd, data, dataLength.pointee, 0)
                if bytesWritten > 0 {
                    dataLength.pointee = bytesWritten
                    return noErr
                } else if bytesWritten == 0 {
                    dataLength.pointee = 0
                    return errSSLClosedGraceful
                } else {
                    dataLength.pointee = 0
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        return errSSLWouldBlock
                    }
                    return errSecIO
                }
            }
        )

        // Привязка SSL контекста к BSD-сокету через UnsafeRawPointer
        guard let connRef = UnsafeRawPointer(bitPattern: Int(sock)) else {
            throw ftpError("Некорректный дескриптор сокета")
        }
        SSLSetConnection(context, connRef)

        // ФИКСИРУЕМ TLS 1.2: SSLSetPeerID (Session ID resumption) несовместим с TLS 1.3.
        // TLS 1.3 PSK-тикеты — другой механизм. Без этого сервер получает некорректный
        // ClientHello и возвращает fatal alert → OSStatus -9806.
        SSLSetProtocolVersionMin(context, .tlsProtocol12)
        SSLSetProtocolVersionMax(context, .tlsProtocol12)

        // PeerID для общего кеша TLS-сессий — КРИТИЧЕСКИ ВАЖНО
        let peerIdStatus = peerId.withUnsafeBytes { ptr -> OSStatus in
            SSLSetPeerID(context, ptr.baseAddress!, peerId.count)
        }
        if peerIdStatus != noErr {
            throw ftpError("SSLSetPeerID ошибка: \(peerIdStatus)")
        }

        // SNI (Server Name Indication) — имя хоста для TLS
        peerName.withCString { cstr in
            _ = SSLSetPeerDomainName(context, cstr, peerName.count)
        }

        // Пропускаем верификацию сертификата только если это не требуется явно
        if !requireValidCertificate {
            SSLSetSessionOption(context, .breakOnServerAuth, true)
        }

        return context
    }

    /// TLS Handshake с обработкой breakOnServerAuth.
    /// При получении errSSLPeerAuthCompleted продолжаем без верификации.
    /// Логирует согласованную TLS-версию для диагностики.
    private static func performSSLHandshake(context: SSLContext, requireValidCertificate: Bool) throws {
        var status: OSStatus
        repeat {
            status = SSLHandshake(context)
        } while status == errSSLWouldBlock || (!requireValidCertificate && status == errSSLPeerAuthCompleted)

        if status != noErr {
            throw ftpError("TLS handshake ошибка: OSStatus \(status)")
        }

        // Логируем согласованную версию TLS для диагностики
        var negotiated = SSLProtocol.sslProtocolUnknown
        SSLGetNegotiatedProtocolVersion(context, &negotiated)
        let versionName: String
        switch negotiated {
        case .tlsProtocol12: versionName = "TLS 1.2"
        case .tlsProtocol13: versionName = "TLS 1.3"
        case .tlsProtocol11: versionName = "TLS 1.1"
        case .tlsProtocol1:  versionName = "TLS 1.0"
        default:             versionName = "Unknown (\(negotiated.rawValue))"
        }
        DispatchQueue.main.async {
            FTPTranscriptLogger.shared.logResponse("[SecureTransport] Согласована версия: \(versionName)")
        }
    }

    // MARK: - SSL I/O

    /// Чтение одной строки через SSL (до \n)
    private static func sslReadLine(context: SSLContext, buffer: inout Data) throws -> String {
        while true {
            if let nlIdx = buffer.firstIndex(of: 0x0A) {
                let lineData = Data(buffer[buffer.startIndex...nlIdx])
                buffer.removeSubrange(buffer.startIndex...nlIdx)
                if let str = String(data: lineData, encoding: .utf8) {
                    return str
                }
            }

            var chunk = [UInt8](repeating: 0, count: 4096)
            var bytesRead = 0
            let status = SSLRead(context, &chunk, chunk.count, &bytesRead)

            if bytesRead > 0 {
                buffer.append(contentsOf: chunk[0..<bytesRead])
            }

            if status != noErr && status != errSSLWouldBlock {
                if bytesRead == 0 {
                    if status == errSSLClosedGraceful {
                        throw ftpError("TLS соединение закрыто сервером")
                    }
                    throw ftpError("SSL read ошибка: \(status)")
                }
            }
        }
    }

    /// Чтение FTP-ответа через SSL (multi-line aware)
    private static func sslReadResponse(context: SSLContext, buffer: inout Data) throws -> String {
        while true {
            let line = try sslReadLine(context: context, buffer: &buffer)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                FTPTranscriptLogger.shared.logResponse(trimmed)
            }

            // Финальная строка: "NNN " (3 цифры + пробел)
            if trimmed.count >= 4,
               trimmed.prefix(3).allSatisfy({ $0.isNumber }),
               trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)] == " " {
                return trimmed
            }
            // "NNN-" — продолжение, читаем дальше
        }
    }

    /// Отправка FTP-команды через SSL
    private static func sslWriteCmd(context: SSLContext, cmd: String) throws {
        DispatchQueue.main.async {
            FTPTranscriptLogger.shared.logCommand(cmd)
        }

        guard let data = cmd.data(using: .utf8) else {
            throw ftpError("Ошибка кодирования команды")
        }

        try data.withUnsafeBytes { buffer in
            var processed = 0
            let ptr = buffer.baseAddress!
            var status = SSLWrite(context, ptr, data.count, &processed)

            if status == errSSLWouldBlock {
                // Команда буферизирована, нужно вытолкнуть
                while status == errSSLWouldBlock {
                    var dummy = 0
                    status = SSLWrite(context, nil, 0, &dummy)
                }
            }

            if status != noErr {
                throw ftpError("SSL write ошибка: \(status)")
            }
        }
    }

    /// Отправка бинарных данных файла через SSL (PROT P)
    ///
    /// КРИТИЧЕСКИ ВАЖНО: SecureTransport буферизирует данные внутри SSLContextRef.
    /// Когда SSLWrite возвращает errSSLWouldBlock, ВСЕ переданные данные уже были
    /// скопированы во внутренний буфер (не в сокет). Параметр 'processed' показывает
    /// не количество реально отправленных байт, а количество помещённых в буфер.
    /// Для очистки буфера нужно вызывать SSLWrite(nil, 0) до получения noErr.
    /// Эта логика скопирована из исходного кода curl (lib/vtls/sectransp.c).
    private static func sslWriteData(context: SSLContext, sock: Int32, data: Data, progress: (@Sendable (Double) -> Void)?) throws {
        let chunkSize = 16384 // 16 KB (размер одной TLS-записи)
        var offset = 0
        let total = data.count
        var totalBytesWrittenToSocket = 0
        var totalErrWouldBlockCount = 0

        // Инициализация контекста хэширования SHA-256
        var shaCtx = CC_SHA256_CTX()
        CC_SHA256_Init(&shaCtx)

        logMsg("[Diagnostic] Начало передачи по SSL. Размер: \(total) байт, чанк: \(chunkSize) байт")

        while offset < total {
            let end = min(offset + chunkSize, total)
            let chunk = Data(data[offset..<end])

            try chunk.withUnsafeBytes { buffer in
                let ptr = buffer.baseAddress!
                let len = chunk.count
                var bytesWrittenThisChunk = 0

                while bytesWrittenThisChunk < len {
                    let currentPtr = ptr.advanced(by: bytesWrittenThisChunk)
                    let currentLen = len - bytesWrittenThisChunk

                    var processed = 0
                    var status = SSLWrite(context, currentPtr, currentLen, &processed)

                    if status == noErr {
                        if processed > 0 {
                            CC_SHA256_Update(&shaCtx, currentPtr, CC_LONG(processed))
                            bytesWrittenThisChunk += processed
                            totalBytesWrittenToSocket += processed
                        } else if currentLen > 0 {
                            logMsg("[WARNING] SSLWrite вернул noErr, но processed = 0")
                            throw ftpError("SSLWrite вернул noErr при processed = 0")
                        }
                        continue
                    }

                    if status == errSSLWouldBlock {
                        totalErrWouldBlockCount += 1
                        
                        if processed > 0 {
                            CC_SHA256_Update(&shaCtx, currentPtr, CC_LONG(processed))
                            bytesWrittenThisChunk += processed
                            totalBytesWrittenToSocket += processed
                        }

                        if totalErrWouldBlockCount <= 10 || totalErrWouldBlockCount % 50 == 0 {
                            logMsg("[Diagnostic] errSSLWouldBlock (всего: \(totalErrWouldBlockCount)). Сброс буфера (уже обработано в чанке: \(bytesWrittenThisChunk)/\(len))...")
                        }

                        var flushAttempts = 0
                        while status == errSSLWouldBlock {
                            var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                            let pollResult = poll(&pollFd, 1, 30000) // таймаут 30 секунд
                            if pollResult <= 0 {
                                throw ftpError("Таймаут сброса буфера данных (попытка \(flushAttempts))")
                            }

                            var dummy = 0
                            status = SSLWrite(context, nil, 0, &dummy)
                            flushAttempts += 1
                        }

                        if status != noErr {
                            throw ftpError("Ошибка сброса буфера данных: OSStatus \(status)")
                        }
                        continue
                    }

                    throw ftpError("Ошибка передачи данных: OSStatus \(status)")
                }
            }

            offset = end
            if total > 0 { progress?(Double(offset) / Double(total)) }
        }

        var sentHash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&sentHash, &shaCtx)
        let sentSha256 = sentHash.map { String(format: "%02x", $0) }.joined()

        logMsg("[Diagnostic] Передача по SSL завершена. Всего записано: \(totalBytesWrittenToSocket) байт. Возникновений errSSLWouldBlock: \(totalErrWouldBlockCount). SHA-256 отправленного потока: \(sentSha256)")
    }

    // MARK: - Helper Methods

    private static func secureSSLClose(context: SSLContext, sock: Int32) {
        var closeStatus: OSStatus
        var attempts = 0
        repeat {
            closeStatus = SSLClose(context)
            if closeStatus == errSSLWouldBlock {
                var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                _ = poll(&pollFd, 1, 2000) // Ждем 2 секунды
                attempts += 1
            }
        } while closeStatus == errSSLWouldBlock && attempts < 5
        
        if closeStatus != noErr {
            logMsg("[Diagnostic] SSLClose завершился со статусом: \(closeStatus) после \(attempts) попыток")
        } else {
            logMsg("[Diagnostic] SSLClose успешно завершён (close_notify отправлен)")
        }
    }

    private static func sha256String(for data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - EPSV / PASV Parsers

    private static func parseEPSVPort(_ response: String) -> Int? {
        // Формат: 229 Entering Extended Passive Mode (|||PORT|)
        let pattern = "\\(\\|\\|\\|(\\d+)\\|\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let range = Range(match.range(at: 1), in: response),
              let port = Int(response[range]) else {
            return nil
        }
        return port
    }

    private static func parsePASVPort(_ response: String) throws -> Int {
        // Формат: 227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)
        let pattern = "\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let range = Range(match.range(at: 1), in: response) else {
            throw ftpError("Ошибка разбора PASV: \(response)")
        }

        let parts = String(response[range]).components(separatedBy: ",")
        guard parts.count == 6,
              let p1 = Int(parts[4].trimmingCharacters(in: .whitespaces)),
              let p2 = Int(parts[5].trimmingCharacters(in: .whitespaces)) else {
            throw ftpError("Ошибка формата PASV: \(response)")
        }

        return p1 * 256 + p2
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

    // MARK: - Utilities

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

    private static func logMsg(_ message: String) {
        DispatchQueue.main.async {
            FTPTranscriptLogger.shared.logResponse(message)
        }
    }

    private static func ftpError(_ message: String) -> NSError {
        NSError(domain: "FTPSecureClient", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
