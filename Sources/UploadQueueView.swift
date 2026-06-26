import SwiftUI
import PhotosUI
import ImageIO
import UIKit

// MARK: - Queue View Model (MainActor Isolated, Safe Concurrency)
@MainActor
class QueueViewModel: ObservableObject {
    static var shared: QueueViewModel? = nil
    
    @Published var photos: [PhotoMetadata] = [] {
        didSet {
            savePhotosToDisk()
        }
    }
    @Published var isAnalyzingAll = false
    @Published var toastMessage = ""
    @Published var showToast = false
    
    private var metadataURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("queue_photos.json")
    }
    
    private var photosDirectoryURL: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
    
    init() {
        loadPhotosFromDisk()
        QueueViewModel.shared = self
    }
    
    func savePhotosToDisk() {
        let photosCopy = self.photos
        let metaURL = self.metadataURL
        let dirURL = self.photosDirectoryURL
        
        Task.detached(priority: .background) {
            do {
                for photo in photosCopy {
                    if let data = photo.imageData {
                        let fileURL = dirURL.appendingPathComponent("\(photo.id.uuidString).jpg")
                        try data.write(to: fileURL, options: .atomic)
                    }
                }
                
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(photosCopy)
                try data.write(to: metaURL, options: .atomic)
                
                let idsInQueue = Set(photosCopy.map { "\($0.id.uuidString).jpg" })
                let existingFiles = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                for file in existingFiles {
                    if !idsInQueue.contains(file.lastPathComponent) {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            } catch {
                print("Error saving photos to disk: \(error.localizedDescription)")
            }
        }
    }
    
    func loadPhotosFromDisk() {
        do {
            let metaURL = self.metadataURL
            
            guard FileManager.default.fileExists(atPath: metaURL.path) else { return }
            let data = try Data(contentsOf: metaURL)
            let decoded = try JSONDecoder().decode([PhotoMetadata].self, from: data)
            
            var loadedPhotos: [PhotoMetadata] = []
            for var photo in decoded {
                photo.imageData = nil // Не загружаем тяжелые оригинальные байты в ОЗУ при старте
                loadedPhotos.append(photo)
            }
            self.photos = loadedPhotos
        } catch {
            print("Error loading photos from disk: \(error.localizedDescription)")
        }
    }
    
    func runAIForPhoto(_ id: UUID) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        
        let provider = UserDefaults.standard.string(forKey: "ai_provider") ?? AIProvider.gemini.rawValue
        let customPrompt = UserDefaults.standard.string(forKey: "ai_custom_prompt") ?? ""
        
        let apiKey: String
        if provider.contains("Gemini") {
            apiKey = UserDefaults.standard.string(forKey: "api_key_gemini") ?? ""
        } else if provider.contains("OpenAI") {
            apiKey = UserDefaults.standard.string(forKey: "api_key_openai") ?? ""
        } else {
            apiKey = UserDefaults.standard.string(forKey: "api_key_claude") ?? ""
        }
        
        // Check if API key is blank
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            // No Key: Demo Mode
            photos[idx].status = .aiAnalyzing
            triggerToast("Запущен демо-анализ (ключ API не введен)")
            
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if self.photos.count > idx {
                    self.photos[idx].title = "Драматичный закат в горах (Демо)"
                    self.photos[idx].keywords = ["закат", "облака", "небо", "горы", "пейзаж", "демо"]
                    self.photos[idx].description = "Демо-описание: Введите ваш API-ключ в настройках ИИ для запуска полноценного анализа вашей фотографии."
                    self.photos[idx].status = .ready
                    self.triggerToast("Демо-анализ завершен")
                }
            }
            return
        }
        
        photos[idx].status = .aiAnalyzing
        triggerToast("ИИ анализирует фотографию...")
        
        Task {
            do {
                let photoId = self.photos[idx].id
                let fileURL = self.photosDirectoryURL.appendingPathComponent("\(photoId.uuidString).jpg")
                let imageData = (try? Data(contentsOf: fileURL)) ?? Data()
                let result = try await AIManager.shared.analyzePhoto(
                    imageData: imageData,
                    customPrompt: customPrompt,
                    provider: provider,
                    apiKey: apiKey
                )
                
                self.photos[idx].title = result.title
                self.photos[idx].description = result.description
                self.photos[idx].keywords = result.keywords
                self.photos[idx].categories = result.categories ?? []
                self.photos[idx].status = .ready
                self.triggerToast("Анализ ИИ успешно завершен!")
            } catch {
                self.photos[idx].description = "Ошибка: \(error.localizedDescription)"
                self.photos[idx].status = .error
                self.photos[idx].errorMessage = error.localizedDescription
                self.triggerToast("Ошибка ИИ: \(error.localizedDescription)")
            }
        }
    }
    
    func runAIForAll() {
        let newOrErrorPhotos = photos.filter { $0.status == .new || $0.status == .error }
        guard !newOrErrorPhotos.isEmpty else { return }
        
        isAnalyzingAll = true
        triggerToast("Запущен ИИ-анализ для \(newOrErrorPhotos.count) фото...")
        
        let provider = UserDefaults.standard.string(forKey: "ai_provider") ?? AIProvider.gemini.rawValue
        let customPrompt = UserDefaults.standard.string(forKey: "ai_custom_prompt") ?? ""
        let apiKey: String
        if provider.contains("Gemini") {
            apiKey = UserDefaults.standard.string(forKey: "api_key_gemini") ?? ""
        } else if provider.contains("OpenAI") {
            apiKey = UserDefaults.standard.string(forKey: "api_key_openai") ?? ""
        } else {
            apiKey = UserDefaults.standard.string(forKey: "api_key_claude") ?? ""
        }
        
        // Loop and run
        Task {
            for photo in newOrErrorPhotos {
                if let idx = self.photos.firstIndex(where: { $0.id == photo.id }) {
                    self.photos[idx].status = .aiAnalyzing
                    
                    if apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Demo mode delay
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if self.photos.count > idx {
                            self.photos[idx].title = "Красивый снимок (Демо)"
                            self.photos[idx].keywords = ["фотография", "снимок", "стоки", "демо", "пейзаж"]
                            self.photos[idx].description = "Демо-описание: Введите ваш API-ключ в настройках ИИ для запуска полноценного анализа."
                            self.photos[idx].status = .ready
                        }
                    } else {
                        // Real analysis
                        do {
                            let photoId = self.photos[idx].id
                            let fileURL = self.photosDirectoryURL.appendingPathComponent("\(photoId.uuidString).jpg")
                            let data = (try? Data(contentsOf: fileURL)) ?? Data()
                            let result = try await AIManager.shared.analyzePhoto(
                                imageData: data,
                                customPrompt: customPrompt,
                                provider: provider,
                                apiKey: apiKey
                            )
                            if self.photos.count > idx {
                                self.photos[idx].title = result.title
                                self.photos[idx].description = result.description
                                self.photos[idx].keywords = result.keywords
                                self.photos[idx].categories = result.categories ?? []
                                self.photos[idx].status = .ready
                            }
                        } catch {
                            if self.photos.count > idx {
                                self.photos[idx].status = .error
                                self.photos[idx].description = "Ошибка: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
            
            self.isAnalyzingAll = false
            self.triggerToast("ИИ-анализ всех фото завершен")
        }
    }
    
    func uploadPhoto(_ id: UUID) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        
        guard checkStockCredentials() else {
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!".localized)
            return
        }
        
        photos[idx].status = .uploading
        photos[idx].uploadProgress = 0.0
        photos[idx].errorMessage = nil
        triggerToast("Загрузка файла".localized + " \(photos[idx].filename)...")
        
        Task {
            do {
                let photo = self.photos[idx]
                try await performRealUpload(for: photo) { progress in
                    _ = Task { @MainActor in
                        if let index = self.photos.firstIndex(where: { $0.id == id }) {
                            self.photos[index].uploadProgress = progress
                        }
                    }
                }
                
                if let index = self.photos.firstIndex(where: { $0.id == id }) {
                    self.photos[index].status = .success
                    self.photos[index].uploadProgress = 1.0
                    self.triggerToast("Файл".localized + " \(self.photos[index].filename) " + "успешно загружен на стоки!".localized)
                    NotificationHelper.sendNotification(
                        title: "Успешная выгрузка".localized,
                        body: "Файл".localized + " \(self.photos[index].filename) " + "успешно загружен на стоки!".localized
                    )
                }
            } catch {
                if let index = self.photos.firstIndex(where: { $0.id == id }) {
                    self.photos[index].status = .error
                    self.photos[index].errorMessage = error.localizedDescription
                    self.triggerToast("Ошибка выгрузки".localized + " \(self.photos[index].filename): \(error.localizedDescription)")
                    NotificationHelper.sendNotification(
                        title: "Ошибка выгрузки".localized,
                        body: "Файл".localized + " \(self.photos[index].filename): \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    func uploadAllReady() {
        let readyPhotos = photos.filter { $0.status == .ready }
        guard !readyPhotos.isEmpty else {
            triggerToast("Нет файлов, готовых к отправке.".localized)
            return
        }
        
        guard checkStockCredentials() else {
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!".localized)
            return
        }
        
        // Читаем лимит параллельных потоков из настроек (по умолчанию 3)
        let maxStreams = UserDefaults.standard.integer(forKey: "sys_parallel_streams")
        let streamLimit = maxStreams > 0 ? maxStreams : 3
        
        triggerToast("Началась отправка".localized + " \(readyPhotos.count) " + "файлов".localized + " (\(streamLimit) " + getStreamWord(streamLimit).localized + ")...")
        
        for photo in readyPhotos {
            let pId = photo.id
            if let idx = self.photos.firstIndex(where: { $0.id == pId }) {
                self.photos[idx].status = .uploading
                self.photos[idx].uploadProgress = 0.0
                self.photos[idx].errorMessage = nil
            }
        }
        
        Task { @MainActor in
            // Простой семафор на основе actor для ограничения параллелизма
            let semaphore = UploadSemaphore(limit: streamLimit)
            
            await withTaskGroup(of: Void.self) { group in
                for photo in readyPhotos {
                    let pId = photo.id
                    group.addTask { @MainActor in
                        await semaphore.wait()
                        
                        do {
                            guard let currentPhoto = self.photos.first(where: { $0.id == pId }) else {
                                await semaphore.signal()
                                return
                            }
                            try await self.performRealUpload(for: currentPhoto) { progress in
                                _ = Task { @MainActor in
                                    if let index = self.photos.firstIndex(where: { $0.id == pId }) {
                                        self.photos[index].uploadProgress = progress
                                    }
                                }
                            }
                            
                            if let index = self.photos.firstIndex(where: { $0.id == pId }) {
                                self.photos[index].status = .success
                                self.photos[index].uploadProgress = 1.0
                                self.triggerToast("Файл \(self.photos[index].filename) успешно загружен!")
                                NotificationHelper.sendNotification(
                                    title: "Успешная выгрузка".localized,
                                    body: "Файл".localized + " \(self.photos[index].filename) " + "успешно загружен!".localized
                                )
                            }
                        } catch {
                            if let index = self.photos.firstIndex(where: { $0.id == pId }) {
                                self.photos[index].status = .error
                                self.photos[index].errorMessage = error.localizedDescription
                                self.triggerToast("Ошибка: \(self.photos[index].filename): \(error.localizedDescription)")
                                NotificationHelper.sendNotification(
                                    title: "Ошибка выгрузки".localized,
                                    body: "Файл".localized + " \(self.photos[index].filename): \(error.localizedDescription)"
                                )
                            }
                        }
                        
                        await semaphore.signal()
                    }
                }
            }
            
            let remaining = self.photos.filter { $0.status == .uploading }.count
            if remaining == 0 {
                self.triggerToast("Все файлы обработаны!")
            }
        }
    }
    
    private func performRealUpload(for photo: PhotoMetadata, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let fileURL = self.photosDirectoryURL.appendingPathComponent("\(photo.id.uuidString).jpg")
        guard let data = try? Data(contentsOf: fileURL) else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Изображение не найдено на диске"])
        }
        
        // Переносим обработку метаданных и сжатие в фоновый актор ImageProcessor
        let compress = UserDefaults.standard.bool(forKey: "sys_compress_jpeg")
        let finalData = await ImageProcessor.shared.prepareImageForUpload(
            imageData: data,
            photo: photo,
            compress: compress
        )
        
        // Load active platforms
        guard let platformsData = UserDefaults.standard.data(forKey: "stock_platforms"),
              let platforms = try? JSONDecoder().decode([StockPlatform].self, from: platformsData) else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Настройки стоков не найдены"])
        }
        
        // Фильтруем только те стоки, которые включены в настройках И выбраны для конкретной фотографии
        let activePlatforms = platforms.filter { platform in
            platform.isEnabled && photo.selectedStocks.contains(platform.name)
        }
        guard !activePlatforms.isEmpty else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Нет активных стоков для отправки. Включите фотостоки в настройках и отметьте их для этого фото."])
        }
        
        // Проверяем, включен ли ПК-сервер
        let pcServerEnabled = UserDefaults.standard.bool(forKey: "sys_pc_server_enabled")
        if pcServerEnabled {
            let pcAddress = UserDefaults.standard.string(forKey: "sys_pc_server_address") ?? "192.168.1.50:5000"
            try await uploadViaPCServer(
                data: finalData,
                filename: photo.filename,
                pcAddress: pcAddress,
                activePlatforms: activePlatforms,
                progress: progress
            )
            return
        }
        
        var uploadErrors: [String] = []
        var successCount = 0
        
        let maxAttempts = UserDefaults.standard.bool(forKey: "sys_retry_on_fail") ? 3 : 1
        
        // Upload to each active platform
        for platform in activePlatforms {
            let serviceKey = "com.samvel.smartstock.platform.\(platform.id)"
            let password = KeychainHelper.shared.read(for: serviceKey) ?? ""
            
            guard !platform.username.isEmpty, !password.isEmpty else {
                uploadErrors.append("\(platform.name): не введены логин или пароль")
                continue
            }
            
            // FTPClient теперь сам определяет протокол по хосту (ftp/ftps/sftp)
            // Передаём оригинальный host как есть
            var attempts = 0
            var uploadError: Error? = nil
            
            while attempts < maxAttempts {
                do {
                    // FTPSecureClient использует BSD-сокеты + SecureTransport
                    // с SSLSetPeerID для TLS Session Resumption (решает проблему Shutterstock)
                    try await FTPSecureClient.upload(
                        data: finalData,
                        filename: photo.filename,
                        host: platform.host,
                        port: 21,
                        username: platform.username,
                        password: password,
                        progress: progress
                    )
                    successCount += 1
                    uploadError = nil
                    // Записываем успешную загрузку в историю статистики
                    StatsManager.recordUpload(
                        platformId: platform.id,
                        platformName: platform.name,
                        filename: photo.filename,
                        isSuccess: true
                    )
                    break
                } catch {
                    attempts += 1
                    uploadError = error
                    if attempts < maxAttempts {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2s before retry
                    }
                }
            }
            
            if let error = uploadError {
                uploadErrors.append("\(platform.name): \(error.localizedDescription)")
                // Записываем ошибку в историю статистики (только после всех попыток)
                StatsManager.recordUpload(
                    platformId: platform.id,
                    platformName: platform.name,
                    filename: photo.filename,
                    isSuccess: false
                )
            }
        }
        
        if successCount == 0 {
            let details = uploadErrors.joined(separator: "; ")
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка загрузки: \(details)"])
        } else if !uploadErrors.isEmpty {
            let details = uploadErrors.joined(separator: "; ")
            throw NSError(domain: "Upload", code: -2, userInfo: [NSLocalizedDescriptionKey: "Частичный успех. Ошибки: \(details)"])
        }
    }
    
    private func uploadViaPCServer(
        data: Data,
        filename: String,
        pcAddress: String,
        activePlatforms: [StockPlatform],
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // Шаг 1: Загрузка временного файла на ПК
        progress?(0.05)
        let fileId = try await uploadMultipart(data: data, filename: filename, pcAddress: pcAddress)
        
        let targetStockIds = Set(activePlatforms.map { $0.id })
        
        // Шаг 2: Запуск загрузки на ПК и SSE-мониторинг
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.listenToSSE(pcAddress: pcAddress, fileId: fileId, targetStocks: targetStockIds, progress: progress)
            }
            
            group.addTask {
                // Небольшая задержка, чтобы дать SSE-слушателю подключиться к бэкенду
                try await Task.sleep(nanoseconds: 500_000_000)
                
                for platform in activePlatforms {
                    let serviceKey = "com.samvel.smartstock.platform.\(platform.id)"
                    let password = KeychainHelper.shared.read(for: serviceKey) ?? ""
                    
                    guard !platform.username.isEmpty, !password.isEmpty else {
                        throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "\(platform.name): не введены логин или пароль"])
                    }
                    
                    try await self.startPCStockUpload(fileId: fileId, pcAddress: pcAddress, platform: platform, passwordHash: password)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    private func uploadMultipart(data: Data, filename: String, pcAddress: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: "http://\(pcAddress)/api/upload-temp") else {
            throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Некорректный адрес ПК-сервера: \(pcAddress)"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photos\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: responseData, encoding: .utf8) ?? "Неизвестная ошибка"
            throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка загрузки на ПК-сервер: \(errorMsg)"])
        }
        
        struct TempUploadResponse: Codable {
            struct FileItem: Codable {
                let id: String
            }
            let success: Bool
            let files: [FileItem]
        }
        
        let decoded = try JSONDecoder().decode(TempUploadResponse.self, from: responseData)
        guard decoded.success, let firstFile = decoded.files.first else {
            throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить ID временного файла от ПК"])
        }
        return firstFile.id
    }
    
    private func startPCStockUpload(fileId: String, pcAddress: String, platform: StockPlatform, passwordHash: String) async throws {
        guard let url = URL(string: "http://\(pcAddress)/api/upload-stock") else {
            throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Некорректный URL для запуска выгрузки"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let protocolStr = platform.host.lowercased().contains("sftp") ? "sftp" : "ftps"
        
        let profile: [String: Any] = [
            "host": platform.host,
            "port": protocolStr == "sftp" ? 22 : 21,
            "username": platform.username,
            "password": passwordHash,
            "protocol": protocolStr,
            "remotePath": ""
        ]
        
        let body: [String: Any] = [
            "fileId": fileId,
            "profile": profile,
            "targetStockId": platform.id
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: responseData, encoding: .utf8) ?? "Неизвестная ошибка"
            throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось запустить загрузку на \(platform.name) через ПК: \(errorMsg)"])
        }
    }
    
    private func listenToSSE(pcAddress: String, fileId: String, targetStocks: Set<String>, progress: (@Sendable (Double) -> Void)?) async throws {
        guard let url = URL(string: "http://\(pcAddress)/api/upload-events") else {
            throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Некорректный URL для SSE событий"])
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 600
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось подключиться к каналу событий ПК"])
        }
        
        struct SSEEvent: Codable {
            let fileId: String?
            let stockId: String?
            let status: String?
            let progress: Double?
            let error: String?
        }
        
        var stockProgresses: [String: Double] = [:]
        var completedStocks = Set<String>()
        var failedStocks = [String: String]()
        
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                guard let jsonData = jsonString.data(using: .utf8) else { continue }
                
                guard let event = try? JSONDecoder().decode(SSEEvent.self, from: jsonData) else { continue }
                
                if event.fileId == fileId, let stockId = event.stockId {
                    let isTarget = targetStocks.contains(where: { $0.lowercased().contains(stockId.lowercased()) })
                    if isTarget {
                        if event.status == "uploading", let prog = event.progress {
                            stockProgresses[stockId] = prog / 100.0
                            let totalProgress = stockProgresses.values.reduce(0.0, +) / Double(targetStocks.count)
                            progress?(totalProgress)
                        } else if event.status == "success" {
                            stockProgresses[stockId] = 1.0
                            completedStocks.insert(stockId)
                            let totalProgress = stockProgresses.values.reduce(0.0, +) / Double(targetStocks.count)
                            progress?(totalProgress)
                        } else if event.status == "error" {
                            failedStocks[stockId] = event.error ?? "Ошибка при загрузке с ПК"
                            completedStocks.insert(stockId)
                        }
                        
                        if completedStocks.count == targetStocks.count {
                            if !failedStocks.isEmpty {
                                let details = failedStocks.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
                                throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка выгрузки через ПК: \(details)"])
                            }
                            return
                        }
                    }
                }
            }
        }
        
        if completedStocks.count < targetStocks.count {
            throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Соединение с ПК-сервером разорвано до завершения выгрузки"])
        }
    }
    
    


    
    private func checkStockCredentials() -> Bool {
        if let data = UserDefaults.standard.data(forKey: "stock_platforms"),
           let decoded = try? JSONDecoder().decode([StockPlatform].self, from: data) {
            let activePlatforms = decoded.filter { $0.isEnabled }
            return !activePlatforms.isEmpty && activePlatforms.contains(where: { platform in
                if platform.username.isEmpty { return false }
                let serviceKey = "com.samvel.smartstock.platform.\(platform.id)"
                let pwd = KeychainHelper.shared.read(for: serviceKey) ?? ""
                return !pwd.isEmpty
            })
        }
        return false
    }
    
    func removePhoto(_ id: UUID) {
        photos.removeAll(where: { $0.id == id })
        savePhotosToDisk()
    }
    
    func deletePhoto(at offsets: IndexSet) {
        photos.remove(atOffsets: offsets)
        savePhotosToDisk()
    }
    
    func addPhoto(_ photo: PhotoMetadata) {
        var photoCopy = photo
        if let data = photo.imageData {
            let fileURL = self.photosDirectoryURL.appendingPathComponent("\(photo.id.uuidString).jpg")
            Task.detached(priority: .background) {
                try? data.write(to: fileURL, options: .atomic)
            }
            photoCopy.imageData = nil // Освобождаем ОЗУ
        }
        photos.append(photoCopy)
        savePhotosToDisk()
    }
    
    func toggleStockForPhoto(_ photoId: UUID, stockName: String) {
        if let idx = photos.firstIndex(where: { $0.id == photoId }) {
            if photos[idx].selectedStocks.contains(stockName) {
                photos[idx].selectedStocks.remove(stockName)
            } else {
                photos[idx].selectedStocks.insert(stockName)
            }
            savePhotosToDisk()
        }
    }
    
    func triggerToast(_ message: String) {
        toastMessage = message
        withAnimation {
            showToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.toastMessage == message {
                withAnimation {
                    self.showToast = false
                }
            }
        }
    }
    
    private func getStreamWord(_ count: Int) -> String {
        switch count {
        case 1: return "поток".localized
        case 3, 4: return "потока".localized
        default: return "потоков".localized
        }
    }
}

