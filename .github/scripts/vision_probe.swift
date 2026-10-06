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

// Процедурные «природные» сцены: сумма октав value-noise (спектр близок к фотографиям), три канала с разным сдвигом
struct Grid {
    let size: Int
    var values: [Float]
    init(size: Int, seed: UInt32) {
        self.size = size
        var state = seed &* 2654435761 &+ 12345
        values = (0..<(size * size)).map { _ in
            state = state &* 1664525 &+ 1013904223
            return Float((state >> 8) & 0xFFFF) / 65535.0
        }
    }
    func sample(_ x: Float, _ y: Float) -> Float {
        let fx = x * Float(size - 1), fy = y * Float(size - 1)
        let x0 = Int(fx), y0 = Int(fy)
        let x1 = min(x0 + 1, size - 1), y1 = min(y0 + 1, size - 1)
        let tx = fx - Float(x0), ty = fy - Float(y0)
        let a = values[y0 * size + x0], b = values[y0 * size + x1]
        let c = values[y1 * size + x0], d = values[y1 * size + x1]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    }
}

func fractalScene(seed: UInt32, width: Int = 1200, height: Int = 800) -> CGImage? {
    let octaves = [4, 8, 16, 32, 64, 128].map { Grid(size: $0 + 1, seed: seed &* 31 &+ UInt32($0)) }
    let weights: [Float] = [0.35, 0.25, 0.17, 0.12, 0.07, 0.04]
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let u = Float(x) / Float(width - 1), v = Float(y) / Float(height - 1)
            var channels: [Float] = [0, 0, 0]
            for c in 0..<3 {
                var value: Float = 0
                for (index, grid) in octaves.enumerated() {
                    value += weights[index] * grid.sample(min(max(u + Float(c) * 0.013, 0), 1), min(max(v, 0), 1))
                }
                channels[c] = value
            }
            let base = (y * width + x) * 4
            for c in 0..<3 { pixels[base + c] = UInt8(max(0, min(255, channels[c] * 255 * 1.1))) }
        }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
}

func noisy(_ image: CGImage, amplitude: Int) -> CGImage? {
    let w = image.width, h = image.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return nil }
    let buffer = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var state: UInt32 = 99
    for i in 0..<(w * h) {
        for c in 0..<3 {
            state = state &* 1664525 &+ 1013904223
            let delta = Int((state >> 8) % UInt32(amplitude * 2 + 1)) - amplitude
            buffer[i * 4 + c] = UInt8(max(0, min(255, Int(buffer[i * 4 + c]) + delta)))
        }
    }
    return ctx.makeImage()
}

print("Генерация процедурных сцен...")
struct Entry {
    let name: String
    let source: CGImage
    let base: VNFeaturePrintObservation
}
var entries: [Entry] = []
for seed in 1...8 {
    guard let source = fractalScene(seed: UInt32(seed)), let thumb = appThumb(source), let fp = featurePrint(thumb) else { continue }
    entries.append(Entry(name: "scene\(seed)", source: source, base: fp))
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
    ("шум сенсора ±6", { noisy($0, amplitude: 6).flatMap { appThumb($0) } }),
    ("шум сенсора ±12", { noisy($0, amplitude: 12).flatMap { appThumb($0) } }),
    ("соседний кадр: сдвиг 10% + зум 8%", { cropped($0, fraction: 0.92, offsetX: 0.10).flatMap { appThumb($0) } }),
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
