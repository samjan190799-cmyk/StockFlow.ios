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

    /// Похожие кадры серии: для каждого файла — другие файлы из его группы (заполняется перед пакетным ИИ-анализом)
    private var seriesSiblings: [UUID: [UUID]] = [:]

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
            let total = items.count
            var imported = 0
            var failed = 0
            var lastErrorText = ""
            let journal = FTPTranscriptLogger.shared

            // Импорт продолжается, даже если пользователь ненадолго свернул приложение
            BackgroundTaskManager.shared.beginTask(named: "SmartStock.GoogleImport")
            defer { BackgroundTaskManager.shared.endTask(named: "SmartStock.GoogleImport") }
            journal.logStep("Импорт из Google Фото: выбрано \(total)")

            for (index, item) in items.enumerated() {
                do {
                    journal.logStep("Google \(index + 1)/\(total): скачиваю \(item.filename)")
                    // Файл скачивается во временный файл (а не в память), затем переносится в папку приложения
                    let tempURL = try await GooglePhotosManager.shared.downloadItemFile(item)

                    let newId = UUID()
                    let fileURL = self.photosDirectoryURL.appendingPathComponent("\(newId.uuidString).\(item.fileExtension)")
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: fileURL)

                    let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                    let byteCount = (attributes?[.size] as? Int64) ?? 0
                    guard byteCount > 0 else {
                        try? FileManager.default.removeItem(at: fileURL)
                        throw NSError(domain: "GooglePhotos", code: 404, userInfo: [NSLocalizedDescriptionKey: "Получен пустой файл"])
                    }

                    let thumbImg = await ImageCacheHelper.shared.loadAndDownsample(fileURL: fileURL, maxPixelSize: 300)
                    let thumbData = thumbImg?.jpegData(compressionQuality: 0.75)
                    let sizeStr = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)

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
                    imported += 1
                    journal.logStep("Google \(index + 1)/\(total): готово, \(sizeStr)")
                    self.triggerToast("Импорт из Google Фото".localized + ": \(imported)/\(total)")
                } catch {
                    failed += 1
                    lastErrorText = error.localizedDescription
                    journal.logError("Google \(index + 1)/\(total): \(item.filename) — \(error.localizedDescription)")
                    print("[GooglePhotos] Ошибка импорта \(item.filename): \(error)")
                }
            }

            // Сессия выбора больше не нужна
            await GooglePhotosManager.shared.endPickerSession()

            if failed == 0 {
                self.triggerToast("Импортировано из Google Фото".localized + ": \(imported)")
            } else {
                self.triggerToast("Импортировано".localized + " \(imported)/\(total). " + "Не удалось".localized + ": \(failed). \(lastErrorText)")
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
                // До 6 кадров по всему ролику, уменьшенные до 1024 px и без чёрных; запасной вариант — прежние 3 кадра
                var frames = await ImageCacheHelper.shared.extractAIFrames(fileURL: sourceURL, count: 6)
                if frames.isEmpty {
                    frames = await ImageCacheHelper.shared.extractFrames(fileURL: sourceURL, count: 3)
                }
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
    
    // MARK: - Промпт, серии похожих кадров, демо-режим, дубли

    /// Промпт для ИИ: пользовательский или стандартный (для видео — видеопромпт с данными ролика)
    /// плюс подсказка не повторять тексты, уже написанные для похожих кадров серии.
    private func aiPrompt(for photo: PhotoMetadata) async -> String {
        let custom = (UserDefaults.standard.string(forKey: "ai_custom_prompt") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = custom
        if custom.isEmpty {
            prompt = photo.isVideo ? AIManager.videoPrompt : AIManager.defaultPrompt
        }

        if photo.isVideo, let (sourceURL, needStop) = resolveSourceURL(for: photo) {
            defer {
                if needStop { sourceURL.stopAccessingSecurityScopedResource() }
            }
            if let info = await ImageCacheHelper.shared.videoInfo(fileURL: sourceURL) {
                prompt += "\n\n" + AIManager.videoContext(info)
            }
        }

        if let siblingIds = seriesSiblings[photo.id] {
            let usedTitles = photos
                .filter { siblingIds.contains($0.id) && !$0.title.isEmpty }
                .prefix(4)
                .map { "\"\($0.title)\"" }
            if !usedTitles.isEmpty {
                prompt += "\n\nThis file belongs to a series of very similar shots. Titles already used for the other shots: "
                    + usedTitles.joined(separator: ", ")
                    + ". Write a clearly different title and description for this one by focusing on what is visually different"
                    + " (framing, light, foreground, details). Do not reuse their wording."
            }
        }
        return prompt
    }

    /// Находит серии похожих кадров среди реальных файлов, чтобы ИИ не писал для них одинаковые тексты
    private func prepareSeriesIndex() async {
        let items = duplicateItems(from: photos.filter { !$0.isDemo })
        guard items.count > 1 else {
            seriesSiblings = [:]
            return
        }
        let groups = await DuplicateDetector.shared.findGroups(items: items, threshold: DuplicateSensitivity.loose.threshold)
        var map: [UUID: [UUID]] = [:]
        for group in groups {
            for id in group.photoIDs {
                map[id] = group.photoIDs.filter { $0 != id }
            }
        }
        seriesSiblings = map
    }

    /// Данные файлов для поиска дублей (по миниатюрам, оригиналы не читаются)
    func duplicateItems(from source: [PhotoMetadata]) -> [DuplicateDetector.Item] {
        source.compactMap { photo in
            guard let thumbnail = photo.thumbnailData, !thumbnail.isEmpty else { return nil }
            return DuplicateDetector.Item(
                id: photo.id,
                thumbnail: thumbnail,
                isUploaded: photo.status == .success,
                fileBytes: parseFileSizeToBytes(photo.fileSize)
            )
        }
    }

    /// Удаляет файлы из очереди вместе с их копиями в папке приложения
    func removePhotosAndFiles(_ ids: Set<UUID>) {
        let directory = photosDirectoryURL.standardizedFileURL.path
        for photo in photos where ids.contains(photo.id) {
            if let path = photo.localURLPath {
                let fileURL = URL(fileURLWithPath: path).standardizedFileURL
                if fileURL.path.hasPrefix(directory) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            uploadSpeedKBps.removeValue(forKey: photo.id)
        }
        photos.removeAll(where: { ids.contains($0.id) })
        savePhotosToDisk()
    }

    /// Добавляет в очередь примеры для демо-режима
    func addDemoFiles() {
        let samples = DemoMode.makeSamplePhotos(into: photosDirectoryURL)
        for sample in samples.reversed() {
            addPhoto(sample)
        }
        triggerToast("Добавлены демо-файлы. В сеть они не отправляются.".localized)
    }

    /// Убирает из очереди все демо-файлы
    func removeDemoFiles() {
        let ids = Set(photos.filter { $0.isDemo }.map { $0.id })
        guard !ids.isEmpty else { return }
        removePhotosAndFiles(ids)
    }

    /// Имитация ИИ-анализа демо-файла: заготовленные метаданные, без сети и без списания лимита
    private func demoAnalyze(_ id: UUID) async {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[idx].status = .aiAnalyzing
        let filename = photos[idx].filename
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let result = DemoMode.metadata(forFilename: filename)
        photos[index].title = result.title
        photos[index].description = result.description
        photos[index].keywords = result.keywords
        photos[index].categories = result.categories ?? []
        photos[index].errorMessage = nil
        photos[index].status = .ready
        savePhotosToDisk()
    }

    /// Имитация отправки демо-файла на вымышленный сток: индикатор доходит до 100%, ничего не уходит в сеть
    private func demoUpload(_ id: UUID) async {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[idx].status = .uploading
        photos[idx].uploadProgress = 0.0
        photos[idx].errorMessage = nil
        for step in 1...10 {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
            photos[index].uploadProgress = Double(step) / 10.0
        }
        if let index = photos.firstIndex(where: { $0.id == id }) {
            photos[index].status = .success
            photos[index].uploadProgress = 1.0
            savePhotosToDisk()
        }
    }

    func runAIForPhoto(_ id: UUID) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }

        if photos[idx].isDemo {
            Task { await demoAnalyze(id) }
            return
        }

        let provider = AIProvider.gemini.rawValue
        let apiKey = AIManager.defaultSystemGeminiKey
        
        // 1. Проверяем и сразу списываем слот
        guard RewardAdManager.shared.consumeActionSlot(isAIAnalysis: true) else {
            triggerToast("Достигнут дневной лимит (15 ИИ-анализов в день). Оформите PRO!".localized)
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
            let customPrompt = await aiPrompt(for: photo)

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
                    let aiCats = metadata.categories ?? []
                    self.photos[index].categories = aiCats.isEmpty
                        ? ShutterstockCategoryMatcher.match(title: metadata.title, description: metadata.description, keywords: metadata.keywords)
                        : aiCats
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
            
            // Серии похожих кадров: ИИ получит подсказку не повторять уже написанные для них тексты
            await prepareSeriesIndex()

            var processedCount = 0
            for photo in unanalyzed {
                if photo.isDemo {
                    await demoAnalyze(photo.id)
                    processedCount += 1
                    continue
                }
                guard RewardAdManager.shared.consumeActionSlot(isAIAnalysis: true) else {
                    self.triggerToast("Достигнут дневной лимит ИИ. Оформите PRO для продолжения.".localized)
                    self.shouldShowDailyLimitAlert = true
                    break
                }
                
                if let idx = self.photos.firstIndex(where: { $0.id == photo.id }) {
                    self.photos[idx].status = .aiAnalyzing
                }
                
                let imagesData = await getAIImagesData(for: photo)
                let customPrompt = await aiPrompt(for: photo)
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
                        let aiCats = metadata.categories ?? []
                        self.photos[index].categories = aiCats.isEmpty
                            ? ShutterstockCategoryMatcher.match(title: metadata.title, description: metadata.description, keywords: metadata.keywords)
                            : aiCats
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

        // Демо-файл: отправка имитируется, нужных стоков и паролей не требуется, лимиты не списываются
        if photos[idx].isDemo {
            Task {
                await demoUpload(id)
                self.triggerToast("Демо: файл «отправлен» на тестовый сток. В сеть ничего не ушло.".localized)
            }
            return
        }

        guard checkStockCredentials() else {
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!".localized)
            return
        }
        
        // Проверяем и сразу списываем слот на отправку
        guard RewardAdManager.shared.consumeActionSlot(isAIAnalysis: false) else {
            triggerToast("Достигнут дневной лимит (15 отправок в день). Оформите PRO!".localized)
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
    
    /// «Отправить все»: каждый готовый файл уходит тем же путём, что и при отправке одного файла
    /// или выбранных файлов (общая очередь, учёт лимитов, индикаторы, фоновая задача).
    /// Раньше здесь был отдельный цикл, минующий очередь, — при трёх и более файлах приложение закрывалось.
    func uploadAllReady() {
        let readyPhotos = photos.filter { $0.status == .ready }
        guard !readyPhotos.isEmpty else {
            triggerToast("Нет файлов, готовых к отправке.".localized)
            return
        }
        // Пароли стоков нужны только для настоящих файлов; демо-файлы «отправляются» без них
        if readyPhotos.contains(where: { !$0.isDemo }) && !checkStockCredentials() {
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!".localized)
            return
        }

        FTPTranscriptLogger.shared.logStep("Отправить все: в очередь \(readyPhotos.count) файлов")
        triggerToast("Началась отправка".localized + " \(readyPhotos.count) " + "файлов...".localized)

        for photo in readyPhotos {
            if !photo.isDemo {
                guard RewardAdManager.shared.canPerformAction(isAIAnalysis: false) else {
                    triggerToast("Достигнут дневной лимит отправок. Оформите PRO для продолжения.".localized)
                    shouldShowDailyLimitAlert = true
                    HapticHelper.notification(.warning)
                    break
                }
            }
            uploadPhoto(photo.id)
        }
    }
    
    /// ⚡️ Режим Автопилота: Последовательный ИИ-анализ и автоматическая отправка на стоки в 1 клик
    func runAutopilotPipeline() {
        let targets = photos.filter { $0.status != .success }
        guard !targets.isEmpty else {
            triggerToast("Все файлы в очереди уже успешно загружены!".localized)
            return
        }
        if targets.contains(where: { !$0.isDemo }) && !checkStockCredentials() {
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
            
            // Серии похожих кадров: ИИ получит подсказку не повторять уже написанные для них тексты
            await prepareSeriesIndex()

            var processedCount = 0

            for photo in targets {
                // Демо-файлы: имитация ИИ-анализа и отправки без сети и без лимитов
                if photo.isDemo {
                    if photo.status == .new || photo.status == .error {
                        await self.demoAnalyze(photo.id)
                    }
                    await self.demoUpload(photo.id)
                    processedCount += 1
                    continue
                }

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
                    let customPrompt = await aiPrompt(for: photo)
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
                            let aiCats = metadata.categories ?? []
                            self.photos[index].categories = aiCats.isEmpty
                                ? ShutterstockCategoryMatcher.match(title: metadata.title, description: metadata.description, keywords: metadata.keywords)
                                : aiCats
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
                        self.triggerToast("Достигнут дневной лимит отправок. Оформите PRO для продолжения.".localized)
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
    
    /// Имя файла на стоке: у фото расширение .jpg (содержимое всегда JPEG), у видео — прежнее
    private func uploadFilename(for photo: PhotoMetadata) -> String {
        if photo.isVideo { return photo.filename }
        let ext = (photo.filename as NSString).pathExtension.lowercased()
        if ext == "jpg" || ext == "jpeg" { return photo.filename }
        return (photo.filename as NSString).deletingPathExtension + ".jpg"
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
            // Обработка метаданных фото и сжатие. Файл читается с диска, а не целиком в память:
            // RAW/ProRAW (DNG) при полном декодировании занимает гигабайты, и система закрывает приложение.
            let compress = UserDefaults.standard.bool(forKey: "sys_compress_jpeg")
            let sourceBytes = ((try? FileManager.default.attributesOfItem(atPath: sourceFileURL.path))?[.size] as? Int64) ?? 0
            let needsUpscale = UserDefaults.standard.bool(forKey: "sys_auto_upscale") && sourceBytes < 8 * 1024 * 1024
            
            if needsUpscale, let data = try? Data(contentsOf: sourceFileURL) {
                // Небольшой файл при включённом авто-апскейле: прежний путь через данные в памяти
                let finalImageData = await ImageProcessor.shared.prepareImageForUpload(
                    imageData: data,
                    photo: photo,
                    compress: compress
                )
                let tempImageURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
                do {
                    try finalImageData.write(to: tempImageURL)
                    fileURLToUpload = tempImageURL
                    tempURLsToDelete.append(tempImageURL)
                } catch {
                    throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить обработанное изображение: \(error.localizedDescription)"])
                }
            } else {
                guard let preparedURL = await ImageProcessor.shared.prepareImageFileForUpload(
                    sourceURL: sourceFileURL,
                    photo: photo,
                    compress: compress
                ) else {
                    throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось подготовить изображение к отправке"])
                }
                fileURLToUpload = preparedURL
                tempURLsToDelete.append(preparedURL)
            }
        }
        
        // Фото всегда отправляется как JPEG — имя должно соответствовать содержимому (раньше уходил JPEG с именем .DNG)
        let uploadName = uploadFilename(for: photo)
        let preparedBytes = ((try? FileManager.default.attributesOfItem(atPath: fileURLToUpload.path))?[.size] as? Int64) ?? 0
        FTPTranscriptLogger.shared.logStep("Файл \(photo.filename) подготовлен к отправке: \(preparedBytes / 1_048_576) МБ")
        
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
                filename: uploadName,
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
            FTPTranscriptLogger.shared.logStep("Отправка \(photo.filename) на \(platform.name)")
            
            while attempts < maxAttempts {
                do {
                    // Используем потоковую отправку по URL
                    try await FTPSecureClient.upload(
                        fileURL: fileURLToUpload,
                        filename: uploadName,
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
            let desc = escape(photo.description.isEmpty ? photo.title : photo.description)
            let kw = escape(photo.keywords.prefix(50).joined(separator: ", "))
            let catsList = photo.categories.isEmpty
                ? ShutterstockCategoryMatcher.match(title: photo.title, description: photo.description, keywords: photo.keywords)
                : photo.categories
            let cats = escape(catsList.prefix(2).joined(separator: ", "))
            let editorialFlag = photo.isEditorial ? "Yes" : "No"
            csv += "\(fn),\(desc),\(kw),\(cats),No,No,\(editorialFlag)\n"
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
