import UIKit
import ImageIO
import Foundation

/// Помощник для работы с кэшем изображений и их даунсемплингом в фоновом потоке
@MainActor
final class ImageCacheHelper {
    static let shared = ImageCacheHelper()
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        // Лимитируем количество объектов в кэше для предотвращения утечки ОЗУ
        cache.countLimit = 150
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
        
        let fileURL = dirURL.appendingPathComponent("\(photoId.uuidString).jpg")
        
        // Переносим обработку в фоновый поток (Task.detached)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let path = fileURL.path
            guard FileManager.default.fileExists(atPath: path) else {
                return nil
            }
            
            let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, imageSourceOptions) else {
                return nil
            }
            
            let downsampleOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary
            
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
                return nil
            }
            
            return UIImage(cgImage: cgImage)
        }.value
        
        if let image = image {
            cacheImage(image, forKey: key)
        }
        
        return image
    }
}
