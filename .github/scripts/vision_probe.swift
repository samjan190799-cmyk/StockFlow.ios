// Одноразовая проба: какие расстояния выдаёт Vision (feature print, revision 1) на реальных фотографиях
// (системные обои macOS на раннере) для пар «тот же кадр / лёгкая обработка / соседний кадр / другая сцена».
// Повторяет конвейер приложения: миниатюра 300 px -> JPEG 0.75 -> отпечаток. Ничего не пишет и не отправляет.
import Foundation
import CoreGraphics
import ImageIO
import Vision
import UniformTypeIdentifiers

func loadSource(_ url: URL, maxPixel: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

func jpegRoundTrip(_ image: CGImage, quality: Double) -> CGImage? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest), let source = CGImageSourceCreateWithData(data, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func resized(_ image: CGImage, maxSide: Int) -> CGImage? {
    let scale = Double(maxSide) / Double(max(image.width, image.height))
    let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

/// Миниатюра как в приложении: 300 px, JPEG 0.75
func appThumb(_ image: CGImage, quality: Double = 0.75) -> CGImage? {
    guard let small = resized(image, maxSide: 300) else { return nil }
    return jpegRoundTrip(small, quality: quality)
}

func cropped(_ image: CGImage, fraction: Double, offsetX: Double = 0) -> CGImage? {
    let w = Double(image.width) * fraction, h = Double(image.height) * fraction
    let x = (Double(image.width) - w) / 2 + offsetX * Double(image.width)
    let y = (Double(image.height) - h) / 2
    return image.cropping(to: CGRect(x: max(0, x), y: y, width: w, height: h))
}

func brighter(_ image: CGImage, amount: Double) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    ctx.draw(image, in: rect)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: amount))
    ctx.fill(rect)
    return ctx.makeImage()
}

func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
    let request = VNGenerateImageFeaturePrintRequest()
    request.revision = VNGenerateImageFeaturePrintRequestRevision1
    request.imageCropAndScaleOption = .scaleFill
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    guard (try? handler.perform([request])) != nil else { return nil }
    return request.results?.first as? VNFeaturePrintObservation
}

func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float {
    var d: Float = 0
    try? a.computeDistance(&d, to: b)
    return d
}

func stats(_ values: [Float]) -> String {
    guard !values.isEmpty else { return "нет данных" }
    let sorted = values.sorted()
    return String(format: "min %.2f · медиана %.2f · max %.2f (n=%d)", sorted.first!, sorted[sorted.count / 2], sorted.last!, sorted.count)
}

let fm = FileManager.default
var files: [URL] = []
for dir in ["/System/Library/Desktop Pictures", "/Library/Desktop Pictures"] {
    if let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) {
        files += items.filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
    }
}
files.sort { $0.path < $1.path }
print("Найдено изображений: \(files.count)")
if files.isEmpty {
    print("Нет системных обоев на раннере, проба невозможна")
    exit(0)
}

// Не более 14 файлов, равномерно по списку
let step = max(1, files.count / 14)
let chosen = stride(from: 0, to: files.count, by: step).map { files[$0] }.prefix(14)

struct Entry {
    let name: String
    let source: CGImage
    let base: VNFeaturePrintObservation
}
var entries: [Entry] = []
for url in chosen {
    guard let source = loadSource(url, maxPixel: 1200), let thumb = appThumb(source), let fp = featurePrint(thumb) else {
        print("  пропуск: \(url.lastPathComponent)")
        continue
    }
    entries.append(Entry(name: url.deletingPathExtension().lastPathComponent, source: source, base: fp))
}
print("Обработано: \(entries.count)")

let variants: [(String, (CGImage) -> CGImage?)] = [
    ("тот же файл, миниатюра заново", { appThumb($0) }),
    ("JPEG миниатюры q0.5", { appThumb($0, quality: 0.5) }),
    ("кроп 97%", { cropped($0, fraction: 0.97).flatMap { appThumb($0) } }),
    ("кроп 90%", { cropped($0, fraction: 0.90).flatMap { appThumb($0) } }),
    ("кроп 90% со сдвигом 4%", { cropped($0, fraction: 0.90, offsetX: 0.04).flatMap { appThumb($0) } }),
    ("кроп 80%", { cropped($0, fraction: 0.80).flatMap { appThumb($0) } }),
    ("яркость +6%", { brighter($0, amount: 0.06).flatMap { appThumb($0) } }),
    ("яркость +12%", { brighter($0, amount: 0.12).flatMap { appThumb($0) } }),
]

print("\nОдин и тот же снимок, обработанный по-разному (расстояние до исходной миниатюры):")
for (name, transform) in variants {
    var values: [Float] = []
    for entry in entries {
        if let image = transform(entry.source), let fp = featurePrint(image) {
            values.append(distance(entry.base, fp))
        }
    }
    print("  \(name): \(stats(values))")
}

print("\nРазные файлы между собой:")
var cross: [(Float, String, String)] = []
for i in 0..<entries.count {
    for j in (i + 1)..<entries.count {
        cross.append((distance(entries[i].base, entries[j].base), entries[i].name, entries[j].name))
    }
}
cross.sort { $0.0 < $1.0 }
print("  \(stats(cross.map { $0.0 }))")
print("  Самые близкие пары:")
for item in cross.prefix(8) {
    print(String(format: "    %.2f  %@  <->  %@", item.0, item.1, item.2))
}
print("\nПороги в приложении сейчас: точная копия <= 0.03, Строго 0.18, Обычно 0.35, Серии 0.55")
