import Foundation
import SwiftUI
import Combine

// MARK: - Структура статистики одного стока
struct StockStats: Identifiable, Sendable {
    let id: String           // ID платформы (например "shutterstock")
    let name: String         // Отображаемое имя
    var totalUploads: Int    // Всего загрузок
    var successUploads: Int  // Успешных загрузок
    var failedUploads: Int   // Ошибочных загрузок
    var lastUploadDate: Date?       // Дата последней загрузки
    var lastUploadFilename: String? // Имя последнего файла

    /// Форматированное время последней синхронизации
    var syncTimeText: String {
        guard let date = lastUploadDate else { return "Нет данных" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60    { return "Только что" }
        if diff < 3600  { return "\(Int(diff / 60)) мин назад" }
        if diff < 86400 { return "\(Int(diff / 3600)) ч назад" }
        return "\(Int(diff / 86400)) д назад"
    }
}

// MARK: - Запись истории загрузки (хранится в UserDefaults)
struct UploadHistoryRecord: Codable, Sendable {
    let platformId: String
    let platformName: String
    let filename: String
    let date: Date
    let isSuccess: Bool
}

// MARK: - StatsManager
@MainActor
final class StatsManager: ObservableObject {

    // MARK: Published
    @Published var statsByStock: [String: StockStats] = [:]
    @Published var isLoading: Bool = false
    @Published var lastRefreshDate: Date? = nil

    // MARK: Ключ хранилища
    private static let historyKey = "stats_upload_history"

    // MARK: Init
    init() {}

    // MARK: - Публичный метод: записать факт загрузки
    /// nonisolated — может вызываться из любого async-контекста без MainActor
    nonisolated static func recordUpload(
        platformId: String,
        platformName: String,
        filename: String,
        isSuccess: Bool
    ) {
        let record = UploadHistoryRecord(
            platformId: platformId,
            platformName: platformName,
            filename: filename,
            date: Date(),
            isSuccess: isSuccess
        )
        var history = loadHistorySync()
        history.append(record)
        // Храним не более 2000 последних записей
        if history.count > 2000 {
            history = Array(history.suffix(2000))
        }
        saveHistorySync(history)
    }

    // MARK: - Обновление статистики (фоновая загрузка)
    func refresh() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            // Захватываем данные на MainActor, потом отпускаем для обработки
            let history = StatsManager.loadHistorySync()
            let connectedPlatforms = StatsManager.getConnectedPlatforms()

            // Вычисляем агрегацию (тяжёлая работа в фоне)
            let result: [String: StockStats] = await Task.detached(priority: .userInitiated) {
                var res: [String: StockStats] = [:]

                // Инициализируем пустую статистику для каждого настроенного стока
                for platform in connectedPlatforms {
                    res[platform.id] = StockStats(
                        id: platform.id,
                        name: platform.name,
                        totalUploads: 0,
                        successUploads: 0,
                        failedUploads: 0,
                        lastUploadDate: nil,
                        lastUploadFilename: nil
                    )
                }

                // Суммируем по истории
                for record in history {
                    guard res[record.platformId] != nil else { continue }
                    res[record.platformId]!.totalUploads += 1
                    if record.isSuccess {
                        res[record.platformId]!.successUploads += 1
                    } else {
                        res[record.platformId]!.failedUploads += 1
                    }
                    // Обновляем время последней загрузки
                    if let existing = res[record.platformId]!.lastUploadDate {
                        if record.date > existing {
                            res[record.platformId]!.lastUploadDate = record.date
                            res[record.platformId]!.lastUploadFilename = record.filename
                        }
                    } else {
                        res[record.platformId]!.lastUploadDate = record.date
                        res[record.platformId]!.lastUploadFilename = record.filename
                    }
                }
                return res
            }.value

