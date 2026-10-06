import SwiftUI
import UIKit

/// Демо-режим: примеры файлов, а также имитация ИИ-анализа и отправки на сток.
/// Позволяет попробовать приложение без ключей ИИ и без аккаунтов на стоках
/// (в том числе при проверке в App Review). В сеть и на стоки ничего не уходит.
enum DemoMode {
    /// Название вымышленного стока, на который «отправляются» демо-файлы
    static let stockName = "Demo Stock"

    struct Sample {
        let filename: String
        let title: String
        let description: String
        let keywords: [String]
        let categories: [String]
        let draw: (CGContext, CGSize) -> Void
    }

    // MARK: - Создание демо-файлов

    /// Рисует примеры, сохраняет их как JPEG в папку очереди и возвращает готовые к добавлению записи
    @MainActor
    static func makeSamplePhotos(into directory: URL) -> [PhotoMetadata] {
        var result: [PhotoMetadata] = []
        let size = CGSize(width: 1600, height: 1067)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        for sample in samples {
            let image = renderer.image { rendererContext in
                sample.draw(rendererContext.cgContext, size)
            }
            guard let jpeg = image.jpegData(compressionQuality: 0.85) else { continue }

            let id = UUID()
            let fileURL = directory.appendingPathComponent("\(id.uuidString).jpg")
            do {
                try jpeg.write(to: fileURL, options: .atomic)
            } catch {
                continue
            }

            let thumbnail = image.preparingThumbnail(of: CGSize(width: 300, height: 200))?.jpegData(compressionQuality: 0.75)
            let sizeText = ByteCountFormatter.string(fromByteCount: Int64(jpeg.count), countStyle: .file)

            result.append(
                PhotoMetadata(
                    id: id,
                    filename: sample.filename,
                    fileSize: sizeText,
                    title: "",
                    keywords: [],
                    description: "",
                    status: .new,
                    selectedStocks: [stockName],
                    localURLPath: fileURL.path,
                    thumbnailData: thumbnail,
                    isVideo: false,
                    isDemo: true
                )
            )
        }
        return result
    }

    /// Заготовленные метаданные «ИИ-анализа» для демо-файла (всегда на английском, как на настоящих стоках)
    static func metadata(forFilename filename: String) -> AIResult {
        if let sample = samples.first(where: { $0.filename == filename }) {
            return AIResult(
                title: sample.title,
                description: sample.description,
                keywords: sample.keywords,
                categories: sample.categories
            )
        }
        return AIResult(
            title: "Demo stock photo",
            description: "Sample illustration generated inside the app for the demo mode",
            keywords: ["demo", "sample", "illustration", "stock", "photo", "example", "test"],
            categories: ["Miscellaneous"]
        )
    }

    // MARK: - Примеры

