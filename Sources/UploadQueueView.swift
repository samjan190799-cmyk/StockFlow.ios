import SwiftUI
import PhotosUI
import ImageIO

// MARK: - Queue View Model (MainActor Isolated, Safe Concurrency)
@MainActor
class QueueViewModel: ObservableObject {
    @Published var photos: [PhotoMetadata] = []
    @Published var isAnalyzingAll = false
    @Published var toastMessage = ""
    @Published var showToast = false
    
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
                let imageData = self.photos[idx].imageData ?? Data()
                let result = try await AIManager.shared.analyzePhoto(
                    imageData: imageData,
                    customPrompt: customPrompt,
                    provider: provider,
                    apiKey: apiKey
                )
                
                self.photos[idx].title = result.title
                self.photos[idx].description = result.description
                self.photos[idx].keywords = result.keywords
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
                            let data = self.photos[idx].imageData ?? Data()
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
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!")
            return
        }
        
        photos[idx].status = .uploading
        photos[idx].uploadProgress = 0.0
        photos[idx].errorMessage = nil
        triggerToast("Загрузка файла \(photos[idx].filename)...")
        
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
                    self.triggerToast("Файл \(self.photos[index].filename) успешно загружен на стоки!")
                }
            } catch {
                if let index = self.photos.firstIndex(where: { $0.id == id }) {
                    self.photos[index].status = .error
                    self.photos[index].errorMessage = error.localizedDescription
                    self.triggerToast("Ошибка выгрузки \(self.photos[index].filename): \(error.localizedDescription)")
                }
            }
        }
    }
    
    func uploadAllReady() {
        let readyPhotos = photos.filter { $0.status == .ready }
        guard !readyPhotos.isEmpty else {
            triggerToast("Нет файлов, готовых к отправке.")
            return
        }
        
        guard checkStockCredentials() else {
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!")
            return
        }
        
        // Читаем лимит параллельных потоков из настроек (по умолчанию 3)
        let maxStreams = UserDefaults.standard.integer(forKey: "sys_parallel_streams")
        let streamLimit = maxStreams > 0 ? maxStreams : 3
        
        triggerToast("Началась отправка \(readyPhotos.count) файлов (\(streamLimit) потока)...")
        
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
                            }
                        } catch {
                            if let index = self.photos.firstIndex(where: { $0.id == pId }) {
                                self.photos[index].status = .error
                                self.photos[index].errorMessage = error.localizedDescription
                                self.triggerToast("Ошибка: \(self.photos[index].filename): \(error.localizedDescription)")
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
        guard let data = photo.imageData else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Изображение пустое"])
        }
        
        // Embed metadata (Title, Description, Keywords, Categories) into the image bytes
        let preparedData = writeMetadata(to: data, title: photo.title, description: photo.description, keywords: photo.keywords, categories: photo.categories) ?? data
        
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
                data: preparedData,
                filename: photo.filename,
                pcAddress: pcAddress,
                activePlatforms: activePlatforms,
                progress: progress
            )
            return
        }
        
        var uploadErrors: [String] = []
        var successCount = 0
        
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
            do {
                // FTPSecureClient использует BSD-сокеты + SecureTransport
                // с SSLSetPeerID для TLS Session Resumption (решает проблему Shutterstock)
                try await FTPSecureClient.upload(
                    data: preparedData,
                    filename: photo.filename,
                    host: platform.host,
                    port: 21,
                    username: platform.username,
                    password: password,
                    progress: progress
                )
                successCount += 1
            } catch {
                uploadErrors.append("\(platform.name): \(error.localizedDescription)")
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
    
    
    private func writeMetadata(to imageData: Data, title: String, description: String, keywords: [String], categories: [String]) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        guard let type = CGImageSourceGetType(source) else { return nil }
        
        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(destinationData, type, 1, nil) else { return nil }
        
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        
        // IPTC Dictionary
        let iptcKey = kCGImagePropertyIPTCDictionary as String
        var iptc = (properties[iptcKey] as? [String: Any]) ?? [:]
        iptc[kCGImagePropertyIPTCObjectName as String] = title
        iptc[kCGImagePropertyIPTCCaptionAbstract as String] = description
        iptc[kCGImagePropertyIPTCKeywords as String] = keywords
        
        if !categories.isEmpty {
            iptc[kCGImagePropertyIPTCCategory as String] = categories[0]
            if categories.count > 1 {
                iptc[kCGImagePropertyIPTCSupplementalCategory as String] = Array(categories.dropFirst())
            }
        }
        
        properties[iptcKey] = iptc
        
        // TIFF Dictionary
        let tiffKey = kCGImagePropertyTIFFDictionary as String
        var tiff = (properties[tiffKey] as? [String: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFImageDescription as String] = description
        properties[tiffKey] = tiff
        
        // EXIF Dictionary
        let exifKey = kCGImagePropertyExifDictionary as String
        var exif = (properties[exifKey] as? [String: Any]) ?? [:]
        exif[kCGImagePropertyExifUserComment as String] = description
        properties[exifKey] = exif
        
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        
        if CGImageDestinationFinalize(destination) {
            return destinationData as Data
        }
        return nil
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
    }
    
    func deletePhoto(at offsets: IndexSet) {
        photos.remove(atOffsets: offsets)
    }
    
    func addPhoto(_ photo: PhotoMetadata) {
        photos.append(photo)
    }
    
    func toggleStockForPhoto(_ photoId: UUID, stockName: String) {
        if let idx = photos.firstIndex(where: { $0.id == photoId }) {
            if photos[idx].selectedStocks.contains(stockName) {
                photos[idx].selectedStocks.remove(stockName)
            } else {
                photos[idx].selectedStocks.insert(stockName)
            }
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
}

// MARK: - Upload Queue View
@MainActor
struct UploadQueueView: View {
    @ObservedObject var viewModel: QueueViewModel
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var searchText = ""
    @State private var selectedFilter: PhotoStatus? = nil
    @State private var editingPhoto: ActiveSheetPhoto? = nil
    @State private var showLogViewer = false
    @State private var selectedErrorMsg: String? = nil
    @State private var showingErrorAlert = false
    
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
                
                VStack(spacing: 14) {
                    // Unified Premium Dashboard
                    unifiedDashboardCard
                        .padding(.horizontal)
                        .padding(.top, 10)
                    
                    // Interactive dashed "Drop Zone" for adding photos
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 50,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(AppleTheme.primaryGradient.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(AppleTheme.primaryGradient)
                            }
                            .neonShadow(color: Color(hex: "7C3AED"), radius: 5)
                            
                            VStack(spacing: 2) {
                                Text("Добавить фотографии")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("Коснитесь, чтобы выбрать JPEG, PNG или HEIC")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .glassCard(cornerRadius: 16, padding: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color(hex: "7C3AED").opacity(0.4), Color(hex: "EC4899").opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [6, 4])
                                )
                        )
                    }
                    .padding(.horizontal)
                    .buttonStyle(PremiumButtonStyle())
                    .onChange(of: selectedItems) { newItems in
                        if !newItems.isEmpty {
                            HapticHelper.trigger(.medium)
                        }
                        loadSelectedPhotos(from: newItems)
                    }
                    
                    // Glass Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("Поиск по названию или тегам...", text: $searchText)
                            .font(.system(size: 13))
                    }
                    .glassCard(cornerRadius: 12, padding: 10)
                    .padding(.horizontal)
                    
                    // Filter Chips Scroll
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(text: "Все (\(viewModel.photos.count))", isSelected: selectedFilter == nil) {
                                selectedFilter = nil
                            }
                            
                            ForEach(PhotoStatus.allCases, id: \.self) { status in
                                let count = viewModel.photos.filter { $0.status == status }.count
                                FilterChip(text: "\(status.rawValue) (\(count))", isSelected: selectedFilter == status) {
                                    selectedFilter = status
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 32)
                    
                    // Photo Queue List
                    if filteredPhotos.isEmpty {
                        Spacer()
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
                        .padding(.horizontal)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredPhotos) { photo in
                                    photoRow(photo)
                                        .glassCard(cornerRadius: 16, padding: 12)
                                        .onTapGesture {
                                            HapticHelper.selection()
                                            editingPhoto = ActiveSheetPhoto(
                                                id: photo.id,
                                                photos: viewModel.photos,
                                                index: viewModel.photos.firstIndex(where: { $0.id == photo.id }) ?? 0
                                            )
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
                            .padding(.horizontal)
                            .padding(.bottom, 90)
                        }
                    }
                }
                
                // Floating Action Bar at the bottom
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
                                .font(.system(size: 12, weight: .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppleTheme.primaryGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .neonShadow(color: Color(hex: "7C3AED"), radius: 6)
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
                                .font(.system(size: 12, weight: .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
                                )
                            }
                            .buttonStyle(PremiumButtonStyle())
                        }
                        .padding(10)
                        .glassCard(cornerRadius: 20, padding: 8)
                        .neonShadow(color: Color(hex: "7C3AED"), radius: 12)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }
                
                // Toast notification overlay
                if viewModel.showToast {
                    VStack {
                        Spacer()
                        Text(viewModel.toastMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                ZStack {
                                    Color.black.opacity(0.4)
                                    Rectangle().fill(.ultraThinMaterial)
                                }
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
            .navigationTitle("StockFlow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showLogViewer = true
                    }) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "7C3AED"))
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
    
    // MARK: - Dashboard Card
    private var unifiedDashboardCard: some View {
        HStack(spacing: 18) {
            let total = viewModel.photos.count
            let ready = viewModel.photos.filter { $0.status == .ready }.count
            let success = viewModel.photos.filter { $0.status == .success }.count
            let errors = viewModel.photos.filter { $0.status == .error }.count
            
            DashboardProgressRing(total: total, completed: success, ready: ready)
                .neonShadow(color: Color(hex: "7C3AED"), radius: 5)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Состояние очереди")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                HStack(spacing: 12) {
                    statColumn(title: "Всего", count: total, color: .blue)
                    statColumn(title: "Готово", count: ready, color: Color(hex: "EC4899"))
                    statColumn(title: "Успех", count: success, color: Color(hex: "10B981"))
                    if errors > 0 {
                        statColumn(title: "Ошибка", count: errors, color: .red)
                    }
                }
            }
            Spacer()
        }
        .glassCard(cornerRadius: 16, padding: 14)
    }
    
    private func statColumn(title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
    }
    
    // MARK: - Photo Row Component
    private func photoRow(_ photo: PhotoMetadata) -> some View {
        HStack(spacing: 14) {
            // Larger rounded thumbnail
            Group {
                if let uiImage = photo.uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.04)
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.filename)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if !photo.title.isEmpty {
                    Text(photo.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.75))
                        .lineLimit(1)
                } else {
                    Text("ИИ метаданные отсутствуют")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .italic()
                }
                
                HStack(spacing: 6) {
                    Text(photo.fileSize)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text("Тегов: \(photo.keywords.count)")
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
                }
                
                // Выбранные стоки для фото
                if !photo.selectedStocks.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(photo.selectedStocks).sorted(), id: \.self) { stock in
                            Text(String(stock.prefix(2)).uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                                )
                        }
                    }
                    .padding(.top, 2)
                }
                
                if photo.status == .uploading {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Выгрузка...")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(photo.uploadProgress * 100))%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(photo.status.color)
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 4)
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "7C3AED"), Color(hex: "EC4899")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * CGFloat(photo.uploadProgress), height: 4)
                                    .shadow(color: Color(hex: "7C3AED").opacity(0.5), radius: 2)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.top, 4)
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
                    .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Inline Action Panel (Combined Send, Delete, and Stocks choice)
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
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .padding(4)
            }
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

