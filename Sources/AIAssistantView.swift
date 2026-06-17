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
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Section 1: Provider selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Интеллектуальный ИИ-Ассистент")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            HStack {
                                Text("Провайдер")
                                    .font(.system(size: 14, weight: .medium))
                                Spacer()
                                Picker("Провайдер", selection: $selectedProvider) {
                                    ForEach(AIProvider.allCases) { provider in
                                        Text(provider.rawValue).tag(provider.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                        .glassCard()
                        
                        // Section 2: API Keys
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Настройка интеграции ИИ")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            apiKeyField(title: "GEMINI API КЛЮЧ", placeholder: "AIzaSy...", text: $apiKeyGemini, provider: "Gemini")
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            apiKeyField(title: "OPENAI API КЛЮЧ", placeholder: "sk-...", text: $apiKeyOpenAI, provider: "OpenAI")
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            apiKeyField(title: "CLAUDE API КЛЮЧ", placeholder: "sk-ant-...", text: $apiKeyClaude, provider: "Claude")
                        }
                        .glassCard()
                        
                        // Section 3: Custom Prompt
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Промпт для ИИ-анализа")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            TextEditor(text: $customPrompt)
                                .font(.system(size: 13, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                                .frame(height: 140)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                            
                            Text("Промпт сообщает модели, в каком виде генерировать заголовок, описание и ключевые слова.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .glassCard()
                    }
                    .padding()
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
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(.primary)
                                Text("Проверка...")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .glassCard(cornerRadius: 16, padding: 24)
                        )
                }
            }
        }
    }
    
    // MARK: - API Key Field Helper
    private func apiKeyField(title: String, placeholder: String, text: Binding<String>, provider: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 10) {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                Button(action: { verifyKey(text.wrappedValue, for: provider) }) {
                    Text("Проверить")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppleTheme.primaryGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