    static var samples: [Sample] {
        [
            Sample(
                filename: "Demo_Sunset_Beach.jpg",
                title: "Golden sunset over a calm ocean beach",
                description: "Warm orange sunset sky reflecting on calm sea water along an empty sandy beach at dusk",
                keywords: ["sunset", "beach", "ocean", "sea", "sky", "orange", "golden hour", "horizon", "sun", "calm", "dusk",
                           "evening", "coast", "seascape", "sand", "summer", "travel", "vacation", "tropical", "nature",
                           "landscape", "peaceful", "scenic", "reflection"],
                categories: ["Nature", "Parks/Outdoor"],
                draw: drawSunsetBeach
            ),
            Sample(
                filename: "Demo_Mountain_Lake.jpg",
                title: "Snow capped mountains reflected in an alpine lake",
                description: "Calm alpine lake mirroring snow capped mountain peaks under a clear blue morning sky",
                keywords: ["mountain", "lake", "alpine", "snow", "peak", "reflection", "water", "sky", "blue", "nature",
                           "landscape", "scenic", "wilderness", "outdoor", "travel", "hiking", "calm", "morning",
                           "panorama", "range", "summit", "tranquil", "cold", "wild"],
                categories: ["Nature", "Parks/Outdoor"],
                draw: drawMountainLake
            ),
            Sample(
                filename: "Demo_City_Night.jpg",
                title: "City skyline at night with glowing windows",
                description: "Modern city skyline at night with lit office windows and a bright moon in a dark blue sky",
                keywords: ["city", "skyline", "night", "buildings", "skyscraper", "urban", "windows", "lights", "moon",
                           "downtown", "architecture", "business", "metropolis", "dark", "evening", "cityscape",
                           "modern", "office", "tower", "illuminated", "dusk", "town"],
                categories: ["Buildings/Landmarks", "Business/Finance"],
                draw: drawCityNight
            ),
            Sample(
                filename: "Demo_Forest_Path.jpg",
                title: "Winding path through a green forest",
                description: "Sunlit dirt path winding between rows of green pine trees in a quiet summer forest",
                keywords: ["forest", "path", "trees", "green", "pine", "woods", "trail", "nature", "summer", "outdoor",
                           "hiking", "walk", "landscape", "woodland", "peaceful", "fresh", "park", "season",
                           "scenic", "tranquil", "leaves", "road", "journey"],
                categories: ["Nature", "Parks/Outdoor"],
                draw: drawForestPath
            ),
            Sample(
                filename: "Demo_Coffee_Cup.jpg",
                title: "Steaming cup of coffee on a warm background",
                description: "White cup of hot coffee with rising steam on a saucer against a warm beige background",
                keywords: ["coffee", "cup", "steam", "hot", "drink", "beverage", "breakfast", "morning", "cafe", "espresso",
                           "saucer", "warm", "beige", "mug", "aroma", "caffeine", "break", "relax", "minimal",
                           "isolated", "food", "table", "cozy"],
                categories: ["Food and drink", "Objects"],
                draw: drawCoffeeCup
            ),
            Sample(
                filename: "Demo_Desert_Dunes.jpg",
                title: "Golden sand dunes under a warm desert sky",
                description: "Smooth golden sand dunes with soft shadows under a warm pale orange desert sky at sunrise",
                keywords: ["desert", "dunes", "sand", "golden", "sky", "sunrise", "dry", "hot", "landscape", "nature",
                           "arid", "wave", "shadow", "texture", "background", "travel", "adventure", "empty",
                           "horizon", "warm", "sahara", "scenic", "minimal"],
                categories: ["Nature", "Backgrounds/Textures"],
                draw: drawDesertDunes
            )
        ]
    }

    // MARK: - Рисование сцен

    private static func fillGradient(_ ctx: CGContext, from top: UIColor, to bottom: UIColor, in rect: CGRect) {
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        ctx.restoreGState()
    }

