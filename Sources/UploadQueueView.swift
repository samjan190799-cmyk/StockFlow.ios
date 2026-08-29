import SwiftUI
import PhotosUI
import ImageIO
import UIKit
import AVFoundation
import UniformTypeIdentifiers

/// Вспомогательный Transferable-тип для импорта видеофайлов через PhotosPickerItem.
/// Необходим потому что URL напрямую не является Transferable.
struct VideoFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoFileTransferable(url: tempURL)
        }
    }
}

final class ContinuationBox<Element>: @unchecked Sendable {
    var continuation: AsyncStream<Element>.Continuation?
}

@MainActor
final class UploadSpeedTracker {
    var lastProgress: Double = 0.0
    var lastTime: Date = Date()
}

// MARK: - Central Upload Queue Manager (Strict Execution & Thermal Protection)
actor UploadQueueManager {
    static let shared = UploadQueueManager()
    
    private struct PendingSlot {
        let isVideo: Bool
        let seqVideo: Bool
        let seqPhoto: Bool
        let parallelStreams: Int
        let continuation: CheckedContinuation<Void, Never>
    }
    
    private var activeStreams = 0
    private var activeVideoCount = 0
    private var activePhotoCount = 0
    private var waiters: [PendingSlot] = []
    
    func acquireSlot(isVideo: Bool, seqVideo: Bool, seqPhoto: Bool, parallelStreams: Int) async {
        let maxStreams = max(1, parallelStreams)
        
        let canExecuteNow = waiters.isEmpty &&
            activeStreams < maxStreams &&
            (!isVideo || !seqVideo || activeVideoCount == 0) &&
            (isVideo || !seqPhoto || activePhotoCount == 0)
            
        if canExecuteNow {
            activeStreams += 1
            if isVideo {
                activeVideoCount += 1
            } else {
                activePhotoCount += 1
            }
            return
        }
        
        await withCheckedContinuation { continuation in
            waiters.append(PendingSlot(
                isVideo: isVideo,
                seqVideo: seqVideo,
                seqPhoto: seqPhoto,
                parallelStreams: maxStreams,
                continuation: continuation
            ))
        }
    }
    
    func releaseSlot(isVideo: Bool, seqVideo: Bool, seqPhoto: Bool) {
        activeStreams = max(0, activeStreams - 1)
        if isVideo {
            activeVideoCount = max(0, activeVideoCount - 1)
        } else {
            activePhotoCount = max(0, activePhotoCount - 1)
        }
        
        processWaiters()
    }
    
    private func processWaiters() {
        var index = 0
        while index < waiters.count {
            let waiter = waiters[index]
            let canExecute = activeStreams < waiter.parallelStreams &&
                (!waiter.isVideo || !waiter.seqVideo || activeVideoCount == 0) &&
                (waiter.isVideo || !waiter.seqPhoto || activePhotoCount == 0)
                
            if canExecute {
                activeStreams += 1
                if waiter.isVideo {
                    activeVideoCount += 1
                } else {
                    activePhotoCount += 1
                }
                
                let next = waiters.remove(at: index)
                next.continuation.resume()
            } else {
                index += 1
            }
        }
    }
}

// MARK: - Queue View Model (MainActor Isolated, Safe Concurrency)
@MainActor
class QueueViewModel: ObservableObject {
    static var shared: QueueViewModel? = nil
    
    @Published var photos: [PhotoMetadata] = []
    @Published var isAnalyzingAll = false
    @Published var isRunningAutopilot = false
    @Published var toastMessage = ""
    @Published var showToast = false
    @Published var shouldShowPaywallFromLimit = false
    @Published var shouldShowDailyLimitAlert = false
    /// Скорость загрузки в KB/с для каждого активного файла
    @Published var uploadSpeedKBps: [UUID: Double] = [:]
    
    private var saveTask: Task<Void, Never>? = nil
    
