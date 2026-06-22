import Foundation
import ImageIO
import UIKit

/// Фоновый актор для ресурсоемких операций с изображениями
actor ImageProcessor {
    static let shared = ImageProcessor()
    private init() {}
    
    /// Записывает метаданные IPTC/EXIF и сжимает JPEG в фоновом потоке
    func prepareImageForUpload(
        imageData: Data,
        photo: PhotoMetadata,
        compress: Bool
    ) -> Data {
        let preparedData = writeMetadata(
            to: imageData,
            title: photo.title,
            description: photo.description,
            keywords: photo.keywords,
            categories: photo.categories
        ) ?? imageData
        
        var finalData = preparedData
        if compress {
            if let uiImage = UIImage(data: preparedData),
               let compressed = uiImage.jpegData(compressionQuality: 0.85) {
                finalData = writeMetadata(
                    to: compressed,
                    title: photo.title,
                    description: photo.description,
                    keywords: photo.keywords,
                    categories: photo.categories
                ) ?? compressed
            }
        }
        return finalData
    }
    
    private func writeMetadata(
        to imageData: Data,
        title: String,
        description: String,
        keywords: [String],
        categories: [String]
    ) -> Data? {
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
        
        // Объединяем ключевые слова с категориями
        var mergedKeywords = keywords
        for category in categories {
            if !mergedKeywords.contains(category) {
                mergedKeywords.append(category)
            }
        }
        iptc[kCGImagePropertyIPTCKeywords as String] = mergedKeywords
        
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
}
