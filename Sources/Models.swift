import Foundation
import SwiftUI
import UIKit

// MARK: - Photo Status
enum PhotoStatus: String, Codable, CaseIterable, Sendable {
    case new = "Новый"
    case aiAnalyzing = "ИИ Анализ"
    case ready = "Готов к отправке"
    case uploading = "Идет загрузка"
    case success = "Загружен"
    case error = "Ошибка"
    
    var color: Color {
        switch self {
        case .new: return .gray
        case .aiAnalyzing: return .orange
        case .ready: return .blue
        case .uploading: return .purple
        case .success: return .green
        case .error: return .red
        }
    }
}

// MARK: - Photo Metadata Model
struct PhotoMetadata: Identifiable, Sendable {
    let id = UUID()
    var filename: String
    var fileSize: String
    var title: String
    var keywords: [String]
    var description: String
    var status: PhotoStatus = .new
    var selectedStocks: Set<String> = ["Shutterstock", "Adobe Stock"]
    var imageData: Data?
    
    var uiImage: UIImage? {
        if let data = imageData {
            return UIImage(data: data)
        }
        return nil
    }
}

// MARK: - AI Provider
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case gemini = "Gemini AI (Рекомендуется, быстрый/экономичный)"
    case openai = "OpenAI API"
    case claude = "Claude (Anthropic)"
    
    var id: String { self.rawValue }
}

// MARK: - Photostock Definition
struct StockPlatform: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let defaultHost: String
    var host: String
    var username: String
    var isEnabled: Bool
    
    // Stored securely in Keychain, not in UserDefaults JSON
    var passwordHash: String = ""
    
    enum CodingKeys: String, CodingKey {
        case id, name, defaultHost, host, username, isEnabled
    }
    
    static var defaults: [StockPlatform] {
        [
            StockPlatform(id: "adobe", name: "Adobe Stock", defaultHost: "sftp.contributor.adobestock.com", host: "sftp.contributor.adobestock.com", username: "", passwordHash: "", isEnabled: false),
            StockPlatform(id: "shutterstock", name: "Shutterstock", defaultHost: "ftps.shutterstock.com", host: "ftps.shutterstock.com", username: "", passwordHash: "", isEnabled: false),
            StockPlatform(id: "istock", name: "iStock / Getty", defaultHost: "ftp.gettyimages.com", host: "ftp.gettyimages.com", username: "", passwordHash: "", isEnabled: false),
            StockPlatform(id: "freepik", name: "Freepik", defaultHost: "sftp.contributor-ftp.freepik.com", host: "sftp.contributor-ftp.freepik.com", username: "", passwordHash: "", isEnabled: false),
            StockPlatform(id: "depositphotos", name: "Depositphotos", defaultHost: "ftp.depositphotos.com", host: "ftp.depositphotos.com", username: "", passwordHash: "", isEnabled: false),
            StockPlatform(id: "alamy", name: "Alamy", defaultHost: "ftp.upload.alamy.com", host: "ftp.upload.alamy.com", username: "", passwordHash: "", isEnabled: false),
            StockPlatform(id: "dreamstime", name: "Dreamstime", defaultHost: "ftp.upload.dreamstime.com", host: "ftp.upload.dreamstime.com", username: "", passwordHash: "", isEnabled: false),
            StockPlatform(id: "123rf", name: "123RF", defaultHost: "ftp.123rf.com", host: "ftp.123rf.com", username: "", passwordHash: "", isEnabled: false),
            StockPlatform(id: "pond5", name: "Pond5", defaultHost: "ftp.pond5.com", host: "ftp.pond5.com", username: "", passwordHash: "", isEnabled: false)
        ]
    }
}
