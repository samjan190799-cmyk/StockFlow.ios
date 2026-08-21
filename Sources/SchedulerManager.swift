import Foundation
import BackgroundTasks
import UIKit

final class SchedulerManager {
    static let shared = SchedulerManager()
    
    private init() {}
    
    /// Регистрирует фоновую задачу при старте приложения
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.samvel.smartstock.backgroundRefresh", using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundTask(task: refreshTask)
        }
    }
    
    /// Перезапускает или выключает планировщик
    func setSchedulerEnabled(_ enabled: Bool) {
        if enabled {
            scheduleNextBackgroundTask()
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.samvel.smartstock.backgroundRefresh")
        }
    }
    
    /// Планирует следующий запуск задачи
    func scheduleNextBackgroundTask() {
        guard UserDefaults.standard.bool(forKey: "sys_bg_scheduler") else { return }
        
        let intervalHours = UserDefaults.standard.integer(forKey: "sys_scheduler_interval_hours")
        let hours = intervalHours > 0 ? intervalHours : 1
        
        let request = BGAppRefreshTaskRequest(identifier: "com.samvel.smartstock.backgroundRefresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(hours * 3600))
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[SchedulerManager] Задача успешно запланирована через \(hours) ч.")
        } catch {
            print("[SchedulerManager] Ошибка планирования задачи: \(error.localizedDescription)")
        }
    }
    
    /// Обработчик фонового пробуждения системы
    private func handleBackgroundTask(task: BGAppRefreshTask) {
        // Планируем сразу следующий запуск
        scheduleNextBackgroundTask()
        
        let backgroundJob = Task {
            await self.runSchedulerUploadCycle()
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = {
            backgroundJob.cancel()
            task.setTaskCompleted(success: false)
        }
    }
    
    /// Основной цикл сканирования папки и автозагрузки
    func runSchedulerUploadCycle() async {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "sys_scheduler_folder_bookmark") else {
            print("[SchedulerManager] Закладка папки не найдена.")
            return
        }
        
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            print("[SchedulerManager] Не удалось восстановить URL папки.")
            return
        }
        
        if isStale {
            print("[SchedulerManager] Закладка папки устарела.")
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            print("[SchedulerManager] Отказано в доступе к папке.")
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            print("[SchedulerManager] Не удалось прочитать содержимое папки.")
            return
        }
        
        let imageExtensions = ["jpg", "jpeg", "png", "heic"]
        let imageFiles = contents.filter { file in
            let ext = file.pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }
        
        var uploadedList = Set(UserDefaults.standard.stringArray(forKey: "sys_uploaded_filenames") ?? [])
        
        var newImages: [URL] = []
        for file in imageFiles {
            if !uploadedList.contains(file.lastPathComponent) {
                newImages.append(file)
            }
        }
        
        guard !newImages.isEmpty else {
            print("[SchedulerManager] Новых файлов для загрузки не найдено.")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "sys_scheduler_last_run")
            return
        }
        
        print("[SchedulerManager] Найдено \(newImages.count) новых файлов.")
        
        // Проверяем наличие активных стоков и учетных данных
        let hasActiveStocks = await MainActor.run { () -> Bool in
            guard QueueViewModel.shared != nil else { return false }
            
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
        
        guard hasActiveStocks else {
            print("[SchedulerManager] Настройки стоков отсутствуют или неактивны.")
            return
        }
        
        for fileURL in newImages {
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            
            let filename = fileURL.lastPathComponent
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            
            let photo = PhotoMetadata(
                filename: filename,
                fileSize: sizeStr,
                title: "Авто-выгрузка: \(filename)",
                keywords: ["автозагрузка"],
                description: "Изображение добавлено и отправлено автоматически планировщиком.",
                status: .new,
                imageData: data
            )
            
            // Добавляем фото в основную очередь
            await MainActor.run {
                QueueViewModel.shared?.addPhoto(photo)
                QueueViewModel.shared?.runAIForPhoto(photo.id)
            }
            
            // Ждем завершения ИИ-анализа (до 20 секунд)
            var isReady = false
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let status = await MainActor.run { () -> PhotoStatus? in
                    QueueViewModel.shared?.photos.first(where: { $0.id == photo.id })?.status
                }
                if status == .ready {
                    isReady = true
                    break
                } else if status == .error {
                    break
                }
            }
            
            if isReady {
                // Запускаем отправку
                await MainActor.run {
                    QueueViewModel.shared?.uploadPhoto(photo.id)
                }
                
                // Ожидаем успешную загрузку (до 60 секунд)
                var isDone = false
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let status = await MainActor.run { () -> PhotoStatus? in
                        QueueViewModel.shared?.photos.first(where: { $0.id == photo.id })?.status
                    }
                    if status == .success {
                        isDone = true
                        break
                    } else if status == .error {
                        break
                    }
                }
                
                if isDone {
                    uploadedList.insert(filename)
                    UserDefaults.standard.set(Array(uploadedList), forKey: "sys_uploaded_filenames")
                }
            }
        }
        
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "sys_scheduler_last_run")
        
        NotificationHelper.sendNotification(
            title: "Планировщик выгрузки".localized,
            body: "Фоновая обработка завершена. Новых файлов загружено: \(newImages.count)".localized
        )
    }
}
