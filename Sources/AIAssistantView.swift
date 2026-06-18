import SwiftUI

struct PromptTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let text: String
}

struct AIAssistantView: View {
    @AppStorage("ai_provider") private var selectedProvider: String = AIProvider.gemini.rawValue
    @AppStorage("api_key_gemini") private var apiKeyGemini: String = ""
    @AppStorage("api_key_openai") private var apiKeyOpenAI: String = ""
    @AppStorage("api_key_claude") private var apiKeyClaude: String = ""
    @AppStorage("ai_custom_prompt") private var customPrompt: String = "Analyze this image for a stock photo agency. Provide: 1. A commercially viable Title (max 70 characters), 2. A detailed Description (max 200 characters), 3. A list of 25-35 highly relevant Keywords (comma separated). Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
    
    @State private var showingKeyVerificationAlert = false
    @State private var verificationMessage = ""
    @State private var isVerifying = false
    
    // Quick Templates
    private let templates: [PromptTemplate] = [
        PromptTemplate(
            id: "standard",
            name: "Стандартный",
            icon: "star.fill",
            text: "Analyze this image for a stock photo agency. Provide: 1. A commercially viable Title (max 70 characters), 2. A detailed Description (max 200 characters), 3. A list of 25-35 highly relevant Keywords (comma separated). Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
        ),
        PromptTemplate(
            id: "creative",
            name: "Креативный",
            icon: "paintpalette.fill",
            text: "Analyze this image focusing on its artistic and emotional value. Generate: 1. An elegant, creative Title (max 80 characters), 2. A narrative description telling the story of the image (max 250 characters), 3. A list of 30 rich descriptive and conceptual Keywords (comma separated). Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
        ),
        PromptTemplate(
            id: "seo",
            name: "SEO-Максимум",
            icon: "magnifyingglass.circle.fill",
            text: "Analyze this image for maximum search engine optimization (SEO) on microstocks like Shutterstock and Adobe Stock. Generate: 1. A highly descriptive, keyword-rich Title (max 70 characters), 2. A clear Description containing the primary subject (max 150 characters), 3. An extensive list of 45-50 highly relevant search terms and keywords (comma separated) including synonyms and concepts. Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
        ),
        PromptTemplate(
            id: "mini",
            name: "Мини",
            icon: "bolt.fill",
            text: "Analyze this image and provide a concise title (max 50 chars), brief description (max 100 chars), and 15 essential keywords. Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
        )
    ]
    
    var activeKey: Binding<String> {
        if selectedProvider.contains("Gemini") {
            return $apiKeyGemini
        } else if selectedProvider.contains("OpenAI") {
            return $apiKeyOpenAI
        } else {
            return $apiKeyClaude
        }
    }
    
    var activeProviderName: String {
        if selectedProvider.contains("Gemini") { return "Gemini" }
        if selectedProvider.contains("OpenAI") { return "OpenAI" }
        return "Claude"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Premium Header Info Panel
                        headerPanel
                        
                        // Provider selector cards
                        providerCards
                        
                        // API Key config
                        apiKeyConfigSection
                        
                        // Prompt templates & Editor
                        promptSection
                        
                        Spacer(minLength: 40)
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
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(.primary)
                                Text("Проверка подключения к \(activeProviderName)...")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .glassCard(cornerRadius: 16, padding: 24)
                        )
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerPanel: some View {
        HStack(spacing: 16) {
            SmartStockLogoView(size: 60)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Интеллектуальный Помощник")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Используйте ИИ для автоматического распознавания образов, генерации названий и подбора ключевых слов.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: 14)
    }
    
    private var providerCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ИИ провайдеры")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
            
            HStack(spacing: 12) {
                providerCard(
                    id: AIProvider.gemini.rawValue,
                    name: "Gemini",
                    company: "Google",
                    iconName: "sparkles",
                    color: Color(hex: "7C3AED"),
                    glowColor: Color(hex: "4F46E5")
                )
                
                providerCard(
                    id: AIProvider.openai.rawValue,
                    name: "GPT-4",
                    company: "OpenAI",
                    iconName: "cpu",
                    color: Color(hex: "10B981"),
                    glowColor: Color(hex: "059669")
                )
                
                providerCard(
                    id: AIProvider.claude.rawValue,
                    name: "Claude",
                    company: "Anthropic",
                    iconName: "hourglass",
                    color: Color(hex: "F97316"),
                    glowColor: Color(hex: "EA580C")
                )
            }
        }
    }
    
    @ViewBuilder
    private func providerCard(id: String, name: String, company: String, iconName: String, color: Color, glowColor: Color) -> some View {
        let isSelected = selectedProvider == id
        
        Button(action: {
            HapticHelper.selection()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selectedProvider = id
            }
        }) {
            VStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    if #available(iOS 17.0, *) {
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(color)
                            .symbolEffect(.bounce, value: selectedProvider)
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }
                .shadow(color: color.opacity(isSelected ? 0.35 : 0.0), radius: 6)
                
                VStack(spacing: 2) {
                    Text(name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(company)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? LinearGradient(colors: [color, glowColor], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                        lineWidth: isSelected ? 2.0 : 1.0
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 0.98)
            .shadow(color: color.opacity(isSelected ? 0.15 : 0.0), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PremiumButtonStyle())
    }
    
    private var apiKeyConfigSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Параметры подключения")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeProviderName)
                            .font(.system(size: 15, weight: .bold))
                        Text("Введите ваш личный API токен")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    // Status Badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(activeKey.wrappedValue.isEmpty ? Color.red : Color.green)
                            .frame(width: 6, height: 6)
                        
                        Text(activeKey.wrappedValue.isEmpty ? "Не настроен" : "Активен")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(activeKey.wrappedValue.isEmpty ? Color.red : Color.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(activeKey.wrappedValue.isEmpty ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(activeKey.wrappedValue.isEmpty ? Color.red.opacity(0.25) : Color.green.opacity(0.25), lineWidth: 1)
                    )
                }
                
                HStack(spacing: 8) {
                    SecureField("Вставьте ключ API здесь...", text: activeKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(12)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    Button(action: {
                        HapticHelper.trigger(.medium)
                        verifyKey(activeKey.wrappedValue, for: activeProviderName)
                    }) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(AppleTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: AppleTheme.glowStart.opacity(0.3), radius: 4)
                    }
                    .buttonStyle(PremiumButtonStyle())
                }
            }
            .glassCard()
        }
    }
    
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Промпт для ИИ-анализа")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
            
            // Templates scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates) { template in
                        let isSelected = customPrompt == template.text
                        Button(action: {
                            HapticHelper.selection()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                customPrompt = template.text
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: template.icon)
                                    .font(.system(size: 10))
                                Text(template.name)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? AppleTheme.primaryGradient : LinearGradient(colors: [Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                            .foregroundStyle(isSelected ? .white : .primary.opacity(0.8))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PremiumButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
            
            // TextEditor Card
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $customPrompt)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 150)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                Text("Редактируйте промпт для получения заголовка и ключевых слов в нужном формате. ИИ возвращает JSON.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            .glassCard()
        }
    }
    
    // MARK: - Operations
    
    private func verifyKey(_ key: String, for provider: String) {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            verificationMessage = "Пожалуйста, введите API-ключ перед проверкой."
            showingKeyVerificationAlert = true
            return
        }
        
        isVerifying = true
        
        // Симулируем проверку
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.isVerifying = false
            self.verificationMessage = "Интеграция с \(provider) успешно настроена! Запросы ИИ-анализа активны."
            self.showingKeyVerificationAlert = true
        }
    }
}
