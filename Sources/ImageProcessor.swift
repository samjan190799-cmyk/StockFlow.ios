import Foundation
import ImageIO
import UIKit
import AVFoundation
import CoreImage
import UniformTypeIdentifiers

/// Фоновый актор для ресурсоемких операций с изображениями и видео
actor ImageProcessor {
    static let shared = ImageProcessor()
    private init() {}
    
    /// Записывает метаданные IPTC/EXIF, выполняет авто-апскейл и сжимает JPEG в фоновом потоке
    func prepareImageForUpload(
        imageData: Data,
        photo: PhotoMetadata,
        compress: Bool
    ) -> Data {
        var processedData = imageData
        
        // 1. Проверяем включение Авто-апскейла в системных настройках
        let autoUpscale = UserDefaults.standard.bool(forKey: "sys_auto_upscale")
        if autoUpscale {
            let thresholdStr = UserDefaults.standard.string(forKey: "sys_upscale_threshold") ?? "Меньше 4 МБ (Рекомендуется)"
            let factorStr = UserDefaults.standard.string(forKey: "sys_upscale_factor") ?? "Увеличение 2x (Бикубическое)"
            
            let thresholdMB: Double
            if thresholdStr.contains("2") {
                thresholdMB = 2.0
            } else if thresholdStr.contains("8") {
                thresholdMB = 8.0
            } else {
                thresholdMB = 4.0
            }
            
            let fileSizeMB = Double(imageData.count) / (1024.0 * 1024.0)
            if fileSizeMB < thresholdMB, let uiImage = UIImage(data: imageData) {
                let scaleFactor: CGFloat = factorStr.contains("4x") ? 4.0 : 2.0
                if let upscaledImage = upscaleImage(uiImage, scaleFactor: scaleFactor),
                   let upscaledJPEG = upscaledImage.jpegData(compressionQuality: 0.95) {
                    processedData = upscaledJPEG
                }
            }
        }
        
        // 2. Внедрение метаданных IPTC / EXIF и гарантия JPEG-контейнера
        let preparedData = writeMetadata(
            to: processedData,
            title: photo.title,
            description: photo.description,
            keywords: photo.keywords,
            categories: photo.categories
        ) ?? processedData
        
        // 3. Сжатие JPEG по требованию
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
    
    /// Апскейл изображения с использованием высшего качества фильтрации
    func upscaleImage(_ image: UIImage, scaleFactor: CGFloat) -> UIImage? {
        let targetSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    private func writeMetadata(
        to imageData: Data,
        title: String,
        description: String,
        keywords: [String],
        categories: [String]
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        
        // Всегда используем стандартный контейнер JPEG (public.jpeg)
        let jpegType = UTType.jpeg.identifier as CFString
        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(destinationData, jpegType, 1, nil) else { return nil }
        
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        
        // IPTC Dictionary
        let iptcKey = kCGImagePropertyIPTCDictionary as String
        var iptc = (properties[iptcKey] as? [String: Any]) ?? [:]
        iptc[kCGImagePropertyIPTCObjectName as String] = title
        iptc[kCGImagePropertyIPTCCaptionAbstract as String] = description
        
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
    func prepareVideoForUpload(
        videoURL: URL,
        photo: PhotoMetadata
    ) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        
        let ext = videoURL.pathExtension.lowercased()
        let actualExt = ext.isEmpty ? "mp4" : ext
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("\(UUID().uuidString).\(actualExt)")
        
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
        
        var metadataItems: [AVMetadataItem] = []
        
        let titleItem = AVMutableMetadataItem()
        titleItem.keySpace = AVMetadataKeySpace.common
        titleItem.key = AVMetadataKey.commonKeyTitle as NSCopying & NSObjectProtocol
        titleItem.value = photo.title as NSString
        metadataItems.append(titleItem)
        
        let descItem = AVMutableMetadataItem()
        descItem.keySpace = AVMetadataKeySpace.common
        descItem.key = AVMetadataKey.commonKeyDescription as NSCopying & NSObjectProtocol
        descItem.value = photo.description as NSString
        metadataItems.append(descItem)
        
        let keywordsString = photo.keywords.joined(separator: ", ")
        
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
