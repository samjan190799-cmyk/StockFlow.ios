import SwiftUI
import PhotosUI

// Импорт из системного PhotosPicker для главного экрана галереи (GalleryView).
extension QueueViewModel {
    func importPickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

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

                    } catch {
                        self.triggerToast("Ошибка импорта видео: \(error.localizedDescription)")
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
                        let targetURL = self.photosDirectoryURL.appendingPathComponent("\(photoId.uuidString).jpg")
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
                        self.addPhoto(newPhoto)

                    } catch {
                        print("[Photo] Ошибка: \(error)")
                    }
                }
            }
        }
    }
}
