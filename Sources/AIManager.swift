import Foundation

// MARK: - AI Response Struct
struct AIResult: Codable {
    var title: String
    var description: String
    var keywords: [String]
    var categories: [String]?
}

final class AIManager: Sendable {
    static let shared = AIManager()
    private init() {}
    
    static let defaultPrompt = "Analyze this image for a stock photo agency. Provide: 1. A commercially viable Title (max 70 characters), 2. A detailed Description (max 200 characters), 3. A list of 25-35 highly relevant Keywords (comma separated), 4. Select exactly 1 or 2 categories that describe this image from this list: [Abstract, Animals/Wildlife, Arts, Backgrounds/Textures, Beauty/Fashion, Buildings/Landmarks, Business/Finance, Celebrities, Education, Food and drink, Healthcare/Medical, Holidays, Industrial, Interiors, Miscellaneous, Nature, Objects, Parks/Outdoor, People, Religion, Science, Signs/Symbols, Sports/Recreation, Technology, Transportation, Vintage]. Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...], \"categories\": [\"category1\", \"category2\"]}"
    
    func analyzePhoto(imagesData: [Data], customPrompt: String, provider: String, apiKey: String) async throws -> AIResult {
        guard !imagesData.isEmpty else {
            throw NSError(domain: "AIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Изображения не найдены."])
        }
        
        let base64Images = imagesData.map { $0.base64EncodedString() }
        let prompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AIManager.defaultPrompt : customPrompt
        
        var attempts = 0
        let maxRetries = 5
        let initialDelay: Double = 1.0
        
        let geminiModels = ["gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.5-flash", "gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash"]
        let openAIModels = ["gpt-5.5", "gpt-5", "gpt-4o-mini", "gpt-4o"]
        let claudeModels = ["claude-sonnet-5", "claude-3-7-sonnet-latest", "claude-3-5-sonnet-latest", "claude-3-5-haiku-latest"]
        
        while true {
            do {
                if provider.contains("Gemini") {
                    let modelName = geminiModels[min(attempts, geminiModels.count - 1)]
                    return try await analyzeWithGemini(modelName: modelName, base64Images: base64Images, prompt: prompt, apiKey: apiKey)
                } else if provider.contains("OpenAI") {
                    let modelName = openAIModels[min(attempts, openAIModels.count - 1)]
                    return try await analyzeWithOpenAI(modelName: modelName, base64Images: base64Images, prompt: prompt, apiKey: apiKey)
                } else if provider.contains("Claude") {
                    let modelName = claudeModels[min(attempts, claudeModels.count - 1)]
                    return try await analyzeWithClaude(modelName: modelName, base64Images: base64Images, prompt: prompt, apiKey: apiKey)
                } else {
                    throw NSError(domain: "AIManager", code: 501, userInfo: [NSLocalizedDescriptionKey: "Провайдер \(provider) пока не поддерживается."])
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
        
        // Prepare request body for GPT-4o-mini/GPT-4o multimodal request
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ],
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить ответ от сервера."])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw parseOpenAIError(statusCode: httpResponse.statusCode, data: data)
        }
        
        // Parse OpenAI response structure
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось распарсить ответ OpenAI."])
        }
        
        return try parseAIResult(from: content)
    }
    
    // MARK: - Claude Integration
    private func analyzeWithClaude(modelName: String, base64Images: [String], prompt: String, apiKey: String) async throws -> AIResult {
        let urlString = "https://api.anthropic.com/v1/messages"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "AIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный URL Claude."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var contentBlocks: [[String: Any]] = []
        for base64 in base64Images {
            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64
                ]
            ])
        }
        
        contentBlocks.append([
            "type": "text",
            "text": prompt
        ])
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": contentBlocks
                ]
            ]
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
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось распарсить ответ Claude."])
        }
        
        return try parseAIResult(from: text)
    }
    
    // MARK: - Robust JSON Parser Helper
    private func parseAIResult(from text: String) throws -> AIResult {
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extract substring between the first '{' and the last '}' to strip any surrounding conversational text or markdown formatting
        if let firstBrace = cleanText.firstIndex(of: "{"),
           let lastBrace = cleanText.lastIndex(of: "}") {
            cleanText = String(cleanText[firstBrace...lastBrace])
        } else {
            // Remove markdown block wraps if present (legacy fallback)
            if cleanText.hasPrefix("```json") {
                cleanText = String(cleanText.dropFirst("```json".count))
            } else if cleanText.hasPrefix("```") {
                cleanText = String(cleanText.dropFirst("```".count))
            }
            
            if cleanText.hasSuffix("```") {
                cleanText = String(cleanText.dropLast("```".count))
            }
            
            cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let textData = cleanText.data(using: .utf8) else {
            throw NSError(domain: "AIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Ошибка кодирования ответа."])
        }
        
        // 1. Try direct decoding first
        do {
            return try JSONDecoder().decode(AIResult.self, from: textData)
        } catch {
            // 2. If it fails, parse manually via JSONSerialization to extract case-insensitive or partial keys
            guard let json = try? JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
                throw error
            }
            
            // Look for title
            let titleKeys = ["title", "Title", "TITLE", "name", "Name", "header", "Header"]
            var title = ""
            for key in titleKeys {
                if let val = json[key] {
                    title = "\(val)".trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            
            // Look for description
            let descKeys = ["description", "Description", "DESCRIPTION", "desc", "Desc", "summary", "Summary"]
            var description = ""
            for key in descKeys {
                if let val = json[key] {
                    description = "\(val)".trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            
            // Look for keywords
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
            
            // Look for categories
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
            userFriendlyMessage = "Недействительный API-ключ Gemini (401). Перейдите во вкладку 'ИИ' и введите корректный ключ Google AI Studio."
        } else if statusCode == 429 || status == "RESOURCE_EXHAUSTED" {
            userFriendlyMessage = "Превышена квота запросов (429: Resource Exhausted). Вы исчерпали лимит бесплатных запросов к Gemini API."
            
            if let range = rawMessage.range(of: "Please retry in ([0-9\\.]+s|[0-9\\.]+ seconds)", options: .regularExpression) {
                let retrySubstring = rawMessage[range]
                let cleanTime = retrySubstring
                    .replacingOccurrences(of: "Please retry in ", with: "")
                    .replacingOccurrences(of: "s", with: " сек")
                userFriendlyMessage += " Повторите попытку через \(cleanTime)."
            } else {
                userFriendlyMessage += " Пожалуйста, подождите перед повторной отправкой."
            }
        } else if statusCode == 400 {
            if rawMessage.contains("API key not valid") || rawMessage.contains("API_KEY_INVALID") {
                userFriendlyMessage = "Недействительный API-ключ Gemini (400). Перейдите во вкладку 'ИИ' и введите корректный ключ Google AI Studio."
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
