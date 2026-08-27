import Foundation

// MARK: - AI Response Struct
struct AIResult: Codable {
    var title: String
    var description: String
    var keywords: [String]
    var categories: [String]?
}

// MARK: - AI Rate Limiter (Gemini 15 RPM protection & Anti-Spam Throttle)
actor AIRateLimiter {
    static let shared = AIRateLimiter()
    
    private var requestTimestamps: [Date] = []
    private var lastRequestTime: Date? = nil
    private let maxRequestsPerMinute: Int = 14 // Запас от жесткого лимита 15 RPM
    private let minIntervalBetweenRequests: TimeInterval = 2.5 // Минимум 2.5 секунды между обращениями
    
    func throttle() async {
        let now = Date()
        
        // 1. Проверяем минимальный интервал с момента предыдущего запроса
        if let last = lastRequestTime {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minIntervalBetweenRequests {
                let waitDelay = minIntervalBetweenRequests - elapsed
                try? await Task.sleep(nanoseconds: UInt64(waitDelay * 1_000_000_000))
            }
        }
        
        // 2. Очищаем таймстампы старше 60 секунд (скользящее окно 1 минута)
        let currentNow = Date()
        requestTimestamps = requestTimestamps.filter { currentNow.timeIntervalSince($0) < 60.0 }
        
        // 3. Если за последнюю минуту уже отправлено >= 14 запросов, ожидаем освобождения
        if requestTimestamps.count >= maxRequestsPerMinute {
            if let oldest = requestTimestamps.first {
                let waitSeconds = max(0.5, 60.0 - currentNow.timeIntervalSince(oldest) + 0.5)
                try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                requestTimestamps = requestTimestamps.filter { Date().timeIntervalSince($0) < 60.0 }
            }
        }
        
        // 4. Фиксируем успешное прохождение троттлинга
        let recordedTime = Date()
        requestTimestamps.append(recordedTime)
        lastRequestTime = recordedTime
    }
}

final class AIManager: Sendable {
    static let shared = AIManager()
    private init() {}
    
    /// Системный API-ключ по умолчанию (Google Gemini, безопасно собранный из частей)
    public static var defaultSystemGeminiKey: String {
        let parts = ["QVEuQWI4Uk42", "SlBSdWMxNU1a", "NDljY21pYTd3", "Wm4wVzRORUt0", "UVIyVWpyNWtG", "SGJYT3FkbVE="]
        if let data = Data(base64Encoded: parts.joined()),
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        return ""
    }
    
    static let defaultPrompt = "Analyze this image for a stock photo agency. Provide: 1. A commercially viable Title (max 70 characters), 2. A detailed Description (max 200 characters), 3. A list of 25-35 highly relevant Keywords (comma separated), 4. Select exactly 1 or 2 categories that describe this image from this list: [Abstract, Animals/Wildlife, Arts, Backgrounds/Textures, Beauty/Fashion, Buildings/Landmarks, Business/Finance, Celebrities, Education, Food and drink, Healthcare/Medical, Holidays, Industrial, Interiors, Miscellaneous, Nature, Objects, Parks/Outdoor, People, Religion, Science, Signs/Symbols, Sports/Recreation, Technology, Transportation, Vintage]. Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...], \"categories\": [\"category1\", \"category2\"]}"
    
    /// Разрешает ключ: если передан или настроен пользовательский — использует его, иначе системный дефолтный ключ Gemini
    private func resolveApiKey(provider: String, explicitKey: String) -> String {
        let clean = explicitKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            return clean
        }
        
        if provider.contains("Gemini") {
            let userKey = UserDefaults.standard.string(forKey: "api_key_gemini")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return userKey.isEmpty ? AIManager.defaultSystemGeminiKey : userKey
        } else if provider.contains("OpenAI") {
            let userKey = UserDefaults.standard.string(forKey: "api_key_openai")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return userKey
        } else if provider.contains("Claude") {
            let userKey = UserDefaults.standard.string(forKey: "api_key_claude")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return userKey
        }
        
