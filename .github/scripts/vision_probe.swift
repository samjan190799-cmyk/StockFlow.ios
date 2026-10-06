// Одноразовая проба: какие расстояния выдаёт Vision (feature print, revision 1) для пар «одинаковые / похожие / разные».
// Нужна только чтобы проверить пороги в DuplicateSensitivity. Ничего не пишет и не отправляет.
import Foundation
import CoreGraphics
import ImageIO
import Vision
import UniformTypeIdentifiers

struct LCG {
    var state: UInt32
    mutating func next() -> CGFloat {
        state = state &* 1664525 &+ 1013904223
        return CGFloat((state >> 8) & 0xFFFF) / 65535.0
    }
}

let width = 640
let height = 427

func render(_ draw: (CGContext) -> Void) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    draw(context)
    return context.makeImage()!
}

func gradient(_ ctx: CGContext, _ top: [CGFloat], _ bottom: [CGFloat], _ rect: CGRect) {
    let colors = [CGColor(red: top[0], green: top[1], blue: top[2], alpha: 1),
                  CGColor(red: bottom[0], green: bottom[1], blue: bottom[2], alpha: 1)] as CFArray
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    ctx.restoreGState()
}

/// Горный пейзаж с «фотографической» текстурой: параметры имитируют соседние кадры серии
func mountains(shift: CGFloat = 0, zoom: CGFloat = 1, brightness: CGFloat = 0, noiseSeed: UInt32 = 1, noise: CGFloat = 0.04) -> CGImage {
    render { ctx in
        let w = CGFloat(width), h = CGFloat(height)
        ctx.translateBy(x: w / 2 + shift, y: h / 2)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -w / 2, y: -h / 2)
        let b = brightness
        gradient(ctx, [0.35 + b, 0.6 + b, 0.95 + b], [0.85 + b, 0.92 + b, 1.0], CGRect(x: -50, y: h * 0.4, width: w + 100, height: h * 0.7))
        let peaks: [(CGFloat, CGFloat)] = [(0.15, 0.62), (0.4, 0.82), (0.7, 0.7), (0.92, 0.58)]
        for (x, y) in peaks {
            ctx.setFillColor(CGColor(red: 0.35 + b, green: 0.4 + b, blue: 0.5 + b, alpha: 1))
            ctx.move(to: CGPoint(x: w * x - 230, y: h * 0.4))
            ctx.addLine(to: CGPoint(x: w * x, y: h * y))
            ctx.addLine(to: CGPoint(x: w * x + 230, y: h * 0.4))
            ctx.fillPath()
        }
        gradient(ctx, [0.3 + b, 0.45 + b, 0.6 + b], [0.1 + b, 0.2 + b, 0.35 + b], CGRect(x: -50, y: -50, width: w + 100, height: h * 0.4 + 50))
        var rng = LCG(state: noiseSeed)
        for _ in 0..<5000 {
            let level = rng.next() * noise * 2 - noise
            ctx.setFillColor(CGColor(red: 0.5 + level, green: 0.5 + level, blue: 0.5 + level, alpha: 0.25))
            ctx.fill(CGRect(x: rng.next() * w, y: rng.next() * h, width: 2, height: 2))
        }
    }
}

/// Совсем другая сцена: ночной город
func city() -> CGImage {
    render { ctx in
        let w = CGFloat(width), h = CGFloat(height)
        gradient(ctx, [0.04, 0.06, 0.2], [0.2, 0.2, 0.45], CGRect(x: 0, y: 0, width: w, height: h))
        var rng = LCG(state: 9)
        var x: CGFloat = 0
        while x < w {
            let bw = 40 + rng.next() * 50
            let bh = h * (0.2 + rng.next() * 0.5)
            ctx.setFillColor(CGColor(red: 0.07, green: 0.09, blue: 0.18, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: bw, height: bh))
            var wy: CGFloat = 8
            while wy < bh - 8 {
                var wx = x + 6
                while wx < x + bw - 8 {
                    if rng.next() > 0.45 {
                        ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
                        ctx.fill(CGRect(x: wx, y: wy, width: 5, height: 7))
                    }
                    wx += 12
                }
                wy += 15
            }
            x += bw + 3
        }
    }
}

func reencode(_ image: CGImage, quality: Double) -> CGImage {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    CGImageDestinationFinalize(dest)
    let source = CGImageSourceCreateWithData(data, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}

func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation {
    let request = VNGenerateImageFeaturePrintRequest()
    request.revision = VNGenerateImageFeaturePrintRequestRevision1
    request.imageCropAndScaleOption = .scaleFill
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try! handler.perform([request])
    return request.results!.first as! VNFeaturePrintObservation
}

func distance(_ a: CGImage, _ b: CGImage) -> Float {
    var d: Float = 0
    try! featurePrint(a).computeDistance(&d, to: featurePrint(b))
    return d
}

let base = mountains()
let rows: [(String, CGImage)] = [
    ("тот же кадр, JPEG q0.5", reencode(base, quality: 0.5)),
    ("тот же кадр, JPEG q0.8", reencode(base, quality: 0.8)),
    ("другой шум сенсора", mountains(noiseSeed: 77)),
    ("яркость +6%", mountains(brightness: 0.06)),
    ("сдвиг 10 px", mountains(shift: 10)),
    ("сдвиг 40 px", mountains(shift: 40)),
    ("зум 1.05x", mountains(zoom: 1.05)),
    ("зум 1.15x", mountains(zoom: 1.15)),
    ("зум 1.15x + сдвиг 30 + яркость +4%", mountains(shift: 30, zoom: 1.15, brightness: 0.04, noiseSeed: 5)),
    ("ДРУГАЯ сцена (ночной город)", city()),
]

print("Расстояния Vision (feature print rev.1) от базового кадра:")
for (name, image) in rows {
    print(String(format: "  %.3f  %@", distance(base, image), name))
}
print("Пороги в приложении: точная копия <= 0.03, Строго 0.18, Обычно 0.35, Серии 0.55")
