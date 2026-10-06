import Foundation
import UIKit
import Vision

/// Насколько похожими должны быть кадры, чтобы считаться одной группой
enum DuplicateSensitivity: Int, CaseIterable, Identifiable, Sendable {
    case strict = 0
    case normal = 1
    case loose = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .strict: return "Строго"
        case .normal: return "Обычно"
        case .loose: return "Серии"
        }
    }

    /// Порог расстояния между отпечатками изображений Vision: чем меньше, тем кадры более одинаковые
    var threshold: Float {
        switch self {
        case .strict: return 0.18
        case .normal: return 0.35
        case .loose: return 0.55
        }
    }
}

/// Группа одинаковых или очень похожих файлов. Первым в списке идёт тот, который рекомендуется оставить.
struct DuplicateGroup: Identifiable, Sendable {
    enum Kind: Sendable {
        case exact
        case similar
    }

    let id = UUID()
    let kind: Kind
    var photoIDs: [UUID]

    var keepID: UUID { photoIDs[0] }
    var removableIDs: [UUID] { Array(photoIDs.dropFirst()) }
}

/// Ищет дубли и похожие кадры по миниатюрам (оригиналы не читаются, поэтому поиск быстрый).
actor DuplicateDetector {
    static let shared = DuplicateDetector()

    /// Максимум файлов за один проход: сравнение идёт попарно
    private let maxItems = 1500
    /// Расстояние, при котором файлы считаются точной копией
    private let exactThreshold: Float = 0.03

    struct Item: Sendable {
        let id: UUID
        let thumbnail: Data
        let isUploaded: Bool
        let fileBytes: Double
    }

    func findGroups(items rawItems: [Item], threshold: Float) -> [DuplicateGroup] {
        let items = Array(rawItems.prefix(maxItems))
        guard items.count > 1 else { return [] }

        // 1. Отпечаток изображения для каждого файла
        var prints: [VNFeaturePrintObservation?] = []
        prints.reserveCapacity(items.count)
        for item in items {
            prints.append(featurePrint(for: item.thumbnail))
        }

        // 2. Попарное сравнение и объединение близких файлов в группы
        var parent = Array(0..<items.count)
        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current {
                parent[current] = parent[parent[current]]
                current = parent[current]
            }
            return current
        }

        var edges: [(Int, Int, Float)] = []
        for i in 0..<items.count {
            guard let first = prints[i] else { continue }
            for j in (i + 1)..<items.count {
                guard let second = prints[j] else { continue }
                var distance: Float = 0
                do {
                    try first.computeDistance(&distance, to: second)
                } catch {
                    continue
                }
                if distance <= threshold {
                    edges.append((i, j, distance))
                    let a = root(i)
                    let b = root(j)
                    if a != b { parent[a] = b }
                }
            }
        }

        // 3. Сбор групп; группа считается «точной копией», если все связи в ней почти нулевые
        var members: [Int: [Int]] = [:]
        for index in 0..<items.count where prints[index] != nil {
            members[root(index), default: []].append(index)
        }
        var worstEdge: [Int: Float] = [:]
        for (i, _, distance) in edges {
            let key = root(i)
            worstEdge[key] = max(worstEdge[key] ?? 0, distance)
        }

        var groups: [DuplicateGroup] = []
        for (key, indexes) in members where indexes.count > 1 {
            let ranked = indexes.sorted { lhs, rhs in
                better(items[lhs], than: items[rhs])
            }
            let kind: DuplicateGroup.Kind = (worstEdge[key] ?? 0) <= exactThreshold ? .exact : .similar
            groups.append(DuplicateGroup(kind: kind, photoIDs: ranked.map { items[$0].id }))
        }

        // Сначала точные копии, затем самые большие группы
        return groups.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .exact }
            return lhs.photoIDs.count > rhs.photoIDs.count
        }
    }

    // MARK: - Внутреннее

    /// Какой из двух файлов лучше оставить: уже отправленный, затем более «тяжёлый», затем более резкий
    private func better(_ a: Item, than b: Item) -> Bool {
        if a.isUploaded != b.isUploaded { return a.isUploaded }
        if abs(a.fileBytes - b.fileBytes) > 1 { return a.fileBytes > b.fileBytes }
        return sharpness(of: a.thumbnail) > sharpness(of: b.thumbnail)
    }

    private func featurePrint(for data: Data) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(data: data, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first as? VNFeaturePrintObservation
    }

    /// Оценка резкости: средняя энергия перепадов яркости по уменьшенной копии 96×96
    private func sharpness(of data: Data) -> Double {
        guard let cgImage = UIImage(data: data)?.cgImage else { return 0 }
        let side = 96
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
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 0 }

        var energy = 0.0
        for y in 0..<(side - 1) {
            for x in 0..<(side - 1) {
                let value = Int(pixels[y * side + x])
                let dx = Int(pixels[y * side + x + 1]) - value
                let dy = Int(pixels[(y + 1) * side + x]) - value
                energy += Double(dx * dx + dy * dy)
            }
        }
        return energy / Double((side - 1) * (side - 1))
    }
}
