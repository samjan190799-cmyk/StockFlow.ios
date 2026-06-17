import Foundation

// MARK: - AI Response Struct
struct AIResult: Codable {
    var title: String
    var description: String
    var keywords: [String]
}

final class AIManager: Sendable {
    static let shared = AIManager()
    private init() {}
    
    func analyzePhoto(imageData: Data, customPrompt: String, provider: String, apiKey: String) async throws -> AIResult {
        guard !imageData.isEmpty else {
            throw NSError(domain: "AIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Изображение не найдено."])
        }
        
        let base64Image = imageData.base64EncodedString()
        
        if provider.contains("Gemini") {
            return try await analyzeWithGemini(base64Image: base64Image, prompt: customPrompt, apiKey: apiKey)
        } else if provider.contains("OpenAI") {
            return try await analyzeWithOpenAI(base64Image: base64Image, prompt: customPrompt, apiKey: apiKey)
        } else {
            throw NSError(domain: "AIManager", code: 501, userInfo: [NSLocalizedDescriptionKey: "Провайдер \(provider) пока не поддерживается."])
        }
    }
    
    // MARK: - Gemini Integration
    private func analyzeWithGemini(base64Image: String, prompt: String, apiKey: String) async throws -> AIResult {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "AIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный URL Gemini."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare request body according to Gemini multimodal API schema
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inlineData": [
                                "mimeType": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
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
            let errorText = String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
            throw NSError(domain: "AIManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini API Error (\(httpResponse.statusCode)): \(errorText)"])
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
    private func analyzeWithOpenAI(base64Image: String, prompt: String, apiKey: String) async throws -> AIResult {
        let urlString = "https://api.openai.com/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "AIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный URL OpenAI."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Prepare request body for GPT-4o-mini multimodal request
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
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
            let errorText = String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
            throw NSError(domain: "AIManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI API Error (\(httpResponse.statusCode)): \(errorText)"])
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
            
            return AIResult(title: title, description: description, keywords: keywords)
        }
    }
}
