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
    let id: UUID
    var filename: String
    var fileSize: String
    var title: String
    var keywords: [String]
    var description: String
    var categories: [String]
    var status: PhotoStatus
    var selectedStocks: Set<String>
    var imageData: Data?
    
    var uploadProgress: Double = 0.0
    var errorMessage: String? = nil
    
    init(
        id: UUID = UUID(),
        filename: String,
        fileSize: String,
        title: String,
        keywords: [String],
        description: String,
        categories: [String] = [],
        status: PhotoStatus = .new,
        selectedStocks: Set<String> = ["Shutterstock", "Adobe Stock"],
        imageData: Data? = nil
    ) {
        self.id = id
        self.filename = filename
        self.fileSize = fileSize
        self.title = title
        self.keywords = keywords
        self.description = description
        self.categories = categories
        self.status = status
        self.selectedStocks = selectedStocks
        self.imageData = imageData
    }
    
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
    var passwordHash: String = ""
    var isEnabled: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, defaultHost, host, username, isEnabled
    }
    
    init(id: String, name: String, defaultHost: String, host: String, username: String, passwordHash: String = "", isEnabled: Bool) {
        self.id = id
        self.name = name
        self.defaultHost = defaultHost
        self.host = host
        self.username = username
        self.passwordHash = passwordHash
        self.isEnabled = isEnabled
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = (try? container.decode(String.self, forKey: .id)) ?? ""
        self.id = decodedId
        
        // Find default platform matching this ID to use as fallback values
        let defaultPlatform = StockPlatform.defaults.first(where: { $0.id == decodedId })
        
        self.name = (try? container.decode(String.self, forKey: .name)) ?? defaultPlatform?.name ?? ""
        let defHost = (try? container.decode(String.self, forKey: .defaultHost)) ?? defaultPlatform?.defaultHost ?? ""
        self.defaultHost = defHost
        
        let loadedHost = (try? container.decode(String.self, forKey: .host)) ?? ""
        self.host = loadedHost.isEmpty ? (defaultPlatform?.host ?? defHost) : loadedHost
        
        self.username = (try? container.decode(String.self, forKey: .username)) ?? ""
        self.passwordHash = ""
        self.isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(defaultHost, forKey: .defaultHost)
        try container.encode(host, forKey: .host)
        try container.encode(username, forKey: .username)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
    
    static var defaults: [StockPlatform] {
        [
            StockPlatform(id: "adobe", name: "Adobe Stock", defaultHost: "sftp.contributor.adobestock.com", host: "sftp.contributor.adobestock.com", username: "", passwordHash: "", isEnabled: false),
            StockPlatform(id: "shutterstock", name: "Shutterstock", defaultHost: "ftp.shutterstock.com", host: "ftp.shutterstock.com", username: "", passwordHash: "", isEnabled: false),
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