            // Обновляем UI на MainActor (мы уже на нём)
            self.statsByStock = result
            self.lastRefreshDate = Date()
            self.isLoading = false
        }
    }

    // MARK: - Вычисляемые свойства для InsightsView

    /// Суммарное количество успешных загрузок
    var totalSuccessUploads: Int {
        statsByStock.values.reduce(0) { $0 + $1.successUploads }
    }

    /// Успешных загрузок для конкретного стока или всех
    func successUploads(for stockName: String) -> Int {
        if stockName == "Все стоки" { return totalSuccessUploads }
        return statsByStock.values.first(where: { $0.name == stockName })?.successUploads ?? 0
    }

    /// Ошибок загрузки для конкретного стока или всех
    func failedUploads(for stockName: String) -> Int {
        if stockName == "Все стоки" {
            return statsByStock.values.reduce(0) { $0 + $1.failedUploads }
        }
        return statsByStock.values.first(where: { $0.name == stockName })?.failedUploads ?? 0
    }

    /// Время последней синхронизации для стока
    func syncTime(for stockName: String) -> String {
        if stockName == "Все стоки" {
            let latest = statsByStock.values.compactMap { $0.lastUploadDate }.max()
            guard let date = latest else { return "Нет данных" }
            let diff = Date().timeIntervalSince(date)
            if diff < 60    { return "Только что" }
            if diff < 3600  { return "\(Int(diff / 3600)) ч назад" }
            return "\(Int(diff / 86400)) д назад"
        }
        return statsByStock.values.first(where: { $0.name == stockName })?.syncTimeText ?? "Нет данных"
    }

    /// Данные для графика: загрузки по дням/неделям для выбранного стока и периода
    func chartData(for stockName: String, period: String) -> [EarningPoint] {
        let history = StatsManager.loadHistorySync()
        let calendar = Calendar.current
        let now = Date()

        let days: Int
        switch period {
        case "7D":  days = 7
        case "90D": days = 90
        default:    days = 30
        }

        let pointCount = period == "90D" ? 3 : (period == "7D" ? 7 : 5)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        switch period {
        case "90D": formatter.dateFormat = "MMM"
        default:    formatter.dateFormat = "dd MMM"
        }

        // Строим метки временных точек
        var datePoints: [(label: String, date: Date)] = []
        for i in stride(from: pointCount - 1, through: 0, by: -1) {
            let offset = period == "90D" ? i * 30 : i * max(1, days / pointCount)
            if let date = calendar.date(byAdding: .day, value: -offset, to: now) {
                let label = formatter.string(from: date).uppercased()
                datePoints.append((label: label, date: date))
            }
        }

        var countByLabel: [String: Double] = Dictionary(
            uniqueKeysWithValues: datePoints.map { ($0.label, 0.0) }
        )

        for record in history {
            guard record.isSuccess else { continue }
            let daysAgo = calendar.dateComponents([.day], from: record.date, to: now).day ?? Int.max
            guard daysAgo <= days else { continue }
            if stockName != "Все стоки" {
                guard record.platformName == stockName else { continue }
            }
            // Находим ближайшую точку графика
            let recordLabel = formatter.string(from: record.date).uppercased()
            if countByLabel[recordLabel] != nil {
                countByLabel[recordLabel]! += 1
            } else {
                // Ищем ближайшую доступную метку
                for point in datePoints.reversed() {
                    if record.date >= point.date {
                        countByLabel[point.label] = (countByLabel[point.label] ?? 0) + 1
                        break
                    }
                }
            }
        }

        return datePoints.map { point in
            EarningPoint(date: point.label, value: countByLabel[point.label] ?? 0)
        }
    }

    // MARK: - Приватные хелперы (nonisolated — работают без MainActor)

    /// Список настроенных стоков из UserDefaults
    nonisolated static func getConnectedPlatforms() -> [StockPlatform] {
        guard let data = UserDefaults.standard.data(forKey: "stock_platforms"),
              let platforms = try? JSONDecoder().decode([StockPlatform].self, from: data) else {
            return []
        }
        return platforms.filter { $0.isEnabled && !$0.username.isEmpty }
    }

    nonisolated static func loadHistorySync() -> [UploadHistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([UploadHistoryRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    private nonisolated static func saveHistorySync(_ history: [UploadHistoryRecord]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}