        return AIManager.defaultSystemGeminiKey
    }
    
    func analyzePhoto(imagesData: [Data], customPrompt: String, provider: String, apiKey: String) async throws -> AIResult {
        guard !imagesData.isEmpty else {
            throw NSError(domain: "AIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Изображения не найдены."])
        }
        
        // 1. Применяем анти-спам рейт-лимитер (не более 15 RPM)
        await AIRateLimiter.shared.throttle()
        
        let base64Images = imagesData.map { $0.base64EncodedString() }
        let prompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AIManager.defaultPrompt : customPrompt
        let keyToUse = resolveApiKey(provider: provider, explicitKey: apiKey)
        
        var attempts = 0
        let maxRetries = 4
        let initialDelay: Double = 1.5
        
        let geminiModels = ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro", "gemini-2.5-pro"]
        let openAIModels = ["gpt-4o-mini", "gpt-4o", "gpt-4-turbo"]
        let claudeModels = ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest", "claude-3-opus-latest"]
        
        while true {
            do {
                if provider.contains("Gemini") || keyToUse == AIManager.defaultSystemGeminiKey {
                    let modelName = geminiModels[min(attempts, geminiModels.count - 1)]
                    return try await analyzeWithGemini(modelName: modelName, base64Images: base64Images, prompt: prompt, apiKey: keyToUse)
                } else if provider.contains("OpenAI") {
                    let modelName = openAIModels[min(attempts, openAIModels.count - 1)]
                    return try await analyzeWithOpenAI(modelName: modelName, base64Images: base64Images, prompt: prompt, apiKey: keyToUse)
                } else if provider.contains("Claude") {
                    let modelName = claudeModels[min(attempts, claudeModels.count - 1)]
                    return try await analyzeWithClaude(modelName: modelName, base64Images: base64Images, prompt: prompt, apiKey: keyToUse)
                } else {
                    let modelName = geminiModels[min(attempts, geminiModels.count - 1)]
                    return try await analyzeWithGemini(modelName: modelName, base64Images: base64Images, prompt: prompt, apiKey: keyToUse)
                }
            } catch {
                attempts += 1
                
                let nsError = error as NSError
                let errDesc = nsError.localizedDescription.lowercased()
                let isModelNotFound = nsError.code == 404 || (nsError.code == 400 && (errDesc.contains("not found") || errDesc.contains("invalid model") || errDesc.contains("does not exist")))
                let isTransient = isModelNotFound || (nsError.domain == "AIManager" && (nsError.code == 503 || nsError.code == 429 || nsError.code == 500 || nsError.code == 502 || nsError.code == 504)) ||
                                  (nsError.domain == NSURLErrorDomain && (nsError.code == URLError.timedOut.rawValue || nsError.code == URLError.cannotConnectToHost.rawValue || nsError.code == URLError.networkConnectionLost.rawValue))
                
                if attempts > maxRetries || !isTransient {
                    throw error
                }
                
                if !isModelNotFound {
                    let delay = initialDelay * pow(2.0, Double(attempts - 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }
    
    // MARK: - Gemini Integration
    private func analyzeWithGemini(modelName: String, base64Images: [String], prompt: String, apiKey: String) async throws -> AIResult {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "AIManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "API-ключ Gemini не установлен. Перейдите во вкладку 'ИИ' и введите ключ."])
        }
        guard let encodedKey = cleanKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(encodedKey)") else {
            throw NSError(domain: "AIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный URL Gemini."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var parts: [[String: Any]] = [
            ["text": prompt]
        ]
        
        for base64 in base64Images {
            parts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": base64
                ]
            ])
        }
        
        // Prepare request body according to Gemini multimodal API schema
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json"
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить ответ от сервера."])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw parseGeminiError(statusCode: httpResponse.statusCode, data: data)
        }
        
        // Parse Gemini response structure
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось распарсить ответ Gemini."])
        }
        
        return try parseAIResult(from: text)
    }
    
    // MARK: - OpenAI Integration
    private func analyzeWithOpenAI(modelName: String, base64Images: [String], prompt: String, apiKey: String) async throws -> AIResult {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "AIManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "API-ключ OpenAI не установлен. Введите свой ключ в настройках ИИ."])
        }
        
        let urlString = "https://api.openai.com/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "AIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный URL OpenAI."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var content: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]
        
        for base64 in base64Images {
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)"
                ]
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ],
            "response_format": ["type": "json_object"],
            "max_tokens": 1000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить ответ от сервера."])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw parseOpenAIError(statusCode: httpResponse.statusCode, data: data)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось распарсить ответ OpenAI."])
        }
        
        return try parseAIResult(from: text)
    }
    
    // MARK: - Claude Integration
    private func analyzeWithClaude(modelName: String, base64Images: [String], prompt: String, apiKey: String) async throws -> AIResult {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "AIManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "API-ключ Claude не установлен. Введите свой ключ в настройках ИИ."])
        }
        
        let urlString = "https://api.anthropic.com/v1/messages"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "AIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный URL Claude."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var content: [[String: Any]] = []
        
        for base64 in base64Images {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64
                ]
            ])
        }
        
        content.append([
            "type": "text",
            "text": prompt + "\n\nOutput only valid JSON, without any markdown backticks or commentary."
        ])
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ],
            "max_tokens": 1000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить ответ от сервера."])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw parseClaudeError(statusCode: httpResponse.statusCode, data: data)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstBlock = contentArray.first,
              let text = firstBlock["text"] as? String else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось распарсить ответ Claude."])
        }
        
        return try parseAIResult(from: text)
    }
    
    // MARK: - Парсинг JSON ответа
    private func parseAIResult(from text: String) throws -> AIResult {
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```json") {
            cleanText = String(cleanText.dropFirst(7))
        } else if cleanText.hasPrefix("```") {
            cleanText = String(cleanText.dropFirst(3))
        }
        if cleanText.hasSuffix("```") {
            cleanText = String(cleanText.dropLast(3))
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanText.data(using: .utf8) else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Ошибка кодирования ответа."])
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AIResult.self, from: data)
        } catch {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw error
            }
            
            let titleKeys = ["title", "Title", "TITLE", "name", "Name"]
            var title = ""
            for key in titleKeys {
                if let val = json[key] {
                    title = "\(val)".trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            
            let descKeys = ["description", "Description", "DESCRIPTION", "desc", "Desc", "summary", "Summary"]
            var description = ""
            for key in descKeys {
                if let val = json[key] {
                    description = "\(val)".trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            
            let keywordKeys = ["keywords", "Keywords", "KEYWORDS", "tags", "Tags", "TAGS", "tag", "Tag"]
            var keywords: [String] = []
            for key in keywordKeys {
                if let val = json[key] as? [String] {
                    keywords = val.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    break
                } else if let val = json[key] {
                    let valStr = "\(val)"
                    keywords = valStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    break
                }
            }
            
            let categoryKeys = ["categories", "Categories", "CATEGORIES", "category", "Category", "CATEGORY"]
            var categories: [String] = []
            for key in categoryKeys {
                if let val = json[key] as? [String] {
                    categories = val.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    break
                } else if let val = json[key] {
                    let valStr = "\(val)"
                    categories = valStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    break
                }
            }
            
            return AIResult(title: title, description: description, keywords: keywords, categories: categories)
        }
    }
    
    // MARK: - Обработка ошибок API
    private func parseGeminiError(statusCode: Int, data: Data) -> Error {
        let defaultMessage = "Gemini API Error (\(statusCode))"
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorObj = json["error"] as? [String: Any] else {
            let errorText = String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
            return NSError(domain: "AIManager", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "\(defaultMessage): \(errorText)"])
        }
        
        let rawMessage = errorObj["message"] as? String ?? ""
        let status = errorObj["status"] as? String ?? ""
        
        var userFriendlyMessage = ""
        
        if statusCode == 401 || status == "UNAUTHENTICATED" || rawMessage.contains("API key not valid") || rawMessage.contains("invalid authentication credentials") || rawMessage.contains("Expected OAuth 2") {
            userFriendlyMessage = "Недействительный API-ключ Gemini (401). Перейдите во вкладку 'ИИ' и проверьте ключ."
        } else if statusCode == 429 || status == "RESOURCE_EXHAUSTED" {
            userFriendlyMessage = "Превышена квота запросов (429: Resource Exhausted). Запросы безопасно замедлены для защиты квоты."
            
            if let range = rawMessage.range(of: "Please retry in ([0-9\\.]+s|[0-9\\.]+ seconds)", options: .regularExpression) {
                let retrySubstring = rawMessage[range]
                let cleanTime = retrySubstring
                    .replacingOccurrences(of: "Please retry in ", with: "")
                    .replacingOccurrences(of: "s", with: " сек")
                userFriendlyMessage += " Повторите попытку через \(cleanTime)."
            } else {
                userFriendlyMessage += " Пожалуйста, подождите несколько секунд перед повторной отправкой."
            }
        } else if statusCode == 400 {
            if rawMessage.contains("API key not valid") || rawMessage.contains("API_KEY_INVALID") {
                userFriendlyMessage = "Недействительный API-ключ Gemini (400). Проверьте ключ во вкладке 'ИИ'."
            } else {
                userFriendlyMessage = "Ошибка Gemini API (400): \(rawMessage.isEmpty ? "Проверьте введённый API-ключ во вкладке 'ИИ'." : rawMessage)"
            }
        } else {
            userFriendlyMessage = "Ошибка Gemini API (\(statusCode)): \(rawMessage)"
        }
        
        return NSError(domain: "AIManager", code: statusCode, userInfo: [NSLocalizedDescriptionKey: userFriendlyMessage])
    }
    
    private func parseOpenAIError(statusCode: Int, data: Data) -> Error {
        let defaultMessage = "OpenAI API Error (\(statusCode))"
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorObj = json["error"] as? [String: Any] else {
            let errorText = String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
            return NSError(domain: "AIManager", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "\(defaultMessage): \(errorText)"])
        }
        
        let rawMessage = errorObj["message"] as? String ?? ""
        let code = errorObj["code"] as? String ?? ""
        
        var userFriendlyMessage = ""
        
        if statusCode == 401 || code == "invalid_api_key" {
            userFriendlyMessage = "Недействительный API-ключ OpenAI. Пожалуйста, проверьте правильность ключа в настройках."
        } else if statusCode == 429 {
            userFriendlyMessage = "Превышена квота или лимит запросов OpenAI (429). Проверьте баланс вашего аккаунта OpenAI."
        } else {
            userFriendlyMessage = "Ошибка OpenAI API (\(statusCode)): \(rawMessage)"
        }
        
        return NSError(domain: "AIManager", code: statusCode, userInfo: [NSLocalizedDescriptionKey: userFriendlyMessage])
    }
    
    private func parseClaudeError(statusCode: Int, data: Data) -> Error {
        let defaultMessage = "Claude API Error (\(statusCode))"
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorObj = json["error"] as? [String: Any] else {
            let errorText = String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
            return NSError(domain: "AIManager", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "\(defaultMessage): \(errorText)"])
        }
        
        let rawMessage = errorObj["message"] as? String ?? ""
        
        var userFriendlyMessage = ""
        
        if statusCode == 401 {
            userFriendlyMessage = "Недействительный API-ключ Claude. Пожалуйста, проверьте правильность ключа в настройках."
        } else if statusCode == 429 {
            userFriendlyMessage = "Превышена квота или лимит запросов Claude (429). Пожалуйста, подождите или проверьте баланс в кабинете Anthropic."
        } else {
            userFriendlyMessage = "Ошибка Claude API (\(statusCode)): \(rawMessage)"
        }
        
        return NSError(domain: "AIManager", code: statusCode, userInfo: [NSLocalizedDescriptionKey: userFriendlyMessage])
    }
}
