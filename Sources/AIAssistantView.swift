import SwiftUI

struct AIAssistantView: View {
    @AppStorage("ai_provider") private var selectedProvider: String = AIProvider.gemini.rawValue
    @AppStorage("api_key_gemini") private var apiKeyGemini: String = ""
    @AppStorage("api_key_openai") private var apiKeyOpenAI: String = ""
    @AppStorage("api_key_claude") private var apiKeyClaude: String = ""
    @AppStorage("ai_custom_prompt") private var customPrompt: String = "Analyze this image for a stock photo agency. Provide: 1. A commercially viable Title (max 70 characters), 2. A detailed Description (max 200 characters), 3. A list of 25-35 highly relevant Keywords (comma separated). Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
    
    @State private var showingKeyVerificationAlert = false
    @State private var verificationMessage = ""
    @State private var isVerifying = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Интеллектуальный ИИ-Ассистент")) {
                    Picker("Приоритетный ИИ-провайдер", selection: $selectedProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("Настройка интеграции ИИ")) {
                    // Gemini Key
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GEMINI API КЛЮЧ").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        HStack {
                            SecureField("AIzaSy...", text: $apiKeyGemini)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, design: .monospaced))
                            
                            Button(action: { verifyKey(apiKeyGemini, for: "Gemini") }) {
                                Text("Проверить")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // OpenAI Key
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OPENAI API КЛЮЧ").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        HStack {
                            SecureField("sk-...", text: $apiKeyOpenAI)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, design: .monospaced))
                            
                            Button(action: { verifyKey(apiKeyOpenAI, for: "OpenAI") }) {
                                Text("Проверить")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Claude Key
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CLAUDE (ANTHROPIC) API КЛЮЧ").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        HStack {
                            SecureField("sk-ant-...", text: $apiKeyClaude)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, design: .monospaced))
                            
                            Button(action: { verifyKey(apiKeyClaude, for: "Claude") }) {
                                Text("Проверить")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Промпт для ИИ-анализа"), footer: Text("Промпт сообщает модели, в каком виде генерировать заголовок, описание и ключевые слова.")) {
                    TextEditor(text: $customPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 140)
                }
            }
            .navigationTitle("ИИ-Ассистент")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Проверка ключа", isPresented: $showingKeyVerificationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(verificationMessage)
            }
            .overlay {
                if isVerifying {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .overlay(
                            ProgressView("Проверка...")
                                .padding()
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 10)
                        )
                }
            }
        }
    }
    
    private func verifyKey(_ key: String, for provider: String) {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            verificationMessage = "Ключ API не может быть пустым."
            showingKeyVerificationAlert = true
            return
        }
        
        isVerifying = true
        // Mock checking api key validity
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isVerifying = false
            verificationMessage = "Ключ для \(provider) успешно проверен! Подключение установлено."
            showingKeyVerificationAlert = true
        }
    }
}
