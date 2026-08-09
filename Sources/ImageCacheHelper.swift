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
        cache.countLimit = 250
        cache.totalCostLimit = 60 * 1024 * 1024 // 60 МБ максимум
    }
    
    func getCachedImage(forKey key: String) -> UIImage? {
        if UserDefaults.standard.bool(forKey: "sys_no_cache_mode") {
            return nil
        }
        return cache.object(forKey: key as NSString)
    }
    
    func cacheImage(_ image: UIImage, forKey key: String) {
        if UserDefaults.standard.bool(forKey: "sys_no_cache_mode") {
            return
        }
        cache.setObject(image, forKey: key as NSString)
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
    
    /// Асинхронно загружает изображение по прямом URL, сжимает (downsample) до нужного размера и сохраняет в NSCache
    func loadAndDownsample(
        fileURL: URL,
        maxPixelSize: Int = 400
    ) async -> UIImage? {
        let key = "\(fileURL.lastPathComponent)_\(maxPixelSize)"
        
        if let cached = getCachedImage(forKey: key) {
            return cached
        }
        
        let isVideoFile = ["mp4", "mov", "m4v", "avi", "mkv", "3gp"].contains(fileURL.pathExtension.lowercased())
        
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
    
    /// Извлекает кадры для ИИ прямо по физическому URL файла без использования кэша папки
    func extractFrames(
        fileURL: URL,
        count: Int = 3
    ) async -> [Data] {
        let isVideoFile = ["mp4", "mov", "m4v", "avi", "mkv", "3gp"].contains(fileURL.pathExtension.lowercased())
        
        guard isVideoFile else {
            if let data = try? Data(contentsOf: fileURL) {
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
            
            let durationSeconds: Double = asset.duration.seconds
            
            guard durationSeconds > 0 else {
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil),
                   let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85) {
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
                    let targetSec = durationSeconds * (0.05 + percent * 0.9)
                    times.append(CMTime(seconds: targetSec, preferredTimescale: 60))
                }
            }
            
            var frames: [Data] = []
            for time in times {
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil),
                   let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85) {
                    frames.append(jpegData)
                }
            }
            
            if frames.isEmpty {
                if let cgImageZero = try? generator.copyCGImage(at: .zero, actualTime: nil),
                   let jpegDataZero = UIImage(cgImage: cgImageZero).jpegData(compressionQuality: 0.85) {
                    frames.append(jpegDataZero)
                }
            }
            
            return frames
        }.value
    }
}
