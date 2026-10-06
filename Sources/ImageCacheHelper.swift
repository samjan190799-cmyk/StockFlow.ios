import UIKit
import ImageIO
import Foundation
import AVFoundation
import UniformTypeIdentifiers

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
            
            // RAW (DNG/ProRAW): полное декодирование 48-Мп кадра занимает 1–2 ГБ памяти, поэтому берём встроенное превью
            let typeIdentifier = (CGImageSourceGetType(imageSource) as String?) ?? ""
            let isRAW = (UTType(typeIdentifier)?.conforms(to: .rawImage) ?? false)
                || ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "raw"].contains(fileURL.pathExtension.lowercased())
            
            let downsampleOptions: CFDictionary = [
                (isRAW ? kCGImageSourceCreateThumbnailFromImageIfAbsent : kCGImageSourceCreateThumbnailFromImageAlways): true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as [CFString: Any] as CFDictionary
            
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
            
            let duration = try? await asset.load(.duration)
            let durationSeconds: Double = duration?.seconds ?? 0
            
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

    /// Кадры видео для ИИ: до `count` кадров, равномерно по всему ролику, без чёрных кадров,
    /// каждый не крупнее `maxDimension` пикселей по большей стороне (запрос к ИИ остаётся лёгким даже для 4K).
    func extractAIFrames(
        fileURL: URL,
        count: Int = 6,
        maxDimension: CGFloat = 1024
    ) async -> [Data] {
        let isVideoFile = ["mp4", "mov", "m4v", "avi", "mkv", "3gp"].contains(fileURL.pathExtension.lowercased())
        guard isVideoFile, count > 0 else { return [] }

        return await Task.detached(priority: .userInitiated) { () -> [Data] in
            let asset = AVAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

            let duration = try? await asset.load(.duration)
            let durationSeconds: Double = duration?.seconds ?? 0

            guard durationSeconds.isFinite, durationSeconds > 0 else {
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil),
                   let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) {
                    return [jpegData]
                }
                return []
            }

            // Берём кадров с запасом, чтобы после отбраковки чёрных осталось нужное число
            let candidates = count + 2
            var decoded: [(image: CGImage, luma: Double)] = []
            for i in 0..<candidates {
                let fraction = 0.03 + 0.94 * (Double(i) + 0.5) / Double(candidates)
                let time = CMTime(seconds: durationSeconds * fraction, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    decoded.append((cgImage, ImageCacheHelper.meanLuma(of: cgImage)))
                }
            }

            // Чёрные кадры (затемнение, вспышки, начало ролика) ИИ ничего не дают
            var usable = decoded.filter { $0.luma > 0.04 }
            if usable.count < 2 { usable = decoded }

            // Если кадров больше нужного — оставляем равномерно распределённые
            if usable.count > count {
                var picked: [(image: CGImage, luma: Double)] = []
                for i in 0..<count {
                    let index = Int((Double(i) * Double(usable.count - 1) / Double(max(count - 1, 1))).rounded())
                    picked.append(usable[index])
                }
                usable = picked
            }

            var frames: [Data] = []
            for item in usable {
                if let jpegData = UIImage(cgImage: item.image).jpegData(compressionQuality: 0.8) {
                    frames.append(jpegData)
                }
            }
            return frames
        }.value
    }

    /// Длительность, размер кадра и частота кадров ролика (для подсказки ИИ)
    func videoInfo(fileURL: URL) async -> VideoClipInfo? {
        let isVideoFile = ["mp4", "mov", "m4v", "avi", "mkv", "3gp"].contains(fileURL.pathExtension.lowercased())
        guard isVideoFile else { return nil }

        return await Task.detached(priority: .userInitiated) { () -> VideoClipInfo? in
            let asset = AVAsset(url: fileURL)
            let duration = try? await asset.load(.duration)
            guard let seconds = duration?.seconds, seconds.isFinite, seconds > 0 else { return nil }

            var width = 0
            var height = 0
            var fps = 0.0
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            if let track = tracks?.first {
                let size = (try? await track.load(.naturalSize)) ?? .zero
                let transform = (try? await track.load(.preferredTransform)) ?? CGAffineTransform.identity
                let rect = CGRect(origin: .zero, size: size).applying(transform)
                width = Int(abs(rect.width).rounded())
                height = Int(abs(rect.height).rounded())
                fps = Double((try? await track.load(.nominalFrameRate)) ?? 0)
            }
            return VideoClipInfo(duration: seconds, width: width, height: height, fps: fps)
        }.value
    }

    /// Средняя яркость кадра от 0 (чёрный) до 1 (белый), по уменьшенной копии 16×16
    nonisolated static func meanLuma(of image: CGImage) -> Double {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 1.0 }
        let sum = pixels.reduce(0) { $0 + Int($1) }
        return Double(sum) / Double(side * side) / 255.0
    }
}

/// Технические данные видеоролика
struct VideoClipInfo: Sendable {
    let duration: Double
    let width: Int
    let height: Int
    let fps: Double
}
