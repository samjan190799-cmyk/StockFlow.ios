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
    
    /// Максимум пикселей после апскейла: 40 Мп ≈ 160 МБ в памяти. Раньше 4x для 12-Мп снимка давал 192 Мп (~770 МБ),
    /// и система закрывала приложение.
    private static let maxUpscaledPixels: CGFloat = 40_000_000
    
    /// Апскейл изображения с использованием высшего качества фильтрации.
    /// Возвращает nil, если увеличение невозможно без превышения лимита памяти (снимок и так достаточно большой).
    func upscaleImage(_ image: UIImage, scaleFactor: CGFloat) -> UIImage? {
        let sourcePixels = image.size.width * image.size.height
        guard sourcePixels > 0 else { return nil }
        let allowedFactor = (Self.maxUpscaledPixels / sourcePixels).squareRoot()
        let factor = min(scaleFactor, allowedFactor)
        guard factor > 1.05 else { return nil }
        
        let targetSize = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        
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
    
    private static let rawExtensions: Set<String> = ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "raw"]
    
    /// Приводит выбранный снимок к JPEG-файлу в папке очереди, не загружая его целиком в память.
    /// JPEG копируется как есть; HEIC, PNG, TIFF и RAW перекодируются через ImageIO с ограничением размера
    /// (раньше они целиком декодировались через UIImage: ProRAW на 48 Мп занимал гигабайты).
    /// Возвращает размер получившегося файла в байтах или nil при ошибке.
    func importPhoto(from sourceURL: URL, to targetURL: URL) -> Int64? {
        return autoreleasepool { () -> Int64? in
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, sourceOptions) else { return nil }
            
            let typeIdentifier = (CGImageSourceGetType(source) as String?) ?? ""
            let sourceType = UTType(typeIdentifier)
            let isJPEG = sourceType?.conforms(to: .jpeg) ?? false
            let isRAW = (sourceType?.conforms(to: .rawImage) ?? false)
                || Self.rawExtensions.contains(sourceURL.pathExtension.lowercased())
            
            try? FileManager.default.removeItem(at: targetURL)
            
            if isJPEG {
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: targetURL)
                } catch {
                    return nil
                }
            } else {
                let maxSide = isRAW ? 6000 : 8192
                guard let cgImage = Self.downsampledImage(from: source, maxSide: maxSide, preferEmbeddedPreview: isRAW),
                      let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                    return nil
                }
                
                var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
                // Поворот уже применён к пикселям, служебные блоки RAW в JPEG не нужны
                properties[kCGImagePropertyOrientation as String] = 1
                properties.removeValue(forKey: kCGImagePropertyDNGDictionary as String)
                properties.removeValue(forKey: "{Raw}")
                if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                    tiff[kCGImagePropertyTIFFOrientation as String] = 1
                    properties[kCGImagePropertyTIFFDictionary as String] = tiff
                }
                properties[kCGImageDestinationLossyCompressionQuality as String] = 0.95
                CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
                
                guard CGImageDestinationFinalize(destination) else {
                    try? FileManager.default.removeItem(at: targetURL)
                    return nil
                }
            }
            
            return ((try? FileManager.default.attributesOfItem(atPath: targetURL.path))?[.size] as? Int64) ?? 0
        }
    }
    
    /// Уменьшенная копия снимка. Для RAW сначала берётся встроенный JPEG-предпросмотр (почти без памяти);
    /// полное декодирование RAW — только если предпросмотра нет или он слишком мал.
    private static func downsampledImage(from source: CGImageSource, maxSide: Int, preferEmbeddedPreview: Bool) -> CGImage? {
        if preferEmbeddedPreview {
            let previewOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: maxSide
            ]
            if let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, previewOptions as CFDictionary),
               max(preview.width, preview.height) >= 3000 {
                return preview
            }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
    
    /// Авто-апскейл JPEG-файла на месте с ограничением итогового размера. Возвращает true, если файл изменён.
    func upscaleJPEGFile(at url: URL, scaleFactor: CGFloat) -> Bool {
        return autoreleasepool { () -> Bool in
            guard let image = UIImage(contentsOfFile: url.path),
                  let upscaled = upscaleImage(image, scaleFactor: scaleFactor),
                  let data = upscaled.jpegData(compressionQuality: 0.92) else {
                return false
            }
            do {
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }
    }
    
    /// Готовит фото к отправке, читая исходный файл с диска (а не целиком в память).
    /// Результат — JPEG с IPTC/EXIF во временном файле. Вызывающий обязан удалить файл.
    /// RAW (DNG/ProRAW и др.) уменьшается до 6000 px по длинной стороне: полное декодирование 48-Мп RAW
    /// занимало 1–2 ГБ памяти, и система закрывала приложение.
    func prepareImageFileForUpload(sourceURL: URL, photo: PhotoMetadata, compress: Bool) -> URL? {
        return autoreleasepool { () -> URL? in
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, sourceOptions) else { return nil }
            
            let typeIdentifier = (CGImageSourceGetType(source) as String?) ?? ""
            let sourceType = UTType(typeIdentifier)
            let isJPEG = sourceType?.conforms(to: .jpeg) ?? false
            let isRAW = (sourceType?.conforms(to: .rawImage) ?? false)
                || Self.rawExtensions.contains(sourceURL.pathExtension.lowercased())
            
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                return nil
            }
            
            let baseProperties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
            var properties = Self.metadataProperties(
                base: baseProperties,
                title: photo.title,
                description: photo.description,
                keywords: photo.keywords,
                categories: photo.categories
            )
            
            if isJPEG {
                if compress {
                    properties[kCGImageDestinationLossyCompressionQuality as String] = 0.85
                }
                CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
            } else {
                // HEIC, PNG, TIFF, RAW: читаем картинку с ограничением размера, чтобы не раздувать память
                let maxSide = isRAW ? 6000 : 8192
                let thumbnailOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: false,
                    kCGImageSourceThumbnailMaxPixelSize: maxSide
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                    try? FileManager.default.removeItem(at: outputURL)
                    return nil
                }
                
                // Поворот уже применён к пикселям, служебные блоки RAW в JPEG не нужны
                properties[kCGImagePropertyOrientation as String] = 1
                properties.removeValue(forKey: kCGImagePropertyDNGDictionary as String)
                properties.removeValue(forKey: "{Raw}")
                if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                    tiff[kCGImagePropertyTIFFOrientation as String] = 1
                    properties[kCGImagePropertyTIFFDictionary as String] = tiff
                }
                properties[kCGImageDestinationLossyCompressionQuality as String] = compress ? 0.85 : 0.92
                CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
            }
            
            guard CGImageDestinationFinalize(destination) else {
                try? FileManager.default.removeItem(at: outputURL)
                return nil
            }
            return outputURL
        }
    }
    
    /// Свойства изображения с подставленными IPTC / TIFF / EXIF (заголовок, описание, ключевые слова, категории)
    private static func metadataProperties(
        base: [String: Any],
        title: String,
        description: String,
        keywords: [String],
        categories: [String]
    ) -> [String: Any] {
        var properties = base
        
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
        
        let tiffKey = kCGImagePropertyTIFFDictionary as String
        var tiff = (properties[tiffKey] as? [String: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFImageDescription as String] = description
        properties[tiffKey] = tiff
        
        let exifKey = kCGImagePropertyExifDictionary as String
        var exif = (properties[exifKey] as? [String: Any]) ?? [:]
        exif[kCGImagePropertyExifUserComment as String] = description
        properties[exifKey] = exif
        
        return properties
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
