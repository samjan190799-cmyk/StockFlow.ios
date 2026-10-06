import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Файловый импорт фото из PhotosPicker: снимок копируется на диск, а не читается целиком в память.
struct PhotoFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let ext = received.file.pathExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("import_\(UUID().uuidString)")
                .appendingPathExtension(ext.isEmpty ? "img" : ext)
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return PhotoFileTransferable(url: tempURL)
        }
    }
}

// Импорт из системного PhotosPicker для главного экрана галереи (GalleryView).
extension QueueViewModel {
    func importPickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        Task { @MainActor in
            let journal = FTPTranscriptLogger.shared
            journal.logStep("Импорт из галереи iPhone: выбрано \(items.count)")
            for (index, item) in items.enumerated() {
                journal.logStep("Галерея iPhone \(index + 1)/\(items.count): загружаю")
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
                        let targetURL = self.photosDirectoryURL.appendingPathComponent("\(uuid.uuidString).\(actualExt)")

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
                        self.addPhoto(newPhoto)
                        journal.logStep("Галерея iPhone \(index + 1)/\(items.count): видео добавлено (\(fileSizeStr))")

                    } catch {
                        journal.logError("Галерея iPhone \(index + 1)/\(items.count): ошибка видео \(error.localizedDescription)")
                        self.triggerToast("Ошибка импорта видео: \(error.localizedDescription)")
                        print("[Video] Ошибка: \(error)")
                    }

                } else {
                    // Фото копируется файлом, а не читается целиком в память; HEIC/PNG/RAW переводятся в JPEG через ImageIO.
                    // Раньше снимок целиком декодировался через UIImage: ProRAW на 48 Мп занимал гигабайты, и приложение закрывала система.
                    do {
                        let photoId = UUID()
                        let targetURL = self.photosDirectoryURL.appendingPathComponent("\(photoId.uuidString).jpg")
                        let randomNum = Int.random(in: 1000...9999)
                        var fileBytes: Int64? = nil

                        if let file = try? await item.loadTransferable(type: PhotoFileTransferable.self) {
                            fileBytes = await ImageProcessor.shared.importPhoto(from: file.url, to: targetURL)
                            try? FileManager.default.removeItem(at: file.url)
                        }

                        // Запасной путь: данные в памяти, но конвертация всё равно идёт через ImageIO
                        if fileBytes == nil, let data = try await item.loadTransferable(type: Data.self) {
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("import_\(UUID().uuidString)")
                            try data.write(to: tempURL, options: .atomic)
                            fileBytes = await ImageProcessor.shared.importPhoto(from: tempURL, to: targetURL)
                            try? FileManager.default.removeItem(at: tempURL)
                        }

                        guard var bytes = fileBytes else {
                            journal.logError("Галерея iPhone \(index + 1)/\(items.count): не удалось получить снимок")
                            continue
                        }

                        // Авто-апскейл (с ограничением итогового размера, чтобы не раздувать память)
                        if UserDefaults.standard.bool(forKey: "sys_auto_upscale") {
                            let thresholdStr = UserDefaults.standard.string(forKey: "sys_upscale_threshold") ?? "Меньше 4 МБ (Рекомендуется)"
                            let factorStr = UserDefaults.standard.string(forKey: "sys_upscale_factor") ?? "Увеличение 2x (Бикубическое)"
                            let thresholdMB: Double = thresholdStr.contains("2 МБ") ? 2.0 : (thresholdStr.contains("8 МБ") ? 8.0 : 4.0)
                            let sizeMB = Double(bytes) / (1024.0 * 1024.0)
                            if sizeMB < thresholdMB {
                                let scale: CGFloat = factorStr.contains("4x") ? 4.0 : 2.0
                                if await ImageProcessor.shared.upscaleJPEGFile(at: targetURL, scaleFactor: scale) {
                                    let newBytes = ((try? FileManager.default.attributesOfItem(atPath: targetURL.path))?[.size] as? Int64) ?? bytes
                                    FTPTranscriptLogger.shared.logInfo("[Upscale] \(String(format: "%.1f", sizeMB)) МБ -> \(String(format: "%.1f", Double(newBytes) / 1024 / 1024)) МБ")
                                    bytes = newBytes
                                }
                            }
                        }

                        let thumbImage = await ImageCacheHelper.shared.loadAndDownsample(fileURL: targetURL, maxPixelSize: 300)
                        let thumbData = thumbImage?.jpegData(compressionQuality: 0.75)

                        let sizeMB = Double(bytes) / (1024.0 * 1024.0)
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
                        self.addPhoto(newPhoto)
                        journal.logStep("Галерея iPhone \(index + 1)/\(items.count): фото добавлено (\(fileSizeStr))")

                    } catch {
                        journal.logError("Галерея iPhone \(index + 1)/\(items.count): ошибка фото \(error.localizedDescription)")
                        print("[Photo] Ошибка: \(error)")
                    }
                }
            }
        }
    }
}
