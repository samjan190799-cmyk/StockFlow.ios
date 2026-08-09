import UIKit
import ImageIO
import Foundation
import AVFoundation

/// Помощник для работы с кэшем изображений и их даунсемплингом в фоновом потоке
@MainActor
final class ImageCacheHelper {
    static let shared = ImageCacheHelper()
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        // Лимитируем количество объектов и объём памяти в кэше для предотвращения утечки ОЗУ
        cache.countLimit = 250
        cache.totalCostLimit = 80 * 1024 * 1024 // 80 МБ максимум
    }
    
    func getCachedImage(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func cacheImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
    
    /// Асинхронно загружает изображение с диска, сжимает (downsample) до нужного размера и сохраняет в NSCache
    func loadAndDownsample(
        photoId: UUID,
        fromDir dirURL: URL,
        maxPixelSize: Int = 400
    ) async -> UIImage? {
        let key = "\(photoId.uuidString)_\(maxPixelSize)"
        
        if let cached = getCachedImage(forKey: key) {
            return cached
        }
        
        // Поиск любого подходящего файла с совпадением UUID в имени
        var targetURL: URL? = nil
        var isVideoFile = false
        
        if let contents = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) {
            for file in contents {
                let name = file.lastPathComponent
                if name.hasPrefix(photoId.uuidString) && !name.hasSuffix("_thumb.jpg") {
                    targetURL = file
                    let ext = file.pathExtension.lowercased()
                    if ["mp4", "mov", "m4v", "avi", "mkv", "3gp"].contains(ext) {
                        isVideoFile = true
                    }
                    break
                }
            }
        }
        
        guard let fileURL = targetURL else {
            return nil
        }
        
        if isVideoFile {
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                let asset = AVAsset(url: fileURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .positiveInfinity
                generator.requestedTimeToleranceAfter = .positiveInfinity
                
                let timesToTry = [
                    CMTime(seconds: 0.5, preferredTimescale: 60),
                    CMTime(seconds: 1.0, preferredTimescale: 60),
                    .zero
                ]
                
                for t in timesToTry {
                    if let cgImage = try? generator.copyCGImage(at: t, actualTime: nil) {
                        return UIImage(cgImage: cgImage)
                    }
                }
                return nil
            }.value
            
            if let image = image {
                cacheImage(image, forKey: key)
            }
            return image
        }
        
        // Переносим обработку фото в фоновый поток
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, imageSourceOptions) else {
                if let rawData = try? Data(contentsOf: fileURL), let uiImg = UIImage(data: rawData) {
                    return uiImg
                }
                return nil
            }
            
            let downsampleOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary
            
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) {
                return UIImage(cgImage: cgImage)
            }
            
            if let rawData = try? Data(contentsOf: fileURL), let uiImg = UIImage(data: rawData) {
                return uiImg
            }
            return nil
        }.value
        
        if let image = image {
            cacheImage(image, forKey: key)
        }
        
        return image
    }
    
    /// Извлекает несколько кадров из видеофайла для анализа ИИ (например, 3 кадра)
    func extractFrames(
        photoId: UUID,
        fromDir dirURL: URL,
        count: Int = 3
    ) async -> [Data] {
        var targetURL: URL? = nil
        var isVideoFile = false
        
        if let contents = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) {
            for file in contents {
                let name = file.lastPathComponent
                if name.hasPrefix(photoId.uuidString) && !name.hasSuffix("_thumb.jpg") {
                    targetURL = file
                    let ext = file.pathExtension.lowercased()
                    if ["mp4", "mov", "m4v", "avi", "mkv", "3gp"].contains(ext) {
                        isVideoFile = true
                    }
                    break
                }
            }
        }
        
        guard isVideoFile, let fileURL = targetURL else {
            if let fileURL = targetURL, let data = try? Data(contentsOf: fileURL) {
                return [data]
            }
            return []
        }
        
        return await Task.detached(priority: .userInitiated) { () -> [Data] in
            let asset = AVAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            
            // Получаем длительность видео
            let durationSeconds: Double
            if #available(iOS 16.0, *) {
                durationSeconds = asset.duration.seconds
            } else {
                durationSeconds = asset.duration.seconds
            }
            
            guard durationSeconds > 0 else {
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil),
                   let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9) {
                    return [jpegData]
                }
                return []
            }
            
            var times: [CMTime] = []
            if count == 1 {
                times.append(CMTime(seconds: min(1.0, durationSeconds), preferredTimescale: 60))
            } else {
                for i in 0..<count {
                    let percent = Double(i) / Double(count - 1)
                    // Точки на 5%, 50%, 95%
                    let targetSec = durationSeconds * (0.05 + percent * 0.9)
                    times.append(CMTime(seconds: targetSec, preferredTimescale: 60))
                }
            }
            
            var frames: [Data] = []
            for time in times {
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil),
                   let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9) {
                    frames.append(jpegData)
                }
            }
            
            if frames.isEmpty {
                if let cgImageZero = try? generator.copyCGImage(at: .zero, actualTime: nil),
                   let jpegDataZero = UIImage(cgImage: cgImageZero).jpegData(compressionQuality: 0.9) {
                    frames.append(jpegDataZero)
                }
            }
            
            return frames
        }.value
    }
}
