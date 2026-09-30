import Foundation
import SwiftUI
import UIKit

/// Журнал работы приложения (FTP и важные шаги импорта).
/// Строки пишутся на диск сразу, поэтому после внезапного закрытия приложения системой
/// журнал прошлого запуска виден в окне «FTP Логи» вместе с занятой памятью на каждом шаге.
@MainActor
class FTPTranscriptLogger: ObservableObject {
    static let shared = FTPTranscriptLogger()

    @Published var logs: [String] = []

    private let maxLogs = 500
    private let dateFormatter: DateFormatter
    private let fileURL: URL

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("app_journal.log")

        restorePreviousSession()
        appendLog("🚀 [START] Запуск приложения, занято памяти: \(Self.footprintMB()) МБ")

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logError("Система просит освободить память. Занято: \(Self.footprintMB()) МБ")
            }
        }
    }

    func logCommand(_ text: String) {
        let maskedText = maskPasswords(in: text)
        appendLog("➡️ [CMD] \(maskedText.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    func logResponse(_ text: String) {
        appendLog("⬅️ [RES] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    func logInfo(_ text: String) {
        appendLog("ℹ️ [INFO] \(text)")
    }

    func logError(_ text: String) {
        appendLog("❌ [ERROR] \(text)")
    }

    /// Шаг с указанием занятой памяти — по нему видно, на каком файле память выросла
    func logStep(_ text: String) {
        appendLog("🔹 [STEP] \(text) · память \(Self.footprintMB()) МБ")
    }

    /// Уход в фон помечается: если прошлый запуск закончился не этой строкой, приложение закрыла система
    func logLifecycle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            appendLog("🌙 [BG] Приложение ушло в фон, занято памяти: \(Self.footprintMB()) МБ")
        case .active:
            appendLog("☀️ [ACTIVE] Приложение на экране, занято памяти: \(Self.footprintMB()) МБ")
        default:
            break
        }
    }

    func clear() {
        logs.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    func getTranscript() -> String {
        return logs.joined(separator: "\n")
    }

    /// Сколько памяти приложение занимает прямо сейчас (то, по чему система решает, кого закрыть)
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint / 1_048_576)
    }

    // MARK: - Хранение на диске

    private func restorePreviousSession() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return }

        let previous = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !previous.isEmpty else { return }

        let endedCleanly = previous.last?.contains("[BG]") == true
        var restored = Array(previous.suffix(300))
        restored.append("—— выше журнал прошлого запуска ——")
        if !endedCleanly {
            restored.append("⚠️ Прошлый запуск оборвался: приложение не успело уйти в фон. Скорее всего, его закрыла система из-за нехватки памяти (смотрите строки выше).")
        }
        logs = restored

        // Файл оставляем компактным: последние строки прошлого запуска
        let compact = restored.joined(separator: "\n") + "\n"
        try? compact.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }

    private func persist(_ entry: String) {
        guard let data = (entry + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func appendLog(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)"

        // Запись на диск выполняется сразу, чтобы строка пережила внезапное закрытие приложения
        persist(logEntry)

        Task { @MainActor in
            logs.append(logEntry)
            if logs.count > maxLogs {
                logs.removeFirst(logs.count - maxLogs)
            }
            print(logEntry) // Also print to console
        }
    }

    private func maskPasswords(in text: String) -> String {
        let pattern = "(?i)(PASS\\s+).+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(location: 0, length: text.utf16.count)
            return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1********")
        }
        return text
    }
}
