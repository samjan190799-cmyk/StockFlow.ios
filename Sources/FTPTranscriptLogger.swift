import Foundation
import SwiftUI

@MainActor
class FTPTranscriptLogger: ObservableObject {
    static let shared = FTPTranscriptLogger()
    
    @Published var logs: [String] = []
    
    private let maxLogs = 500
    private let dateFormatter: DateFormatter
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
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
    
    func clear() {
        logs.removeAll()
    }
    
    func getTranscript() -> String {
        return logs.joined(separator: "\n")
    }
    
    private func appendLog(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)"
        
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