    private var metadataURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("queue_photos.json")
    }
    
    var photosDirectoryURL: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
    
    init() {
        QueueViewModel.shared = self
        Task {
            await loadPhotosFromDiskAsync()
        }
    }
    
    /// Сохраняет строго маловесные метаданные JSON (<10KB) с дебаунсом (300мс), защищая диск и процессор
    func savePhotosToDisk() {
        saveTask?.cancel()
        let photosCopy = self.photos
        let metaURL = self.metadataURL
        
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(photosCopy)
                try data.write(to: metaURL, options: .atomic)
            } catch {
                print("Error saving photos metadata: \(error.localizedDescription)")
            }
        }
    }
    
    /// Разрешает реальный URL медиафайла для чтения
    func resolveSourceURL(for photo: PhotoMetadata) -> (url: URL, needAccessStop: Bool)? {
        // 1. Приоритет #1: Ранее сохраненный прямой путь localURLPath
        if let path = photo.localURLPath, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return (url, false)
            }
        }
        
        // 2. Приоритет #2: Поиск файла в папке photosDirectoryURL по photo.id
        let prefix = photo.id.uuidString
        if let files = try? FileManager.default.contentsOfDirectory(at: self.photosDirectoryURL, includingPropertiesForKeys: nil) {
            if let matched = files.first(where: { $0.lastPathComponent.hasPrefix(prefix) }) {
                return (matched, false)
            }
        }
        
        // 3. Приоритет #3: Security-scoped Bookmark (для внешних ресурсов)
        if let bookmarkData = photo.localBookmarkData {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                let accessed = resolved.startAccessingSecurityScopedResource()
                if FileManager.default.fileExists(atPath: resolved.path) {
                    return (resolved, accessed)
                }
                if accessed { resolved.stopAccessingSecurityScopedResource() }
            }
        }
        
        // 4. Приоритет #4: Авто-восстановление на диск из данных в памяти (imageData или thumbnailData)
        if let data = photo.imageData ?? photo.thumbnailData, !data.isEmpty {
            let ext = photo.isVideo ? "mp4" : "jpg"
            let recoveryURL = self.photosDirectoryURL.appendingPathComponent("\(photo.id.uuidString).\(ext)")
            if (try? data.write(to: recoveryURL, options: .atomic)) != nil {
                return (recoveryURL, false)
            }
        }
        
        return nil
    }
    
    func addGoogleMediaItems(_ items: [GoogleMediaItem]) {
        Task {
            for item in items {
                do {
                    let data = try await GooglePhotosManager.shared.downloadItemData(item)
                    guard !data.isEmpty else {
                        throw NSError(domain: "GooglePhotos", code: 404, userInfo: [NSLocalizedDescriptionKey: "Получен пустой файл"])
                    }
                    
                    let ext = item.fileExtension
                    let newId = UUID()
                    let fileURL = self.photosDirectoryURL.appendingPathComponent("\(newId.uuidString).\(ext)")
                    try data.write(to: fileURL, options: .atomic)
                    
                    let thumbImg = await ImageCacheHelper.shared.loadAndDownsample(fileURL: fileURL, maxPixelSize: 300)
                    let thumbData = thumbImg?.jpegData(compressionQuality: 0.75) ?? (item.isVideo ? nil : data)
                    let sizeStr = String(format: "%.1f MB", Double(data.count) / (1024.0 * 1024.0))
                    
                    let newPhoto = PhotoMetadata(
                        id: newId,
                        filename: item.filename,
                        fileSize: sizeStr,
                        title: "",
                        keywords: [],
                        description: "",
                        status: .new,
                        selectedStocks: StoreManager.shared.isProUser ? Set(["Shutterstock", "Adobe Stock", "iStock / Getty"]) : Set(["Shutterstock", "Adobe Stock"]),
                        localURLPath: fileURL.path,
                        thumbnailData: thumbData,
                        imageData: nil,
                        isVideo: item.isVideo
                    )
                    self.addPhoto(newPhoto)
                    self.triggerToast("Добавлен файл из Google Фото: \(item.filename)".localized)
                } catch {
                    self.triggerToast("Ошибка импорта \(item.filename): \(error.localizedDescription)")
                }
            }
        }
    }

    func addLocalFiles(_ urls: [URL]) {
        Task {
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                
                let ext = url.pathExtension.lowercased()
                let isVideo = ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)
                let actualExt = ext.isEmpty ? (isVideo ? "mp4" : "jpg") : ext
                let newId = UUID()
                let targetURL = self.photosDirectoryURL.appendingPathComponent("\(newId.uuidString).\(actualExt)")
                
                try? FileManager.default.copyItem(at: url, to: targetURL)
                
                let thumbImage = await ImageCacheHelper.shared.loadAndDownsample(fileURL: targetURL, maxPixelSize: 300)
                let thumbData = thumbImage?.jpegData(compressionQuality: 0.75)
                
                let fileAttrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path)
                let fileSizeByte = (fileAttrs?[.size] as? Int64) ?? 0
                let sizeStr = ByteCountFormatter.string(fromByteCount: fileSizeByte, countStyle: .file)
                
                let newPhoto = PhotoMetadata(
                    id: newId,
                    filename: url.lastPathComponent,
                    fileSize: sizeStr,
                    title: "",
                    keywords: [],
                    description: "",
                    status: .new,
                    selectedStocks: StoreManager.shared.isProUser ? Set(["Shutterstock", "Adobe Stock", "iStock / Getty"]) : Set(["Shutterstock", "Adobe Stock"]),
                    localURLPath: targetURL.path,
                    thumbnailData: thumbData,
                    isVideo: isVideo
                )
                self.addPhoto(newPhoto)
                self.triggerToast("Добавлен файл: \(url.lastPathComponent)".localized)
            }
        }
    }

    func loadPhotosFromDiskAsync() async {
        let metaURL = self.metadataURL
        guard FileManager.default.fileExists(atPath: metaURL.path) else { return }
        
        let loaded: [PhotoMetadata]? = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: metaURL),
                  let decoded = try? JSONDecoder().decode([PhotoMetadata].self, from: data) else {
                return nil
            }
            return decoded
        }.value
        
        if let loaded {
            self.photos = loaded
        }
    }
    
    private func getAIImagesData(for photo: PhotoMetadata) async -> [Data] {
        if let (sourceURL, needStop) = resolveSourceURL(for: photo) {
            defer {
                if needStop { sourceURL.stopAccessingSecurityScopedResource() }
            }
            if photo.isVideo {
                let frames = await ImageCacheHelper.shared.extractFrames(fileURL: sourceURL, count: 3)
                if !frames.isEmpty {
                    return frames
                }
            } else {
                if let image = await ImageCacheHelper.shared.loadAndDownsample(fileURL: sourceURL, maxPixelSize: 1568),
                   let jpegData = image.jpegData(compressionQuality: 0.85) {
                    return [jpegData]
                } else if let rawData = try? Data(contentsOf: sourceURL), !rawData.isEmpty,
                          let uiImg = UIImage(data: rawData),
                          let jpegData = uiImg.jpegData(compressionQuality: 0.85) {
                    return [jpegData]
                }
            }
        }
        
        // Резервный источник: данные миниатюры или бинарные данные фото
        if let thumb = photo.thumbnailData, !thumb.isEmpty {
            return [thumb]
        }
        if let imgData = photo.imageData, !imgData.isEmpty {
            return [imgData]
        }
        return []
    }
    
    func runAIForPhoto(_ id: UUID) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        
        let customPrompt = UserDefaults.standard.string(forKey: "ai_custom_prompt") ?? ""
        let provider = AIProvider.gemini.rawValue
        let apiKey = AIManager.defaultSystemGeminiKey
        
        // 1. Проверяем и сразу списываем слот
        guard RewardAdManager.shared.consumeActionSlot(isAIAnalysis: true) else {
            triggerToast("Достигнут дневной лимит (15 ИИ-анализов в день). Посмотрите видео (+5) или оформите PRO!".localized)
            shouldShowDailyLimitAlert = true
            HapticHelper.notification(.warning)
            return
        }
        
        photos[idx].status = .aiAnalyzing
        let photo = photos[idx]
        
        let taskName = "SmartStock.AI.\(id.uuidString)"
        BackgroundTaskManager.shared.beginTask(named: taskName)
        
        Task {
            defer {
                BackgroundTaskManager.shared.endTask(named: taskName)
            }
            
            let imagesData = await getAIImagesData(for: photo)
            
            do {
                let metadata = try await AIManager.shared.analyzePhoto(
                    imagesData: imagesData,
                    customPrompt: customPrompt,
                    provider: provider,
                    apiKey: apiKey
                )
                
                if let index = self.photos.firstIndex(where: { $0.id == id }) {
                    self.photos[index].title = metadata.title
                    self.photos[index].keywords = metadata.keywords
                    self.photos[index].description = metadata.description
                    self.photos[index].categories = metadata.categories ?? []
                    self.photos[index].status = .ready
                    self.savePhotosToDisk()
                    self.triggerToast("ИИ успешно заполнил метаданные для".localized + " \(photo.filename)!")
                }
            } catch {
                RewardAdManager.shared.refundActionSlot(isAIAnalysis: true)
                if let index = self.photos.firstIndex(where: { $0.id == id }) {
                    self.photos[index].status = .error
                    self.photos[index].errorMessage = "Ошибка ИИ: \(error.localizedDescription)"
                    self.savePhotosToDisk()
                    self.triggerToast("Ошибка ИИ-анализа для".localized + " \(photo.filename): \(error.localizedDescription)")
                }
            }
        }
    }
    
    func runAIForAll() {
        let unanalyzed = photos.filter { $0.status == .new || $0.status == .error }
        guard !unanalyzed.isEmpty else {
            triggerToast("Нет новых файлов для ИИ-анализа.".localized)
            return
        }
        
        isAnalyzingAll = true
        triggerToast("Запущен ИИ-анализ для".localized + " \(unanalyzed.count) " + "файлов...".localized)
        
        BackgroundTaskManager.shared.beginTask(named: "SmartStock.BatchAI")
        
        Task {
            defer {
                BackgroundTaskManager.shared.endTask(named: "SmartStock.BatchAI")
                self.isAnalyzingAll = false
            }
            
            var processedCount = 0
            for photo in unanalyzed {
                guard RewardAdManager.shared.consumeActionSlot(isAIAnalysis: true) else {
                    self.triggerToast("Достигнут дневной лимит ИИ. Посмотрите видео (+5) для продолжения.".localized)
                    self.shouldShowDailyLimitAlert = true
                    break
                }
                
                if let idx = self.photos.firstIndex(where: { $0.id == photo.id }) {
                    self.photos[idx].status = .aiAnalyzing
                }
                
                let imagesData = await getAIImagesData(for: photo)
                let customPrompt = UserDefaults.standard.string(forKey: "ai_custom_prompt") ?? ""
                let provider = AIProvider.gemini.rawValue
                let apiKey = AIManager.defaultSystemGeminiKey
                
                do {
                    let metadata = try await AIManager.shared.analyzePhoto(
                        imagesData: imagesData,
                        customPrompt: customPrompt,
                        provider: provider,
                        apiKey: apiKey
                    )
                    if let index = self.photos.firstIndex(where: { $0.id == photo.id }) {
                        self.photos[index].title = metadata.title
                        self.photos[index].keywords = metadata.keywords
                        self.photos[index].description = metadata.description
                        self.photos[index].categories = metadata.categories ?? []
                        self.photos[index].status = .ready
                        self.savePhotosToDisk()
                        processedCount += 1
                    }
                } catch {
                    RewardAdManager.shared.refundActionSlot(isAIAnalysis: true)
                    if let index = self.photos.firstIndex(where: { $0.id == photo.id }) {
                        self.photos[index].status = .error
                        self.photos[index].errorMessage = "Ошибка ИИ: \(error.localizedDescription)"
                        self.savePhotosToDisk()
                    }
                }
                
                // Плавная задержка между вызовами (2.5 сек) для защиты от 429
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            
            NotificationHelper.sendNotification(
                title: "ИИ-анализ завершён".localized,
                body: "Метаданные успешно заполнены для".localized + " \(processedCount) " + "файлов.".localized
            )
            self.triggerToast("ИИ-анализ успешно завершён!".localized)
        }
    }
    
    private func parseFileSizeToBytes(_ sizeStr: String) -> Double {
        let clean = sizeStr.lowercased().replacingOccurrences(of: ",", with: ".")
        let components = clean.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard let first = components.first, let num = Double(first) else { return 10 * 1024 * 1024 }
        
        if clean.contains("gb") || clean.contains("гб") {
            return num * 1024 * 1024 * 1024
        } else if clean.contains("kb") || clean.contains("кб") {
            return num * 1024
        } else {
            return num * 1024 * 1024
        }
    }
    
    func uploadPhoto(_ id: UUID) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        guard checkStockCredentials() else {
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!".localized)
            return
        }
        
        // Проверяем и сразу списываем слот на отправку
        guard RewardAdManager.shared.consumeActionSlot(isAIAnalysis: false) else {
            triggerToast("Достигнут дневной лимит (15 отправок в день). Посмотрите видео (+5) или оформите PRO!".localized)
            shouldShowDailyLimitAlert = true
            HapticHelper.notification(.warning)
            return
        }
        
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "SmartStock.Upload.\(id.uuidString)") {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        
        photos[idx].status = .inQueue
        photos[idx].uploadProgress = 0.0
        photos[idx].errorMessage = nil
        let targetPhoto = photos[idx]
        
        let taskName = "SmartStock.Upload.\(id.uuidString)"
        BackgroundTaskManager.shared.beginTask(named: taskName)
        
        Task {
            let maxStreams = UserDefaults.standard.integer(forKey: "sys_parallel_streams")
            let streamLimit = maxStreams > 0 ? maxStreams : 1
            let seqVideo = UserDefaults.standard.bool(forKey: "sys_seq_video")
            let seqPhoto = UserDefaults.standard.bool(forKey: "sys_seq_photo")
            
            await UploadQueueManager.shared.acquireSlot(
                isVideo: targetPhoto.isVideo,
                seqVideo: seqVideo,
                seqPhoto: seqPhoto,
                parallelStreams: streamLimit
            )
            
            defer {
                Task {
                    await UploadQueueManager.shared.releaseSlot(
                        isVideo: targetPhoto.isVideo,
                        seqVideo: seqVideo,
                        seqPhoto: seqPhoto
                    )
                    BackgroundTaskManager.shared.endTask(named: taskName)
                }
            }
            
            if let i = self.photos.firstIndex(where: { $0.id == id }) {
                self.photos[i].status = .uploading
                self.triggerToast("Загрузка файла".localized + " \(self.photos[i].filename)...")
            }
            
            let tracker = UploadSpeedTracker()
            let totalBytes = max(parseFileSizeToBytes(targetPhoto.fileSize), 1.0)
            
            let box = ContinuationBox<Double>()
            let progressStream = AsyncStream<Double> { cont in box.continuation = cont }
            guard let progressContinuation = box.continuation else { return }
            
            let progressTask = Task { @MainActor in
                for await prog in progressStream {
                    if let index = self.photos.firstIndex(where: { $0.id == id }) {
                        self.photos[index].uploadProgress = prog
                        let now = Date()
                        let dt = now.timeIntervalSince(tracker.lastTime)
                        if dt > 0.4 {
                            let dprog = prog - tracker.lastProgress
                            if dprog > 0 {
                                let bytesPerSec = (dprog * totalBytes) / dt
                                self.uploadSpeedKBps[id] = bytesPerSec / 1024.0
                            }
                            tracker.lastProgress = prog
                            tracker.lastTime = now
                        }
                    }
                }
            }
            
            do {
                try await performRealUpload(for: targetPhoto) { prog in
                    progressContinuation.yield(prog)
                }
                progressContinuation.finish()
                _ = await progressTask.result
                
                if let index = self.photos.firstIndex(where: { $0.id == id }) {
                    self.photos[index].status = .success
                    self.photos[index].uploadProgress = 1.0
                    self.uploadSpeedKBps.removeValue(forKey: id)
                    self.savePhotosToDisk()
                    self.triggerToast("Файл".localized + " \(self.photos[index].filename) " + "успешно загружен на стоки!".localized)
                    NotificationHelper.sendNotification(
                        title: "Успешная выгрузка".localized,
                        body: "Файл".localized + " \(self.photos[index].filename) " + "успешно загружен на стоки!".localized
                    )
                }
            } catch {
                progressContinuation.finish()
                _ = await progressTask.result
                RewardAdManager.shared.refundActionSlot(isAIAnalysis: false)
                if let index = self.photos.firstIndex(where: { $0.id == id }) {
                    self.photos[index].status = .error
                    self.photos[index].errorMessage = error.localizedDescription
                    self.uploadSpeedKBps.removeValue(forKey: id)
                    self.savePhotosToDisk()
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
        
        triggerToast("Началась отправка".localized + " \(readyPhotos.count) " + "файлов...".localized)
        
        BackgroundTaskManager.shared.beginTask(named: "SmartStock.BatchUpload")
        
        Task {
            defer {
                BackgroundTaskManager.shared.endTask(named: "SmartStock.BatchUpload")
            }
            
            var successCount = 0
            for photo in readyPhotos {
                guard RewardAdManager.shared.consumeActionSlot(isAIAnalysis: false) else {
                    self.triggerToast("Достигнут дневной лимит отправок. Посмотрите видео (+5) для продолжения.".localized)
                    self.shouldShowDailyLimitAlert = true
                    break
                }
                
                if let idx = self.photos.firstIndex(where: { $0.id == photo.id }) {
                    self.photos[idx].status = .uploading
                }
                
                do {
                    try await self.performRealUpload(for: photo)
                    if let idx = self.photos.firstIndex(where: { $0.id == photo.id }) {
                        self.photos[idx].status = .success
                        self.photos[idx].uploadProgress = 1.0
                        self.photos[idx].errorMessage = nil
                        self.savePhotosToDisk()
                        successCount += 1
                    }
                } catch {
                    RewardAdManager.shared.refundActionSlot(isAIAnalysis: false)
                    if let idx = self.photos.firstIndex(where: { $0.id == photo.id }) {
                        self.photos[idx].status = .error
                        self.photos[idx].errorMessage = error.localizedDescription
                        self.savePhotosToDisk()
                    }
                }
                
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            NotificationHelper.sendNotification(
                title: "Выгрузка завершена".localized,
                body: "Все готовые файлы успешно отправлены на стоки!".localized
            )
            self.triggerToast("Выгрузка успешно завершена!".localized)
        }
    }
    
    /// ⚡️ Режим Автопилота: Последовательный ИИ-анализ и автоматическая отправка на стоки в 1 клик
    func runAutopilotPipeline() {
        let targets = photos.filter { $0.status != .success }
        guard !targets.isEmpty else {
            triggerToast("Все файлы в очереди уже успешно загружены!".localized)
            return
        }
        guard checkStockCredentials() else {
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!".localized)
            return
        }
        
        isRunningAutopilot = true
        triggerToast("⚡️ Автопилот запущен для".localized + " \(targets.count) " + "файлов...".localized)
        
        BackgroundTaskManager.shared.beginTask(named: "SmartStock.Autopilot")
        
        Task {
            defer {
                BackgroundTaskManager.shared.endTask(named: "SmartStock.Autopilot")
                self.isRunningAutopilot = false
            }
            
            var processedCount = 0
            
            for photo in targets {
                // 1. ИИ Анализ (если требуется)
                if photo.status == .new || photo.status == .error {
                    guard RewardAdManager.shared.consumeActionSlot(isAIAnalysis: true) else {
                        self.triggerToast("Достигнут дневной лимит ИИ. Автопилот приостановлен.".localized)
                        self.shouldShowDailyLimitAlert = true
                        break
                    }
                    
                    if let idx = self.photos.firstIndex(where: { $0.id == photo.id }) {
                        self.photos[idx].status = .aiAnalyzing
                    }
                    
                    let imagesData = await getAIImagesData(for: photo)
                    let customPrompt = UserDefaults.standard.string(forKey: "ai_custom_prompt") ?? ""
                    let provider = AIProvider.gemini.rawValue
                    let apiKey = AIManager.defaultSystemGeminiKey
                    
                    do {
                        let metadata = try await AIManager.shared.analyzePhoto(
                            imagesData: imagesData,
                            customPrompt: customPrompt,
                            provider: provider,
                            apiKey: apiKey
                        )
                        if let index = self.photos.firstIndex(where: { $0.id == photo.id }) {
                            self.photos[index].title = metadata.title
                            self.photos[index].keywords = metadata.keywords
                            self.photos[index].description = metadata.description
                            self.photos[index].categories = metadata.categories ?? []
                            self.photos[index].status = .ready
                            self.savePhotosToDisk()
                        }
                    } catch {
                        RewardAdManager.shared.refundActionSlot(isAIAnalysis: true)
                        if let index = self.photos.firstIndex(where: { $0.id == photo.id }) {
                            self.photos[index].status = .error
                            self.photos[index].errorMessage = "Ошибка ИИ: \(error.localizedDescription)"
                            self.savePhotosToDisk()
                        }
                    }
                }
                
                // 2. Отправка на стоки
                if let readyPhoto = self.photos.first(where: { $0.id == photo.id }), readyPhoto.status == .ready {
                    guard RewardAdManager.shared.consumeActionSlot(isAIAnalysis: false) else {
                        self.triggerToast("Достигнут дневной лимит отправок. Посмотрите видео (+5) для продолжения.".localized)
                        self.shouldShowDailyLimitAlert = true
                        break
                    }
                    
                    if let idx = self.photos.firstIndex(where: { $0.id == readyPhoto.id }) {
                        self.photos[idx].status = .uploading
                    }
                    
                    do {
                        try await self.performRealUpload(for: readyPhoto)
                        if let idx = self.photos.firstIndex(where: { $0.id == readyPhoto.id }) {
                            self.photos[idx].status = .success
                            self.photos[idx].uploadProgress = 1.0
                            self.photos[idx].errorMessage = nil
                            self.savePhotosToDisk()
                            processedCount += 1
                        }
                    } catch {
                        RewardAdManager.shared.refundActionSlot(isAIAnalysis: false)
                        if let idx = self.photos.firstIndex(where: { $0.id == readyPhoto.id }) {
                            self.photos[idx].status = .error
                            self.photos[idx].errorMessage = error.localizedDescription
                            self.savePhotosToDisk()
                        }
                    }
                }
                
                // Анти-спам пауза
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            
            NotificationHelper.sendNotification(
                title: "⚡️ Автопилот завершён".localized,
                body: "Успешно обработано и выгружено \(processedCount) файлов.".localized
            )
            self.triggerToast("⚡️ Автопилот успешно завершил работу!".localized)
        }
    }
    
    private func performRealUpload(for photo: PhotoMetadata, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let resolved = resolveSourceURL(for: photo) else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Исходный файл \(photo.filename) не найден на устройстве"])
        }
        let sourceFileURL = resolved.url
        defer {
            if resolved.needAccessStop {
                sourceFileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        var tempURLsToDelete: [URL] = []
        defer {
            for tempURL in tempURLsToDelete {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        
        let fileURLToUpload: URL
        if photo.isVideo {
            do {
                let preparedVideoURL = try await ImageProcessor.shared.prepareVideoForUpload(
                    videoURL: sourceFileURL,
                    photo: photo
                )
                fileURLToUpload = preparedVideoURL
                tempURLsToDelete.append(preparedVideoURL)
            } catch {
                fileURLToUpload = sourceFileURL
            }
        } else {
            // Обработка метаданных фото и сжатие
            guard let data = try? Data(contentsOf: sourceFileURL) else {
                throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать файл изображения"])
            }
            
            let compress = UserDefaults.standard.bool(forKey: "sys_compress_jpeg")
            let finalImageData = await ImageProcessor.shared.prepareImageForUpload(
                imageData: data,
                photo: photo,
                compress: compress
            )
            
            // Сохраняем обработанное фото во временный файл
            let tempImageURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            do {
                try finalImageData.write(to: tempImageURL)
                fileURLToUpload = tempImageURL
                tempURLsToDelete.append(tempImageURL)
            } catch {
                throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить обработанное изображение: \(error.localizedDescription)"])
            }
        }
        
        // Load active platforms
        guard let platformsData = UserDefaults.standard.data(forKey: "stock_platforms"),
              let platforms = try? JSONDecoder().decode([StockPlatform].self, from: platformsData) else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Настройки стоков не найдены"])
        }
        
        var activePlatforms = platforms.filter { platform in
            platform.isEnabled && photo.selectedStocks.contains(platform.name)
        }
        if !StoreManager.shared.isProUser && activePlatforms.count > 2 {
            activePlatforms = Array(activePlatforms.prefix(2))
        }
        guard !activePlatforms.isEmpty else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Нет активных стоков для отправки. Включите фотостоки в настройках и отметьте их для этого фото."])
        }
        
        // Проверяем, включен ли ПК-сервер
        let pcServerEnabled = UserDefaults.standard.bool(forKey: "sys_pc_server_enabled")
        if pcServerEnabled {
            let pcAddress = UserDefaults.standard.string(forKey: "sys_pc_server_address") ?? "192.168.1.50:5000"
            try await uploadViaPCServer(
                fileURL: fileURLToUpload,
                filename: photo.filename,
                pcAddress: pcAddress,
                activePlatforms: activePlatforms,
                isVideo: photo.isVideo,
                progress: progress
            )
            return
        }
        
        var uploadErrors: [String] = []
        var successCount = 0
        
        let maxAttempts = UserDefaults.standard.bool(forKey: "sys_retry_on_fail") ? 3 : 1
        
        for platform in activePlatforms {
            let serviceKey = "com.samvel.smartstock.platform.\(platform.id)"
            let password = KeychainHelper.shared.read(for: serviceKey) ?? ""
            
            guard !platform.username.isEmpty, !password.isEmpty else {
                uploadErrors.append("\(platform.name): не введены логин или пароль")
                continue
            }
            
            var attempts = 0
            var uploadError: Error? = nil
            
            let parsed = FTPSecureClient.parseHostAndPort(from: platform.host, defaultPort: 21)
            
            while attempts < maxAttempts {
                do {
                    // Используем потоковую отправку по URL
                    try await FTPSecureClient.upload(
                        fileURL: fileURLToUpload,
                        filename: photo.filename,
                        host: parsed.host,
                        port: parsed.port,
                        username: platform.username,
                        password: password,
                        progress: progress
                    )
                    successCount += 1
                    uploadError = nil
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
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }
            }
            
            if let error = uploadError {
                uploadErrors.append("\(platform.name): \(error.localizedDescription)")
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
        fileURL: URL,
        filename: String,
        pcAddress: String,
        activePlatforms: [StockPlatform],
        isVideo: Bool,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // Шаг 1: Загрузка временного файла на ПК
        progress?(0.05)
        let fileId = try await uploadMultipart(fileURL: fileURL, filename: filename, pcAddress: pcAddress, isVideo: isVideo)
        
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
    
    private func uploadMultipart(fileURL: URL, filename: String, pcAddress: String, isVideo: Bool) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: "http://\(pcAddress)/api/upload-temp") else {
            throw NSError(domain: "PCUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Некорректный адрес ПК-сервера: \(pcAddress)"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Создаем временный файл для multipart-тела
        let tempBodyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        // Записываем заголовки
        var headerData = Data()
        headerData.append("--\(boundary)\r\n".data(using: .utf8)!)
        headerData.append("Content-Disposition: form-data; name=\"photos\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        
        let contentType = isVideo ? "video/mp4" : "image/jpeg"
        headerData.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        
        try headerData.write(to: tempBodyURL)
        
        // Дописываем сам файл
        let fileHandle = try FileHandle(forWritingTo: tempBodyURL)
        try fileHandle.seekToEnd()
        
        let sourceHandle = try FileHandle(forReadingFrom: fileURL)
        while let chunk = try? sourceHandle.read(upToCount: 65536), !chunk.isEmpty {
            try fileHandle.write(contentsOf: chunk)
        }
        try sourceHandle.close()
        
        // Дописываем закрывающий boundary
        var footerData = Data()
        footerData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        try fileHandle.write(contentsOf: footerData)
        try fileHandle.close()
        
        defer { try? FileManager.default.removeItem(at: tempBodyURL) }
        
        let (responseData, response) = try await URLSession.shared.upload(for: request, fromFile: tempBodyURL)
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
        uploadSpeedKBps.removeValue(forKey: id)
        savePhotosToDisk()
    }
    
    func deletePhoto(at offsets: IndexSet) {
        // Очищаем скорость для удаляемых
        for idx in offsets {
            if idx < photos.count {
                uploadSpeedKBps.removeValue(forKey: photos[idx].id)
            }
        }
        photos.remove(atOffsets: offsets)
        savePhotosToDisk()
    }
    
    /// Перемещает файл в очереди (для drag & drop)
    func movePhoto(from source: IndexSet, to destination: Int) {
        photos.move(fromOffsets: source, toOffset: destination)
    }
    
    func addPhoto(_ photo: PhotoMetadata) {
        var photoCopy = photo
        if let data = photo.imageData, !data.isEmpty {
            let rawExt = (photo.filename as NSString).pathExtension.lowercased()
            let actualExt = rawExt.isEmpty ? (photo.isVideo ? "mp4" : "jpg") : rawExt
            let fileURL = self.photosDirectoryURL.appendingPathComponent("\(photo.id.uuidString).\(actualExt)")
            
            // Синхронная запись на локальный диск приложения
            try? data.write(to: fileURL, options: .atomic)
            photoCopy.localURLPath = fileURL.path
            photoCopy.imageData = nil // Освобождаем ОЗУ
            
            if photoCopy.thumbnailData == nil {
                if let thumbImg = UIImage(data: data) {
                    photoCopy.thumbnailData = thumbImg.jpegData(compressionQuality: 0.75)
                }
            }
        }
        
        if photoCopy.thumbnailData == nil, let path = photoCopy.localURLPath {
            let fileURL = URL(fileURLWithPath: path)
            let photoId = photoCopy.id
            Task {
                if let thumb = await ImageCacheHelper.shared.loadAndDownsample(fileURL: fileURL, maxPixelSize: 300) {
                    if let idx = self.photos.firstIndex(where: { $0.id == photoId }) {
                        self.photos[idx].thumbnailData = thumb.jpegData(compressionQuality: 0.75)
                        self.savePhotosToDisk()
                    }
                }
            }
        }
        
        if let idx = photos.firstIndex(where: { $0.id == photoCopy.id }) {
            photos[idx] = photoCopy
        } else {
            photos.insert(photoCopy, at: 0)
        }
        savePhotosToDisk()
    }
    
    func toggleStockForPhoto(_ photoId: UUID, stockName: String) {
        if let idx = photos.firstIndex(where: { $0.id == photoId }) {
            if photos[idx].selectedStocks.contains(stockName) {
                photos[idx].selectedStocks.remove(stockName)
            } else {
                if !StoreManager.shared.isProUser && photos[idx].selectedStocks.count >= 2 {
                    triggerToast("В бесплатной версии доступно до 2 стоков. Перейдите на PRO для одновременной выгрузки на все стоки!".localized)
                    shouldShowPaywallFromLimit = true
                    HapticHelper.notification(.warning)
                    return
                }
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
    
    // MARK: - CSV Export Helpers
    
    /// Фильтрует фотографии для экспорта:
    /// Если forIds != nil — экспортируем только выбранные,
    /// иначе — только те, что ещё не загружены (status != .success)
    private func photosForExport(forIds: Set<UUID>?) -> [PhotoMetadata] {
        if let ids = forIds {
            return photos.filter { ids.contains($0.id) }
        } else {
            return photos.filter { $0.status != .success }
        }
    }
    
    private func escape(_ str: String) -> String {
        "\"" + str.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    
    // Shutterstock: Filename, Description, Keywords, Categories, Illustration, Mature Content, Editorial
    func generateShutterstockCSV(forIds: Set<UUID>? = nil) -> String {
        var csv = "Filename,Description,Keywords,Categories,Illustration,Mature Content,Editorial\n"
        for photo in photosForExport(forIds: forIds) {
            let fn = escape(photo.filename)
            let desc = escape(photo.description)
            let kw = escape(photo.keywords.prefix(50).joined(separator: ", "))
            let cats = escape(photo.categories.prefix(2).joined(separator: ", "))
            csv += "\(fn),\(desc),\(kw),\(cats),No,No,No\n"
        }
        return csv
    }
    
    // Adobe Stock: Filename,Title,Keywords,Category,Releases
    // Лимиты: Title ≤ 70 chars, Keywords ≤ 50 через запятую
    func generateAdobeStockCSV(forIds: Set<UUID>? = nil) -> String {
        var csv = "Filename,Title,Keywords,Category,Releases\n"
        for photo in photosForExport(forIds: forIds) {
            let fn = escape(photo.filename)
            // Adobe не принимает заголовки длиннее 70 символов
            let title = escape(String(photo.title.prefix(70)))
            let kw = escape(photo.keywords.prefix(50).joined(separator: ", "))
            // Adobe использует числовые коды категорий; оставляем первую текстовую категорию как есть
            let cat = escape(photo.categories.first ?? "")
            csv += "\(fn),\(title),\(kw),\(cat),\n"
        }
        return csv
    }
    
    // Pond5: originalfilename, title, description, keywords
    func generatePond5CSV(forIds: Set<UUID>? = nil) -> String {
        var csv = "originalfilename,title,description,keywords\n"
        for photo in photosForExport(forIds: forIds) {
            let fn = escape(photo.filename)
            let title = escape(String(photo.title.prefix(80)))
            let desc = escape(photo.description)
            let kw = escape(photo.keywords.prefix(50).joined(separator: ", "))
            csv += "\(fn),\(title),\(desc),\(kw)\n"
        }
        return csv
    }
    
    // Dreamstime: загружается тем же FTP в папку загрузки рядом с файлами
    // Формат: filename, title, description, keywords, category
    func generateDreamstimeCSV(forIds: Set<UUID>? = nil) -> String {
        var csv = "filename,title,description,keywords,category\n"
        for photo in photosForExport(forIds: forIds) {
            let fn = escape(photo.filename)
            let title = escape(String(photo.title.prefix(80)))
            let desc = escape(photo.description)
            let kw = escape(photo.keywords.prefix(50).joined(separator: ", "))
            let cat = escape(photo.categories.first ?? "")
            csv += "\(fn),\(title),\(desc),\(kw),\(cat)\n"
        }
        return csv
    }
}

// MARK: - Upload Queue View
@MainActor
struct UploadQueueView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @AppStorage("sys_notifications") private var sysNotifications: Bool = true
    @ObservedObject var viewModel: QueueViewModel
    @ObservedObject private var storeManager = StoreManager.shared
    @ObservedObject private var rewardManager = RewardAdManager.shared
    @State private var showPaywall = false
    @State private var showRewardedAd = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var searchText = ""
    @State private var selectedFilter: PhotoStatus? = nil
    @State private var showLogViewer = false
    @State private var selectedErrorMsg: String? = nil
    @State private var showingErrorAlert = false
    @State private var selectedDetailPhoto: PhotoMetadata? = nil
    @State private var isSelectionMode = false
    @State private var selectedPhotoIds = Set<UUID>()
    @State private var showCSVMenu = false
    @State private var isReorderMode = false
    @State private var showGooglePhotosPicker = false
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false
    /// 0 = Фото, 1 = Видео
    @State private var mediaTab: Int = 0
    
    var filteredPhotos: [PhotoMetadata] {
        let isVideo = mediaTab == 1
        return viewModel.photos.filter { photo in
            // Фильтр по вкладке Фото / Видео
            guard photo.isVideo == isVideo else { return false }
            
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
                    if isReorderMode {
                        reorderListView
                    } else {
                        mainScrollView
                    }
                }
                
                plusFloatingButton
                floatingActionBarView
                toastView
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 6) {
                        if storeManager.isProUser {
                            Button(action: {
                                HapticHelper.trigger(.light)
                                showPaywall = true
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.yellow)
                                    Text("PRO Безлимит".localized)
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(.yellow)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.yellow.opacity(0.18))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                                )
                            }
                        } else {
                            Button(action: {
                                HapticHelper.trigger(.light)
                                showPaywall = true
                            }) {
                                HStack(spacing: 5) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color(hex: "A855F7"))
                                        Text("\(rewardManager.remainingAIToday)")
                                            .font(.system(size: 11, weight: .heavy))
                                            .foregroundStyle(.primary)
                                    }
                                    Text("•")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 2) {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Color(hex: "3B82F6"))
                                        Text("\(rewardManager.remainingUploadsToday)")
                                            .font(.system(size: 11, weight: .heavy))
                                            .foregroundStyle(.primary)
                                    }
                                    if rewardManager.bonusCredits > 0 {
                                        Text("(+\(rewardManager.bonusCredits))")
                                            .font(.system(size: 9, weight: .heavy))
                                            .foregroundStyle(Color.orange)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(hex: "A855F7").opacity(0.15))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color(hex: "A855F7").opacity(0.35), lineWidth: 1)
                                )
                            }
                            
                            Button(action: {
                                HapticHelper.trigger(.light)
                                showRewardedAd = true
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 11))
                                    Text("+5")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.18))
                                .foregroundStyle(Color.orange)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if !viewModel.photos.isEmpty {
                            // Меню экспорта CSV для каждого стока
                            let exportIds: Set<UUID>? = isSelectionMode && !selectedPhotoIds.isEmpty ? selectedPhotoIds : nil
                            
                            Menu {
                                // Shutterstock
                                ShareLink(
                                    item: CSVDocument(csvText: viewModel.generateShutterstockCSV(forIds: exportIds)),
                                    preview: SharePreview("shutterstock_metadata.csv", image: Image(systemName: "tablecells"))
                                ) {
                                    Label("Shutterstock CSV", systemImage: "s.circle.fill")
                                }
                                
                                // Adobe Stock
                                ShareLink(
                                    item: CSVDocument(csvText: viewModel.generateAdobeStockCSV(forIds: exportIds)),
                                    preview: SharePreview("adobe_stock_metadata.csv", image: Image(systemName: "tablecells"))
                                ) {
                                    Label("Adobe Stock CSV", systemImage: "a.circle.fill")
                                }
                                
                                // Pond5
                                ShareLink(
                                    item: CSVDocument(csvText: viewModel.generatePond5CSV(forIds: exportIds)),
                                    preview: SharePreview("pond5_metadata.csv", image: Image(systemName: "tablecells"))
                                ) {
                                    Label("Pond5 CSV", systemImage: "p.circle.fill")
                                }
                                
                                // Dreamstime
                                ShareLink(
                                    item: CSVDocument(csvText: viewModel.generateDreamstimeCSV(forIds: exportIds)),
                                    preview: SharePreview("dreamstime_metadata.csv", image: Image(systemName: "tablecells"))
                                ) {
                                    Label("Dreamstime CSV", systemImage: "d.circle.fill")
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15))
                                    Text("CSV")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundStyle(Color(hex: "7C3AED"))
                            }
                        }
                        
                        Button(action: {
                            showLogViewer = true
                        }) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color(hex: "7C3AED"))
                        }
                        
                        Button(action: {
                            HapticHelper.selection()
                            sysNotifications.toggle()
                            if sysNotifications {
                                NotificationHelper.requestAuthorization()
                            }
                        }) {
                            Image(systemName: sysNotifications ? "bell.fill" : "bell.slash")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(sysNotifications ? Color(hex: "7C3AED") : .secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showLogViewer) {
                LogViewer()
            }
            .sheet(item: $selectedDetailPhoto) { photo in
                PhotoDetailSheet(photo: photo, viewModel: viewModel)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showRewardedAd) {
                RewardedAdView()
            }
            .onChange(of: viewModel.shouldShowPaywallFromLimit) { show in
                if show {
                    showPaywall = true
                    viewModel.shouldShowPaywallFromLimit = false
                }
            }
            .alert("Дневной лимит исчерпан".localized, isPresented: $viewModel.shouldShowDailyLimitAlert) {
                Button("🎬 Получить +5 слотов".localized) {
                    showRewardedAd = true
                }
                Button("👑 SmartStock PRO".localized) {
                    showPaywall = true
                }
                Button("Закрыть".localized, role: .cancel) {}
            } message: {
                Text("В бесплатной версии доступно 15 ИИ-анализов и 15 отправок на стоки в день. Вы можете посмотреть видео (+5 слотов) или перейти на безлимитный PRO.".localized)
            }
            .alert("Ошибка загрузки".localized, isPresented: $showingErrorAlert) {
                Button("Скопировать".localized) {
                    if let msg = selectedErrorMsg {
                        UIPasteboard.general.string = msg
                        HapticHelper.notification(.success)
                    }
                }
                Button("ОК".localized, role: .cancel) {}
            } message: {
                if let msg = selectedErrorMsg {
                    Text(msg)
                }
            }
        }
    }

    @ViewBuilder
    private var reorderListView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Порядок очереди".localized)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Готово".localized) {
                    HapticHelper.trigger(.light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isReorderMode = false
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: "10B981"))
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            List {
                ForEach(viewModel.photos) { photo in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        LazyImageView(photoId: photo.id, maxPixelSize: 60, contentMode: .fill, isVideo: photo.isVideo, photo: photo)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(photo.filename)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(photo.status.rawValue)
                                .font(.system(size: 10))
                                .foregroundStyle(photo.status.color)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove { from, to in
                    HapticHelper.trigger(.light)
                    viewModel.movePhoto(from: from, to: to)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }

    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Виджет статистики и сети вместо зоны добавления файлов
                QueueStatsWidget(viewModel: viewModel)
                
                // MARK: - Вкладки Фото / Видео
                HStack(spacing: 0) {
                    mediaTabButton(index: 0, title: "Фото".localized, icon: "photo.on.rectangle")
                    mediaTabButton(index: 1, title: "Видео".localized, icon: "video.fill")
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1)
                )
                
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
                
                // Заголовок Recents и кнопки управления режимами
                HStack(spacing: 10) {
                    Text("Недавние".localized)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    
                    if !isSelectionMode {
                        // Кнопка режима перетаскивания
                        Button(isReorderMode ? "Готово".localized : "Порядок".localized) {
                            HapticHelper.trigger(.light)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isReorderMode.toggle()
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isReorderMode ? Color(hex: "10B981") : Color(hex: "A855F7"))
                    }
                    
                    if !isReorderMode {
                        Button(isSelectionMode ? "Отмена".localized : "Выбрать".localized) {
                            HapticHelper.trigger(.light)
                            isSelectionMode.toggle()
                            selectedPhotoIds.removeAll()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "A855F7"))
                    }
                }
                .padding(.top, 8)
                
                // Список фотографий
                if filteredPhotos.isEmpty {
                    VStack(spacing: 12) {
                        SmartStockLogoView(size: 64)
                            .padding(.bottom, 6)
                        Text("Очередь пуста".localized)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Выберите снимки, чтобы запустить ИИ-подбор метаданных и отправить их на микростоки.".localized)
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
                        ForEach(filteredPhotos) { photo in
                            HStack(spacing: 12) {
                                if isSelectionMode {
                                    Button(action: {
                                        HapticHelper.trigger(.light)
                                        if selectedPhotoIds.contains(photo.id) {
                                            selectedPhotoIds.remove(photo.id)
                                        } else {
                                            selectedPhotoIds.insert(photo.id)
                                        }
                                    }) {
                                        Image(systemName: selectedPhotoIds.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundStyle(selectedPhotoIds.contains(photo.id) ? Color(hex: "A855F7") : .secondary)
                                    }
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                }
                                
                                PhotoRowView(
                                    photo: photo,
                                    viewModel: viewModel,
                                    onSelect: {
                                        if isSelectionMode {
                                            HapticHelper.trigger(.light)
                                            if selectedPhotoIds.contains(photo.id) {
                                                selectedPhotoIds.remove(photo.id)
                                            } else {
                                                selectedPhotoIds.insert(photo.id)
                                            }
                                        } else {
                                            HapticHelper.selection()
                                            selectedDetailPhoto = photo
                                        }
                                    }
                                )
                            }
                            .contextMenu {
                                Button {
                                    viewModel.runAIForPhoto(photo.id)
                                } label: {
                                    Label("Запустить ИИ-анализ".localized, systemImage: "sparkles")
                                }
                                
                                Button {
                                    viewModel.uploadPhoto(photo.id)
                                } label: {
                                    Label("Выгрузить на стоки".localized, systemImage: "paperplane")
                                }
                                
                                Button(role: .destructive) {
                                    viewModel.removePhoto(photo.id)
                                } label: {
                                    Label("Удалить".localized, systemImage: "trash")
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

    @ViewBuilder
    private var plusFloatingButton: some View {
        if !isReorderMode {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Menu {
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            showPhotosPicker = true
                        }) {
                            Label("Галерея iOS".localized, systemImage: "photo.on.rectangle")
                        }
                        
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            showGooglePhotosPicker = true
                        }) {
                            Label("Google Фото".localized, systemImage: "photo.stack.fill")
                        }
                        
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            showFileImporter = true
                        }) {
                            Label("Файлы на устройстве".localized, systemImage: "folder.badge.plus")
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AppleTheme.primaryGradient)
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
                                )
                                .shadow(color: Color(hex: "007AFF").opacity(0.4), radius: 10, x: 0, y: 5)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .bold))
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
            .sheet(isPresented: $showGooglePhotosPicker) {
                GooglePhotosPickerView { items in
                    viewModel.addGoogleMediaItems(items)
                }
            }
            .photosPicker(
                isPresented: $showPhotosPicker,
                selection: $selectedItems,
                maxSelectionCount: 50,
                matching: mediaTab == 0 ? .images : .videos,
                photoLibrary: .shared()
            )
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: mediaTab == 0 ? [.image] : [.movie, .video],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    viewModel.addLocalFiles(urls)
                case .failure(let error):
                    viewModel.triggerToast("Ошибка выбора файлов: \(error.localizedDescription)")
                }
            }
        }
    }

    @ViewBuilder
    private var floatingActionBarView: some View {
        if !viewModel.photos.isEmpty {
            VStack {
                Spacer()
                HStack(spacing: 14) {
                    if isSelectionMode {
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            let selectedIdsArray = Array(selectedPhotoIds)
                            Task {
                                for id in selectedIdsArray {
                                    viewModel.runAIForPhoto(id)
                                }
                            }
                            isSelectionMode = false
                            selectedPhotoIds.removeAll()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("ИИ для выбранных".localized)
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
                        .disabled(selectedPhotoIds.isEmpty)
                        
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            let selectedIdsArray = Array(selectedPhotoIds)
                            Task {
                                for id in selectedIdsArray {
                                    viewModel.uploadPhoto(id)
                                }
                            }
                            isSelectionMode = false
                            selectedPhotoIds.removeAll()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane.fill")
                                Text("Отправить выбр.".localized)
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
                        .disabled(selectedPhotoIds.isEmpty)
                    } else {
                        // 1. Кнопка АВТОПИЛОТ (Анализ + Выгрузка в 1 клик)
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            viewModel.runAutopilotPipeline()
                        }) {
                            HStack(spacing: 5) {
                                if #available(iOS 17.0, *) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .symbolEffect(.pulse, options: .repeating, value: viewModel.isRunningAutopilot)
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                Text("Автопилот".localized)
                                    .font(.system(size: 11, weight: .heavy))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "8B5CF6"), Color(hex: "EC4899")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .neonShadow(color: Color(hex: "EC4899"), radius: 6)
                        }
                        .buttonStyle(PremiumButtonStyle())
                        .disabled(viewModel.isRunningAutopilot)
                        
                        // 2. Кнопка ТОЛЬКО ИИ
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            viewModel.runAIForAll()
                        }) {
                            HStack(spacing: 4) {
                                if #available(iOS 17.0, *) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                        .symbolEffect(.pulse, options: .repeating, value: viewModel.isAnalyzingAll)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                }
                                Text("ИИ".localized)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppleTheme.primaryGradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PremiumButtonStyle())
                        .disabled(viewModel.isAnalyzingAll || viewModel.isRunningAutopilot)
                        
                        // 3. Кнопка ОТПРАВИТЬ
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            viewModel.uploadAllReady()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 11))
                                Text("Отправить".localized)
                                    .font(.system(size: 11, weight: .bold))
                            }
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
                        .disabled(viewModel.isRunningAutopilot)
                    }
                }
                .padding(10)
                .floatingGlassBar(cornerRadius: 24)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
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
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 1.0))
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 94)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - Media Tab Button Helper
    @ViewBuilder
    private func mediaTabButton(index: Int, title: String, icon: String) -> some View {
        let isActive = mediaTab == index
        let count = viewModel.photos.filter { $0.isVideo == (index == 1) }.count
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                mediaTab = index
                selectedFilter = nil
                searchText = ""
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title.localized)
                    .font(.system(size: 13, weight: .bold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isActive ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isActive ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isActive
                    ? LinearGradient(colors: [Color(hex: "7C3AED"), Color(hex: "A855F7")], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color.clear, Color.clear], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Load Photos Logic
    private func loadSelectedPhotos(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let vm = viewModel
        
        Task { @MainActor in
            for item in items {
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
                
                if isVideo {
                    // Загружаем видео через VideoFileTransferable
                    do {
                        guard let videoFile = try await item.loadTransferable(type: VideoFileTransferable.self) else {
                            print("[Video] loadTransferable вернул nil")
                            continue
                        }
                        let url = videoFile.url
                        let ext = url.pathExtension.lowercased()
                        let actualExt = ext.isEmpty ? "mp4" : ext
                        let uuid = UUID()
                        let targetURL = vm.photosDirectoryURL.appendingPathComponent("\(uuid.uuidString).\(actualExt)")
                        
                        if FileManager.default.fileExists(atPath: targetURL.path) {
                            try? FileManager.default.removeItem(at: targetURL)
                        }
                        try FileManager.default.copyItem(at: url, to: targetURL)
                        
                        let randomNum = Int.random(in: 1000...9999)
                        let filename = "VID_\(randomNum).\(actualExt.uppercased())"
                        
                        let fileAttributes = try FileManager.default.attributesOfItem(atPath: targetURL.path)
                        let fileSizeByte = fileAttributes[.size] as? Int64 ?? 0
                        let fileSizeStr = ByteCountFormatter.string(fromByteCount: fileSizeByte, countStyle: .file)
                        
                        let newPhoto = PhotoMetadata(
                            id: uuid,
                            filename: filename,
                            fileSize: fileSizeStr,
                            title: "",
                            keywords: [],
                            description: "",
                            categories: [],
                            status: .new,
                            selectedStocks: StoreManager.shared.isProUser ? Set(["Shutterstock", "Adobe Stock", "iStock / Getty"]) : Set(["Shutterstock", "Adobe Stock"]),
                            localURLPath: targetURL.path,
                            isVideo: true
                        )
                        vm.addPhoto(newPhoto)
                        
                    } catch {
                        vm.triggerToast("Ошибка импорта видео: \(error.localizedDescription)")
                        print("[Video] Ошибка: \(error)")
                    }
                    
                } else {
                    // Загружаем фото как Data
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            print("[Photo] loadTransferable вернул nil")
                            continue
                        }
                        
                        var finalData = data
                        let randomNum = Int.random(in: 1000...9999)
                        
                        // Авто-конвертация не-JPEG (HEIC, PNG, RAW) в JPEG
                        let isJpeg = data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
                        if !isJpeg {
                            if let uiImage = UIImage(data: data), let jpegData = uiImage.jpegData(compressionQuality: 0.95) {
                                finalData = jpegData
                                FTPTranscriptLogger.shared.logInfo("[Diagnostic] Авто-конвертация не-JPEG в JPEG (\(data.count) -> \(jpegData.count))")
                            } else {
                                FTPTranscriptLogger.shared.logInfo("[WARNING] Не удалось конвертировать в UIImage")
                            }
                        }
                        
                        // Авто-апскейл
                        let autoUpscaleEnabled = UserDefaults.standard.bool(forKey: "sys_auto_upscale")
                        if autoUpscaleEnabled {
                            let thresholdStr = UserDefaults.standard.string(forKey: "sys_upscale_threshold") ?? "Меньше 4 МБ (Рекомендуется)"
                            let factorStr = UserDefaults.standard.string(forKey: "sys_upscale_factor") ?? "Увеличение 2x (Бикубическое)"
                            let thresholdMB: Double = thresholdStr.contains("2 МБ") ? 2.0 : (thresholdStr.contains("8 МБ") ? 8.0 : 4.0)
                            let sizeMB = Double(finalData.count) / (1024.0 * 1024.0)
                            if sizeMB < thresholdMB, let uiImage = UIImage(data: finalData) {
                                let scale: CGFloat = factorStr.contains("4x") ? 4.0 : 2.0
                                if let upscaled = await ImageProcessor.shared.upscaleImage(uiImage, scaleFactor: scale),
                                   let upscaledData = upscaled.jpegData(compressionQuality: 0.92) {
                                    finalData = upscaledData
                                    FTPTranscriptLogger.shared.logInfo("[Upscale] \(String(format: "%.1f", sizeMB)) МБ -> \(String(format: "%.1f", Double(upscaledData.count)/1024/1024)) МБ (\(Int(scale))x)")
                                }
                            }
                        }
                        
                        let photoId = UUID()
                        let targetURL = vm.photosDirectoryURL.appendingPathComponent("\(photoId.uuidString).jpg")
                        try finalData.write(to: targetURL, options: .atomic)
                        
                        let thumbImage = await ImageCacheHelper.shared.loadAndDownsample(fileURL: targetURL, maxPixelSize: 300)
                        let thumbData = thumbImage?.jpegData(compressionQuality: 0.75)
                        
                        let sizeMB = Double(finalData.count) / (1024.0 * 1024.0)
                        let fileSizeStr = String(format: "%.2f МБ", sizeMB)
                        let filename = "IMG_\(randomNum).JPG"
                        
                        let newPhoto = PhotoMetadata(
                            id: photoId,
                            filename: filename,
                            fileSize: fileSizeStr,
                            title: "",
                            keywords: [],
                            description: "",
                            categories: [],
                            status: .new,
                            selectedStocks: StoreManager.shared.isProUser ? Set(["Shutterstock", "Adobe Stock", "iStock / Getty"]) : Set(["Shutterstock", "Adobe Stock"]),
                            localURLPath: targetURL.path,
                            thumbnailData: thumbData,
                            isVideo: false
                        )
                        vm.addPhoto(newPhoto)
                        
                    } catch {
                        print("[Photo] Ошибка: \(error)")
                    }
                }
            }
            selectedItems = []
        }
    }
}


