import Foundation
import ImageIO
import UIKit
import AVFoundation

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
    
    /// Внедряет метаданные (Title, Description, Keywords) в MP4/QuickTime видеофайл без перекодирования.
    /// Возвращает URL нового временного файла.
    func prepareVideoForUpload(
        videoURL: URL,
        photo: PhotoMetadata
    ) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        
        // Создаем уникальный временный файл с тем же расширением
        let ext = videoURL.pathExtension.lowercased()
        let actualExt = ext.isEmpty ? "mp4" : ext
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("\(UUID().uuidString).\(actualExt)")
        
        // Определяем тип файла по расширению
        let fileType: AVFileType
        if actualExt == "mov" {
            fileType = .mov
        } else {
            fileType = .mp4
        }
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw NSError(domain: "ImageProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать AVAssetExportSession"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = fileType
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Формируем метаданные
        var metadataItems: [AVMetadataItem] = []
        
        // Common Keys
        // Title
        let titleItem = AVMutableMetadataItem()
        titleItem.keySpace = AVMetadataKeySpace.common
        titleItem.key = AVMetadataKey.commonKeyTitle as NSCopying & NSObjectProtocol
        titleItem.value = photo.title as NSString
        metadataItems.append(titleItem)
        
        // Description
        let descItem = AVMutableMetadataItem()
        descItem.keySpace = AVMetadataKeySpace.common
        descItem.key = AVMetadataKey.commonKeyDescription as NSCopying & NSObjectProtocol
        descItem.value = photo.description as NSString
        metadataItems.append(descItem)
        
        // Keywords
        let keywordsString = photo.keywords.joined(separator: ", ")
        let keywordsItem = AVMutableMetadataItem()
        keywordsItem.keySpace = AVMetadataKeySpace.common
        keywordsItem.key = AVMetadataKey.commonKeyKeywords as NSCopying & NSObjectProtocol
        keywordsItem.value = keywordsString as NSString
        metadataItems.append(keywordsItem)
        
        // QuickTime Metadata Keys
        let qtTitleItem = AVMutableMetadataItem()
        qtTitleItem.keySpace = AVMetadataKeySpace.quickTimeMetadata
        qtTitleItem.key = AVMetadataKey.quickTimeMetadataKeyTitle as NSCopying & NSObjectProtocol
        qtTitleItem.value = photo.title as NSString
        metadataItems.append(qtTitleItem)
        
        let qtDescItem = AVMutableMetadataItem()
        qtDescItem.keySpace = AVMetadataKeySpace.quickTimeMetadata
        qtDescItem.key = AVMetadataKey.quickTimeMetadataKeyDescription as NSCopying & NSObjectProtocol
        qtDescItem.value = photo.description as NSString
        metadataItems.append(qtDescItem)
        
        let qtKeywordsItem = AVMutableMetadataItem()
        qtKeywordsItem.keySpace = AVMetadataKeySpace.quickTimeMetadata
        qtKeywordsItem.key = AVMetadataKey.quickTimeMetadataKeyKeywords as NSCopying & NSObjectProtocol
        qtKeywordsItem.value = keywordsString as NSString
        metadataItems.append(qtKeywordsItem)
        
        exportSession.metadata = metadataItems
        
        await exportSession.export()
        
        if let error = exportSession.error {
            throw error
        }
        
        return outputURL
    }
}