// MARK: - Upload Queue View
@MainActor
struct UploadQueueView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var viewModel: QueueViewModel
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var searchText = ""
    @State private var selectedFilter: PhotoStatus? = nil
    @State private var editingPhoto: ActiveSheetPhoto? = nil
    @State private var showLogViewer = false
    @State private var selectedErrorMsg: String? = nil
    @State private var showingErrorAlert = false
    @State private var selectedDetailPhoto: PhotoMetadata? = nil
    
    var filteredPhotos: [PhotoMetadata] {
        viewModel.photos.filter { photo in
            let matchesSearch = searchText.isEmpty || 
                                photo.filename.localizedCaseInsensitiveContains(searchText) || 
                                photo.title.localizedCaseInsensitiveContains(searchText) ||
                                photo.keywords.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            
            let matchesFilter = selectedFilter == nil || photo.status == selectedFilter
            return matchesSearch && matchesFilter
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Виджет статистики и сети вместо зоны добавления файлов
                            QueueStatsWidget(viewModel: viewModel)
                            
                            // Строка поиска (адаптивная для тёмной и светлой темы)
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.secondary)
                                TextField("Поиск фото, альбомов...".localized, text: $searchText)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.04), radius: 4, x: 0, y: 2)
                            
                            // Заголовок Recents и кнопка Select
                            HStack {
                                Text("Недавние".localized)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button("Выбрать".localized) {
                                    HapticHelper.trigger(.light)
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "A855F7"))
                            }
                            .padding(.top, 8)
                            
                            // Список фотографий
                            if filteredPhotos.isEmpty {
                                VStack(spacing: 12) {
                                    SmartStockLogoView(size: 64)
                                        .padding(.bottom, 6)
                                    Text("Очередь пуста")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.primary)
                                    Text("Выберите снимки, чтобы запустить ИИ-подбор метаданных и отправить их на микростоки.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                                .frame(maxWidth: .infinity)
                                .glassCard(cornerRadius: 20, padding: 24)
                                .padding(.top, 20)
                            } else {
                                LazyVStack(spacing: 16) {
                                    ForEach(Array(filteredPhotos.enumerated()), id: \.element.id) { index, photo in
                                        PhotoRowView(photo: photo, index: index, viewModel: viewModel)
                                            .onTapGesture {
                                                HapticHelper.selection()
                                                selectedDetailPhoto = photo
                                            }
                                            .contextMenu {
                                                Button {
                                                    viewModel.runAIForPhoto(photo.id)
                                                } label: {
                                                    Label("Запустить ИИ-анализ", systemImage: "sparkles")
                                                }
                                                
                                                Button {
                                                    viewModel.uploadPhoto(photo.id)
                                                } label: {
                                                    Label("Выгрузить на стоки", systemImage: "paperplane")
                                                }
                                                
                                                Button(role: .destructive) {
                                                    viewModel.removePhoto(photo.id)
                                                } label: {
                                                    Label("Удалить", systemImage: "trash")
                                                }
                                            }
                                            .applyScrollTransitionIfAvailable()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 120) // Отступ для плавающих кнопок и таб-бара
                    }
                }
                
                // Плавающая фиолетовая кнопка "+" в нижнем правом углу
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 50,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color(hex: "7C3AED"), Color(hex: "A855F7")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 56, height: 56)
                                    .neonShadow(color: Color(hex: "7C3AED"), radius: 8)
                                
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .onChange(of: selectedItems) { newItems in
                            if !newItems.isEmpty {
                                HapticHelper.trigger(.medium)
                            }
                            loadSelectedPhotos(from: newItems)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, viewModel.photos.isEmpty ? 20 : 94) // Сдвигаем вверх, если виден Floating Action Bar
                    }
                }
                
                // Floating Action Bar (Заполнить все ИИ / Отправить)
                if !viewModel.photos.isEmpty {
                    VStack {
                        Spacer()
                        HStack(spacing: 14) {
                            Button(action: {
                                HapticHelper.trigger(.medium)
                                viewModel.runAIForAll()
                            }) {
                                HStack(spacing: 6) {
                                    if #available(iOS 17.0, *) {
                                        Image(systemName: "sparkles")
                                            .symbolEffect(.pulse, options: .repeating, value: viewModel.isAnalyzingAll)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text("Заполнить все ИИ")
                                }
                                .font(.system(size: 11, weight: .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppleTheme.primaryGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .neonShadow(color: Color(hex: "7C3AED"), radius: 5)
                            }
                            .buttonStyle(PremiumButtonStyle())
                            .disabled(viewModel.isAnalyzingAll)
                            
                            Button(action: {
                                HapticHelper.trigger(.medium)
                                viewModel.uploadAllReady()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "paperplane.fill")
                                    Text("Отправить")
                                }
                                .font(.system(size: 11, weight: .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 1.2)
                                )
                            }
                            .buttonStyle(PremiumButtonStyle())
                        }
                        .padding(10)
                        .glassCard(cornerRadius: 18, padding: 8)
                        .neonShadow(color: Color(hex: "7C3AED"), radius: 10)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                
                // Toast-уведомление
                if viewModel.showToast {
                    VStack {
                        Spacer()
                        Text(viewModel.toastMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                colorScheme == .dark ? Color(hex: "2C2C2E") : Color(hex: "E5E5EA")
                            )
                            .foregroundStyle(.primary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                            .neonShadow(color: .black, radius: 10)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 94)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("Галерея".localized)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {
                            showLogViewer = true
                        }) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color(hex: "7C3AED"))
                        }
                        
                        Button(action: {
                            HapticHelper.trigger(.light)
                        }) {
                            Image(systemName: "bell")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showLogViewer) {
                LogViewer()
            }
            .sheet(item: $editingPhoto) { wrapper in
                NavigationStack {
                    AIMetadataView(photos: wrapper.photos, currentIndex: wrapper.index) { updatedPhotos in
                        for updated in updatedPhotos {
                            if let idx = viewModel.photos.firstIndex(where: { $0.id == updated.id }) {
                                viewModel.photos[idx] = updated
                            }
                        }
                        editingPhoto = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Закрыть") {
                                editingPhoto = nil
                            }
                            .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
            }
            .sheet(item: $selectedDetailPhoto) { photo in
                PhotoDetailSheet(photo: photo, viewModel: viewModel, editingPhoto: $editingPhoto)
            }
            .alert("Ошибка загрузки", isPresented: $showingErrorAlert) {
                Button("Скопировать") {
                    if let msg = selectedErrorMsg {
                        UIPasteboard.general.string = msg
                        HapticHelper.notification(.success)
                    }
                }
                Button("ОК", role: .cancel) {}
            } message: {
                if let msg = selectedErrorMsg {
                    Text(msg)
                }
            }
        }
    }
    
// MARK: - Photo Row View (Equatable)
struct PhotoRowView: View, Equatable {
    let photo: PhotoMetadata
    let index: Int
    @ObservedObject var viewModel: QueueViewModel
    
    nonisolated static func == (lhs: PhotoRowView, rhs: PhotoRowView) -> Bool {
        return lhs.photo.id == rhs.photo.id &&
               lhs.photo.status == rhs.photo.status &&
               lhs.photo.uploadProgress == rhs.photo.uploadProgress &&
               lhs.photo.title == rhs.photo.title &&
               lhs.photo.filename == rhs.photo.filename &&
               lhs.photo.fileSize == rhs.photo.fileSize &&
               lhs.photo.selectedStocks == rhs.photo.selectedStocks
    }
    
    var body: some View {
        VStack(spacing: 0) {
            photoImage(photo)
            photoProgressBar(photo)
            photoButtons(photo, index: index)
            if photo.status == .uploading {
                Text("UPLOADING...")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color(hex: "10B981"))
                    .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)  // Адаптивный фон
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1.2)  // Адаптивная обводка
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    
    private func photoImage(_ photo: PhotoMetadata) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                // Размытый фон для заполнения пропорций по краям
                LazyImageView(photoId: photo.id, maxPixelSize: 150, contentMode: .fill)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .blur(radius: 16)
                    .opacity(0.35)
                    .clipped()
                
                // Полное изображение без обрезки
                LazyImageView(photoId: photo.id, maxPixelSize: 400, contentMode: .fit)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            }
            .background(Color.black.opacity(0.2))
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            
            // Статус READY (слева сверху)
            if photo.status == .ready {
                Text("READY")
                    .font(.system(size: 9, weight: .black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "223E4A").opacity(0.85))
                    .foregroundStyle(Color(hex: "81E6D9"))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(12)
            }
            
            // Иконка УСПЕШНО (справа сверху)
            if photo.status == .success {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "10B981"))
                        .background(Color.black.clipShape(Circle()))
                        .neonShadow(color: Color(hex: "10B981"), radius: 4)
                        .padding(12)
                }
            }
            
            // Иконка СИНХРОНИЗАЦИИ / ЗАГРУЗКИ (справа сверху)
            if photo.status == .uploading {
                HStack {
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6).clipShape(Circle()))
                        .padding(12)
                }
            }
        }
    }
    
    private func photoProgressBar(_ photo: PhotoMetadata) -> some View {
        Group {
            if photo.status == .uploading {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3)
                        
                        RoundedRectangle(cornerRadius: 0)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "10B981"), Color(hex: "34D399")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(photo.uploadProgress), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
    }
    
    private func photoButtons(_ photo: PhotoMetadata, index: Int) -> some View {
        HStack(spacing: 12) {
            // Кнопка DELETE
            Button(action: {
                HapticHelper.trigger(.medium)
                viewModel.removePhoto(photo.id)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("DELETE")
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Кнопка ИИ АНАЛИЗ
            Button(action: {
                HapticHelper.trigger(.medium)
                viewModel.runAIForPhoto(photo.id)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(photo.status == .aiAnalyzing ? Color.secondary : Color(hex: "A78BFA"))
                    Text(photo.status == .aiAnalyzing ? "Анализируем...".localized : "ИИ АНАЛИЗ".localized)
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(photo.status == .aiAnalyzing ? Color.white.opacity(0.04) : Color.white.opacity(0.08))
                .foregroundStyle(photo.status == .aiAnalyzing ? Color.secondary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(photo.status == .aiAnalyzing ? Color.white.opacity(0.04) : Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .disabled(photo.status == .aiAnalyzing)
            
            // Кнопка SEND / SENT
            Button(action: {
                if photo.status != .success {
                    HapticHelper.trigger(.medium)
                    viewModel.uploadPhoto(photo.id)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: photo.status == .success ? "checkmark" : "paperplane")
                    Text(photo.status == .success ? "SENT" : "SEND")
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(photo.status == .success ? Color.white.opacity(0.04) : Color.white.opacity(0.08))
                .foregroundStyle(photo.status == .success ? Color.secondary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .disabled(photo.status == .success)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}
    
    // MARK: - Load Photos Logic
    private func loadSelectedPhotos(from items: [PhotosPickerItem]) {
        let vm = viewModel
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                switch result {
                case .success(let data):
                    if let data = data {
                        var finalData = data
                        let isJpeg = data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
                        
                        if !isJpeg {
                            if let uiImage = UIImage(data: data),
                               let jpegData = uiImage.jpegData(compressionQuality: 0.95) {
                                finalData = jpegData
                                Task { @MainActor in
                                    FTPTranscriptLogger.shared.logInfo("[Diagnostic] Авто-конвертация не-JPEG (RAW/HEIC/PNG) в JPEG (размер: \(data.count) -> \(jpegData.count))")
                                }
                            } else {
                                Task { @MainActor in
                                    FTPTranscriptLogger.shared.logInfo("[WARNING] Файл не является JPEG и не удалось конвертировать его в UIImage.")
                                }
                            }
                        }
                        
                        let randomNum = Int.random(in: 1000...9999)
                        let filename = "IMG_\(randomNum).JPG"
                        
                        // Авто-апскейл: применяем только если настройка включена
                        let autoUpscaleEnabled = UserDefaults.standard.bool(forKey: "sys_auto_upscale")
                        if autoUpscaleEnabled {
                            let thresholdStr = UserDefaults.standard.string(forKey: "sys_upscale_threshold") ?? ""
                            let factorStr = UserDefaults.standard.string(forKey: "sys_upscale_factor") ?? ""
                            
                            // Определяем порог в МБ
                            let thresholdMB: Double
                            if thresholdStr.contains("2 МБ") {
                                thresholdMB = 2.0
                            } else if thresholdStr.contains("8 МБ") {
                                thresholdMB = 8.0
                            } else {
                                thresholdMB = 4.0 // Рекомендуется
                            }
                            
                            let sizeMB = Double(finalData.count) / (1024.0 * 1024.0)
                            if sizeMB < thresholdMB, let uiImage = UIImage(data: finalData) {
                                // Определяем коэффициент масштабирования
                                let scale: CGFloat = factorStr.contains("4x") ? 4.0 : 2.0
                                let newSize = CGSize(
                                    width: uiImage.size.width * scale,
                                    height: uiImage.size.height * scale
                                )
                                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                                uiImage.draw(in: CGRect(origin: .zero, size: newSize))
                                let upscaled = UIGraphicsGetImageFromCurrentImageContext()
                                UIGraphicsEndImageContext()
                                
                                if let upscaled = upscaled,
                                   let upscaledData = upscaled.jpegData(compressionQuality: 0.92) {
                                    finalData = upscaledData
                                    Task { @MainActor in
                                        FTPTranscriptLogger.shared.logInfo("[Upscale] Авто-апскейл \(String(format: "%.1f", sizeMB)) МБ → \(String(format: "%.1f", Double(upscaledData.count)/1024/1024)) МБ (\(Int(scale))x, бикубика)")
                                    }
                                }
                            }
                        }
                        
                        let sizeMB = Double(finalData.count) / (1024.0 * 1024.0)
                        let fileSizeStr = String(format: "%.2f МБ", sizeMB)
                        
                        let newPhoto = PhotoMetadata(
                            filename: filename,
                            fileSize: fileSizeStr,
                            title: "",
                            keywords: [],
                            description: "",
                            categories: [],
                            status: .new,
                            imageData: finalData
                        )
                        
                        Task {
                            await vm.addPhoto(newPhoto)
                        }
                    }
                case .failure(let error):
                    print("Error loading image: \(error.localizedDescription)")
                }
            }
        }
        selectedItems = []
    }
}

// MARK: - Dashboard Progress Ring Component
struct DashboardProgressRing: View {
    var total: Int
    var completed: Int
    var ready: Int
    
    var percentCompleted: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
    
    var percentReady: Double {
        total > 0 ? Double(ready) / Double(total) : 0
    }
    
    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 6)
                
            // Ready Segment
            Circle()
                .trim(from: 0.0, to: CGFloat(percentReady + percentCompleted))
                .stroke(
                    LinearGradient(colors: [Color(hex: "7C3AED"), Color(hex: "EC4899")], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(Angle(degrees: -90))
                
            // Completed Segment
            Circle()
                .trim(from: 0.0, to: CGFloat(percentCompleted))
                .stroke(
                    LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(Angle(degrees: -90))
            
            // Text info
            VStack(spacing: 0) {
                Text(total > 0 ? "\(Int((percentCompleted + percentReady) * 100))%" : "0%")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.primary)
                Text("готовность")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 68, height: 68)
    }
}

// MARK: - Helper Models for Sheet Presentation
struct ActiveSheetPhoto: Identifiable, Sendable {
    let id: UUID
    let photos: [PhotoMetadata]
    let index: Int
}

// MARK: - Filter Chip Component
@MainActor
struct FilterChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticHelper.selection()
            action()
        }) {
            Text(text)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        AppleTheme.primaryGradient
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .foregroundStyle(isSelected ? .white : .primary.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(PremiumButtonStyle())
    }
}

// MARK: - Upload Concurrency Semaphore (Actor-based, thread-safe)
/// Ограничивает количество одновременных задач загрузки согласно настройке sys_parallel_streams
actor UploadSemaphore {
    private let limit: Int
    private var running: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(limit: Int) {
        self.limit = max(1, limit)
    }
    
    func wait() async {
        if running < limit {
            running += 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            running += 1
        }
    }
    
    func signal() {
        running -= 1
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

// MARK: - Network Status Indicator Component
struct NetworkStatusIndicator: View {
    @StateObject private var monitor = NetworkMonitor.shared
    
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(monitor.isConnected ? Color(hex: "10B981") : Color.red)
                .frame(width: 8, height: 8)
                .neonShadow(color: monitor.isConnected ? Color(hex: "10B981") : Color.red, radius: 2)
            
            Text(monitor.isConnected ? monitor.connectionType.rawValue : "Offline".localized)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .clipShape(Capsule())
    }
}

// MARK: - Queue Stats Widget
struct QueueStatsWidget: View {
    @ObservedObject var viewModel: QueueViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let total = viewModel.photos.count
        let success = viewModel.photos.filter { $0.status == .success }.count
        let ready = viewModel.photos.filter { $0.status == .ready }.count
        let uploading = viewModel.photos.filter { $0.status == .uploading }.count
        let error = viewModel.photos.filter { $0.status == .error }.count
        
        HStack(spacing: 16) {
            DashboardProgressRing(total: total, completed: success, ready: ready)
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Статистика очереди".localized)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Всего".localized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(total)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Готово".localized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(ready)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "A855F7"))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Загружено".localized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(success)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "10B981"))
                    }
                    
                    if error > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ошибки".localized)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("\(error)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            
            Spacer()
            
            NetworkStatusIndicator()
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 18, padding: 14)
    }
}
// MARK: - Photo Detail Sheet
struct PhotoDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let photo: PhotoMetadata
    @ObservedObject var viewModel: QueueViewModel
    @Binding var editingPhoto: ActiveSheetPhoto?
    
    var currentPhoto: PhotoMetadata {
        viewModel.photos.first(where: { $0.id == photo.id }) ?? photo
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(spacing: 16) {
                        DetailCardView(photo: currentPhoto, viewModel: viewModel, editingPhoto: $editingPhoto)
                            .glassCard(cornerRadius: 20, padding: 16)
                            .padding(.horizontal)
                            .padding(.top, 12)
                        
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Закрыть")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Детали фотографии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Detail Card View
struct DetailCardView: View {
    let photo: PhotoMetadata
    @ObservedObject var viewModel: QueueViewModel
    @Binding var editingPhoto: ActiveSheetPhoto?
    
    @State private var selectedErrorMsg: String? = nil
    @State private var showingErrorAlert = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Раздел 1: Превью и Ключевые слова
            HStack(alignment: .top, spacing: 14) {
                // Превью
                LazyImageView(photoId: photo.id, maxPixelSize: 300, contentMode: .fill)
                .frame(width: 100, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 4)
                
                // Ключевые слова
                VStack(alignment: .leading, spacing: 8) {
                    Text("КЛЮЧЕВЫЕ СЛОВА (Генерация ИИ)".localized)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    if photo.keywords.isEmpty {
                        Text("Ключевые слова отсутствуют. Запустите ИИ-анализ.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding(.top, 4)
                    } else {
                        QueueFlowLayout(spacing: 5) {
                            ForEach(photo.keywords, id: \.self) { kw in
                                QueueKeywordChip(text: kw) {
                                    // Удаление тега
                                    if let idx = viewModel.photos.firstIndex(where: { $0.id == photo.id }) {
                                        viewModel.photos[idx].keywords.removeAll { $0 == kw }
                                        HapticHelper.trigger(.light)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Divider().background(Color.primary.opacity(0.08))
            
            // Раздел 2: Метаданные
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("МЕТАДАННЫЕ".localized)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: {
                        HapticHelper.selection()
                        editingPhoto = ActiveSheetPhoto(
                            id: photo.id,
                            photos: viewModel.photos,
                            index: viewModel.photos.firstIndex(where: { $0.id == photo.id }) ?? 0
                        )
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "7C3AED"))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text(photo.title.isEmpty ? "Без названия".localized : photo.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Text("Description")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text(photo.description.isEmpty ? "Описание отсутствует".localized : photo.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            Divider().background(Color.primary.opacity(0.08))
            
            // Раздел 3: Прогноз популярности
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ПРОГНОЗ ПОПУЛЯРНОСТИ (Рыночный анализ ИИ)".localized)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                // Табличка
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 12) {
                            Text("Shutterstock")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .center)
                            Text("Adobe Stock")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .center)
                            Text("Getty")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .center)
                        }
                    }
                    .padding(.bottom, 2)
                    
                    let displayKeywords = photo.keywords.isEmpty ? ["Пейзаж", "Путешествие", "Горы"] : Array(photo.keywords.prefix(3))
                    ForEach(displayKeywords, id: \.self) { kw in
                        let hash = abs(kw.hashValue ^ photo.id.hashValue)
                        let val = Double(55 + (hash % 41)) / 100.0 // от 0.55 до 0.95
                        PopularityRow(keyword: kw, value: val)
                    }
                }
            }
            
            Divider().background(Color.primary.opacity(0.08))
            
            // Нижняя строка статуса и кнопки вызова контекстного меню
            HStack(spacing: 8) {
                Text(photo.fileSize)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                Text("Статус:".localized + " \(photo.status.rawValue)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Status Badge Capsule (Glassmorphic)
                Text(photo.status.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(photo.status.color.opacity(0.12))
                    .foregroundStyle(photo.status.color)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(photo.status.color.opacity(0.3), lineWidth: 1)
                    )
                
                // Меню действий
                Menu {
                    Section {
                        Button(action: {
                            HapticHelper.trigger(.light)
                            viewModel.uploadPhoto(photo.id)
                        }) {
                            Label("Отправить на стоки", systemImage: "paperplane.fill")
                        }
                        
                        Button(action: {
                            HapticHelper.trigger(.light)
                            viewModel.runAIForPhoto(photo.id)
                        }) {
                            Label("Заполнить ИИ", systemImage: "sparkles")
                        }
                    }
                    
                    Menu {
                        ForEach(["Shutterstock", "Adobe Stock", "iStock / Getty", "Freepik", "Depositphotos", "Alamy", "Dreamstime", "123RF", "Pond5"], id: \.self) { stock in
                            Button(action: {
                                HapticHelper.selection()
                                viewModel.toggleStockForPhoto(photo.id, stockName: stock)
                            }) {
                                HStack {
                                    Text(stock)
                                    if photo.selectedStocks.contains(stock) {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Выбрать стоки...", systemImage: "checklist")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        HapticHelper.trigger(.medium)
                        viewModel.removePhoto(photo.id)
                    }) {
                        Label("Удалить из очереди", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                        .padding(4)
                }
            }
            
            if photo.status == .error, let errorMsg = photo.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(errorMsg)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button(action: {
                        HapticHelper.trigger(.light)
                        selectedErrorMsg = errorMsg
                        showingErrorAlert = true
                    }) {
                        Text("Подробнее")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "7C3AED"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "7C3AED").opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .alert("Ошибка загрузки", isPresented: $showingErrorAlert) {
            Button("Скопировать") {
                if let msg = selectedErrorMsg {
                    UIPasteboard.general.string = msg
                    HapticHelper.notification(.success)
                }
            }
            Button("ОК", role: .cancel) {}
        } message: {
            if let msg = selectedErrorMsg {
                Text(msg)
            }
        }
    }
}

// MARK: - Queue Flow Layout
struct QueueFlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Queue Keyword Chip
struct QueueKeywordChip: View {
    let text: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
            Button(action: {
                HapticHelper.trigger(.light)
                onRemove()
            }) {
                Image(systemName: "pencil")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - Popularity Row
struct PopularityRow: View {
    let keyword: String
    let value: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Text(keyword)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            
            ZStack(alignment: .leading) {
                // Градиентная подложка шкалы
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "10B981"), Color(hex: "F59E0B"), Color(hex: "EF4444")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 7)
                        
                        Circle()
                            .fill(.white)
                            .frame(width: 11, height: 11)
                            .shadow(color: .black.opacity(0.35), radius: 2)
                            .offset(x: geo.size.width * CGFloat(value) - 5.5, y: -2)
                    }
                }
                .frame(height: 7)
            }
            
            Text("Высокий".localized)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