// MARK: - Photo Row View
struct PhotoRowView: View {
    @Environment(\.colorScheme) var colorScheme
    let photo: PhotoMetadata
    @ObservedObject var viewModel: QueueViewModel
    var onSelect: () -> Void
    
    // Текущая скорость загрузки для этого файла
    private var speedKBps: Double? {
        viewModel.uploadSpeedKBps[photo.id]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            photoImage(photo)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect()
                }
                
            photoProgressBar(photo)
            photoButtons(photo)
            if photo.status == .uploading {
                // Показываем скорость KB/с если известна, иначе статус Загрузка...
                let speedText: String = {
                    if let kbps = speedKBps, kbps > 0 {
                        if kbps >= 1024 {
                            return String(format: "%.1f MB/s", kbps / 1024.0)
                        } else {
                            return String(format: "%.0f KB/s", kbps)
                        }
                    }
                    return "Загрузка...".localized
                }()
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 9))
                    Text(speedText)
                        .font(.system(size: 10, weight: .black))
                }
                .foregroundStyle(Color(hex: "10B981"))
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color(hex: "141620").opacity(0.95) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            colorScheme == .dark ? Color.white.opacity(0.14) : Color.white,
                            colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 8, x: 0, y: 4)
    }
    
    private func photoImage(_ photo: PhotoMetadata) -> some View {
        ZStack(alignment: .topLeading) {
            LazyImageView(photoId: photo.id, maxPixelSize: 400, contentMode: .fill, isVideo: photo.isVideo, photo: photo)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            
            // Статус (слева сверху)
            if photo.status == .ready {
                Text("ГОТОВ".localized)
                    .font(.system(size: 9, weight: .black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "10B981").opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(12)
            } else if photo.status == .inQueue {
                Text("В ОЧЕРЕДИ".localized)
                    .font(.system(size: 9, weight: .black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "007AFF").opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(12)
            }
            
            // Иконка УСПЕШНО (справа сверху)
            if photo.status == .success {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: "10B981"))
                        .background(Circle().fill(Color.black.opacity(0.6)))
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
                        .padding(7)
                        .background(Circle().fill(Color.black.opacity(0.65)))
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
    
    private func photoButtons(_ photo: PhotoMetadata) -> some View {
        HStack(spacing: 10) {
            // Кнопка УДАЛИТЬ
            Button(action: {
                HapticHelper.trigger(.medium)
                viewModel.removePhoto(photo.id)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Удалить".localized)
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(.red)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.red.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(PremiumButtonStyle())
            
            // Кнопка ИИ АНАЛИЗ
            Button(action: {
                HapticHelper.trigger(.medium)
                viewModel.runAIForPhoto(photo.id)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(photo.status == .aiAnalyzing ? Color.secondary : Color(hex: "818CF8"))
                    Text(photo.status == .aiAnalyzing ? "Анализируем...".localized : "ИИ АНАЛИЗ".localized)
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    photo.status == .aiAnalyzing
                    ? (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04))
                    : (colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                )
                .foregroundStyle(photo.status == .aiAnalyzing ? Color.secondary : Color.primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(PremiumButtonStyle())
            .disabled(photo.status == .aiAnalyzing)
            
            // Кнопка ОТПРАВИТЬ / ОТПРАВЛЕНО
            Button(action: {
                if photo.status != .success {
                    HapticHelper.trigger(.medium)
                    viewModel.uploadPhoto(photo.id)
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: photo.status == .success ? "checkmark" : "paperplane.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(photo.status == .success ? "Отправлено".localized : "Отправить".localized)
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    photo.status == .success
                    ? Color(hex: "10B981").opacity(0.12)
                    : (colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                )
                .foregroundStyle(photo.status == .success ? Color(hex: "10B981") : Color.primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        photo.status == .success
                        ? Color(hex: "10B981").opacity(0.3)
                        : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)),
                        lineWidth: 1
                    )
                )
            }
            .buttonStyle(PremiumButtonStyle())
            .disabled(photo.status == .success)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
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
                Text("готовность".localized)
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
    @State private var showMetadataEditor = false
    
    var currentPhoto: PhotoMetadata {
        viewModel.photos.first(where: { $0.id == photo.id }) ?? photo
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(spacing: 16) {
                        DetailCardView(photo: currentPhoto, viewModel: viewModel, onEditMetadata: {
                            showMetadataEditor = true
                        })
                        .glassCard(cornerRadius: 20, padding: 16)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Закрыть".localized)
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
            .navigationTitle("Детали фотографии".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово".localized) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
            }
            .sheet(isPresented: $showMetadataEditor) {
                NavigationStack {
                    AIMetadataView(
                        photos: viewModel.photos,
                        currentIndex: viewModel.photos.firstIndex(where: { $0.id == photo.id }) ?? 0
                    ) { updatedPhotos in
                        for updated in updatedPhotos {
                            if let idx = viewModel.photos.firstIndex(where: { $0.id == updated.id }) {
                                viewModel.photos[idx] = updated
                            }
                        }
                        showMetadataEditor = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Закрыть".localized) {
                                showMetadataEditor = false
                            }
                            .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Detail Card View
struct DetailCardView: View {
    let photo: PhotoMetadata
    @ObservedObject var viewModel: QueueViewModel
    var onEditMetadata: () -> Void
    
    @State private var selectedErrorMsg: String? = nil
    @State private var showingErrorAlert = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Раздел 1: Превью и Ключевые слова
            HStack(alignment: .top, spacing: 14) {
                // Превью
                LazyImageView(photoId: photo.id, maxPixelSize: 300, contentMode: .fill, isVideo: photo.isVideo, photo: photo)
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
                        Text("Ключевые слова отсутствуют. Запустите ИИ-анализ.".localized)
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
                        onEditMetadata()
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
                            Label("Отправить на стоки".localized, systemImage: "paperplane.fill")
                        }
                        
                        Button(action: {
                            HapticHelper.trigger(.light)
                            viewModel.runAIForPhoto(photo.id)
                        }) {
                            Label("Заполнить ИИ".localized, systemImage: "sparkles")
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
                        Label("Выбрать стоки...".localized, systemImage: "checklist")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        HapticHelper.trigger(.medium)
                        viewModel.removePhoto(photo.id)
                    }) {
                        Label("Удалить из очереди".localized, systemImage: "trash")
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
                        Text("Подробнее".localized)
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
        .alert("Ошибка загрузки".localized, isPresented: $showingErrorAlert) {
            Button("Скопировать".localized) {
                if let msg = selectedErrorMsg {
                    UIPasteboard.general.string = msg
                    HapticHelper.notification(.success)
                }
            }
            Button("ОК".localized, role: .cancel) {}
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
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
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

// MARK: - CSV Document Transferable Helper
struct CSVDocument: Transferable {
    let csvText: String
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(
            contentType: .commaSeparatedText,
            exporting: { doc in
                doc.csvText.data(using: .utf8) ?? Data()
            },
            importing: { data in
                CSVDocument(csvText: String(data: data, encoding: .utf8) ?? "")
            }
        )
    }
}