    private static func fillCircle(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: UIColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func fillPolygon(_ ctx: CGContext, points: [CGPoint], color: UIColor) {
        guard let first = points.first else { return }
        ctx.setFillColor(color.cgColor)
        ctx.beginPath()
        ctx.move(to: first)
        for point in points.dropFirst() { ctx.addLine(to: point) }
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawSunsetBeach(_ ctx: CGContext, _ size: CGSize) {
        let horizon = size.height * 0.58
        fillGradient(ctx, from: UIColor(red: 0.35, green: 0.18, blue: 0.45, alpha: 1),
                     to: UIColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 1),
                     in: CGRect(x: 0, y: 0, width: size.width, height: horizon))
        fillCircle(ctx, center: CGPoint(x: size.width * 0.5, y: horizon - 40), radius: 130,
                   color: UIColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 1))
        fillGradient(ctx, from: UIColor(red: 0.95, green: 0.55, blue: 0.3, alpha: 1),
                     to: UIColor(red: 0.08, green: 0.25, blue: 0.4, alpha: 1),
                     in: CGRect(x: 0, y: horizon, width: size.width, height: size.height * 0.30))
        ctx.setFillColor(UIColor(red: 0.93, green: 0.78, blue: 0.55, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: size.height * 0.88, width: size.width, height: size.height * 0.12))
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.35).cgColor)
        ctx.setLineWidth(3)
        for i in 0..<6 {
            let y = horizon + 30 + CGFloat(i) * 38
            ctx.move(to: CGPoint(x: size.width * 0.35 + CGFloat(i) * 20, y: y))
            ctx.addLine(to: CGPoint(x: size.width * 0.65 - CGFloat(i) * 20, y: y))
        }
        ctx.strokePath()
    }

    private static func drawMountainLake(_ ctx: CGContext, _ size: CGSize) {
        let shore = size.height * 0.62
        fillGradient(ctx, from: UIColor(red: 0.45, green: 0.7, blue: 0.95, alpha: 1),
                     to: UIColor(red: 0.85, green: 0.93, blue: 1.0, alpha: 1),
                     in: CGRect(x: 0, y: 0, width: size.width, height: shore))
        let peaks: [(CGFloat, CGFloat)] = [(0.18, 0.28), (0.42, 0.14), (0.68, 0.24), (0.9, 0.34)]
        for (x, y) in peaks {
            let top = CGPoint(x: size.width * x, y: size.height * y)
            let half = size.width * 0.26
            fillPolygon(ctx, points: [CGPoint(x: top.x - half, y: shore), top, CGPoint(x: top.x + half, y: shore)],
                        color: UIColor(red: 0.35, green: 0.42, blue: 0.55, alpha: 1))
            fillPolygon(ctx, points: [CGPoint(x: top.x - half * 0.22, y: top.y + (shore - top.y) * 0.22), top,
                                      CGPoint(x: top.x + half * 0.22, y: top.y + (shore - top.y) * 0.22)],
                        color: UIColor(white: 0.96, alpha: 1))
        }
        fillGradient(ctx, from: UIColor(red: 0.3, green: 0.45, blue: 0.62, alpha: 1),
                     to: UIColor(red: 0.1, green: 0.22, blue: 0.38, alpha: 1),
                     in: CGRect(x: 0, y: shore, width: size.width, height: size.height - shore))
    }

    private static func drawCityNight(_ ctx: CGContext, _ size: CGSize) {
        fillGradient(ctx, from: UIColor(red: 0.04, green: 0.06, blue: 0.2, alpha: 1),
                     to: UIColor(red: 0.2, green: 0.2, blue: 0.45, alpha: 1),
                     in: CGRect(origin: .zero, size: size))
        fillCircle(ctx, center: CGPoint(x: size.width * 0.82, y: size.height * 0.16), radius: 60,
                   color: UIColor(red: 0.97, green: 0.96, blue: 0.85, alpha: 1))
        var seed: UInt32 = 7
        func next() -> CGFloat {
            seed = seed &* 1664525 &+ 1013904223
            return CGFloat(seed >> 8 & 0xFFFF) / 65535.0
        }
        var x: CGFloat = 0
        while x < size.width {
            let width = 90 + next() * 90
            let height = size.height * (0.25 + next() * 0.45)
            let top = size.height - height
            ctx.setFillColor(UIColor(red: 0.07, green: 0.09, blue: 0.18, alpha: 1).cgColor)
            ctx.fill(CGRect(x: x, y: top, width: width, height: height))
            var wy = top + 18
            while wy < size.height - 20 {
                var wx = x + 12
                while wx < x + width - 14 {
                    if next() > 0.4 {
                        ctx.setFillColor(UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 0.95).cgColor)
                        ctx.fill(CGRect(x: wx, y: wy, width: 10, height: 14))
                    }
                    wx += 24
                }
                wy += 30
            }
            x += width + 6
        }
    }

    private static func drawForestPath(_ ctx: CGContext, _ size: CGSize) {
        fillGradient(ctx, from: UIColor(red: 0.7, green: 0.88, blue: 0.95, alpha: 1),
                     to: UIColor(red: 0.85, green: 0.95, blue: 0.8, alpha: 1),
                     in: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.45))
        ctx.setFillColor(UIColor(red: 0.25, green: 0.5, blue: 0.22, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: size.height * 0.45, width: size.width, height: size.height * 0.55))
        fillPolygon(ctx, points: [CGPoint(x: size.width * 0.46, y: size.height * 0.45),
                                  CGPoint(x: size.width * 0.54, y: size.height * 0.45),
                                  CGPoint(x: size.width * 0.86, y: size.height),
                                  CGPoint(x: size.width * 0.14, y: size.height)],
                    color: UIColor(red: 0.72, green: 0.6, blue: 0.4, alpha: 1))
        for row in 0..<4 {
            let scale = 0.5 + CGFloat(row) * 0.3
            let baseY = size.height * (0.5 + CGFloat(row) * 0.16)
            for side in [-1.0, 1.0] {
                for col in 0..<3 {
                    let cx = size.width * 0.5 + CGFloat(side) * (size.width * (0.14 + CGFloat(col) * 0.12) * scale + 60)
                    let treeHeight = 280 * scale
                    fillPolygon(ctx, points: [CGPoint(x: cx - 70 * scale, y: baseY), CGPoint(x: cx, y: baseY - treeHeight),
                                              CGPoint(x: cx + 70 * scale, y: baseY)],
                                color: UIColor(red: 0.08, green: 0.32 + CGFloat(row) * 0.04, blue: 0.12, alpha: 1))
                }
            }
        }
    }

    private static func drawCoffeeCup(_ ctx: CGContext, _ size: CGSize) {
        fillGradient(ctx, from: UIColor(red: 0.96, green: 0.9, blue: 0.8, alpha: 1),
                     to: UIColor(red: 0.85, green: 0.72, blue: 0.55, alpha: 1),
                     in: CGRect(origin: .zero, size: size))
        let cx = size.width * 0.5
        let cy = size.height * 0.62
        ctx.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 330, y: cy + 90, width: 660, height: 150))
        ctx.setFillColor(UIColor(white: 0.9, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 250, y: cy + 110, width: 500, height: 100))
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: cx - 170, y: cy - 150, width: 340, height: 250))
        ctx.fillEllipse(in: CGRect(x: cx - 170, y: cy + 50, width: 340, height: 100))
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(26)
        ctx.strokeEllipse(in: CGRect(x: cx + 120, y: cy - 90, width: 130, height: 150))
        ctx.setFillColor(UIColor(red: 0.28, green: 0.15, blue: 0.08, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 170, y: cy - 190, width: 340, height: 90))
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.55).cgColor)
        ctx.setLineWidth(10)
        ctx.setLineCap(.round)
        for i in 0..<3 {
            let x = cx - 70 + CGFloat(i) * 70
            ctx.move(to: CGPoint(x: x, y: cy - 200))
            ctx.addCurve(to: CGPoint(x: x, y: cy - 380),
                         control1: CGPoint(x: x - 45, y: cy - 260),
                         control2: CGPoint(x: x + 45, y: cy - 320))
        }
        ctx.strokePath()
    }

    private static func drawDesertDunes(_ ctx: CGContext, _ size: CGSize) {
        fillGradient(ctx, from: UIColor(red: 0.98, green: 0.8, blue: 0.6, alpha: 1),
                     to: UIColor(red: 1.0, green: 0.93, blue: 0.8, alpha: 1),
                     in: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.55))
        fillCircle(ctx, center: CGPoint(x: size.width * 0.75, y: size.height * 0.3), radius: 90,
                   color: UIColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1))
        let layers: [(CGFloat, UIColor)] = [
            (0.50, UIColor(red: 0.88, green: 0.66, blue: 0.4, alpha: 1)),
            (0.62, UIColor(red: 0.8, green: 0.55, blue: 0.3, alpha: 1)),
            (0.76, UIColor(red: 0.7, green: 0.45, blue: 0.24, alpha: 1))
        ]
        for (index, layer) in layers.enumerated() {
            let baseY = size.height * layer.0
            ctx.setFillColor(layer.1.cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: size.height))
            ctx.addLine(to: CGPoint(x: 0, y: baseY))
            ctx.addCurve(to: CGPoint(x: size.width, y: baseY - 20),
                         control1: CGPoint(x: size.width * (0.25 + CGFloat(index) * 0.1), y: baseY - 150),
                         control2: CGPoint(x: size.width * (0.6 - CGFloat(index) * 0.08), y: baseY + 90))
            ctx.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.closePath()
            ctx.fillPath()
        }
    }
}
