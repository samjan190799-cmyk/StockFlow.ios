import SwiftUI

struct PromptTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let text: String
}

struct AIAssistantView: View {
    @AppStorage("ai_provider") private var selectedProvider: String = AIProvider.gemini.rawValue
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @AppStorage("api_key_gemini") private var apiKeyGemini: String = ""
    @AppStorage("api_key_openai") private var apiKeyOpenAI: String = ""
    @AppStorage("api_key_claude") private var apiKeyClaude: String = ""
    @AppStorage("ai_custom_prompt") private var customPrompt: String = "Analyze this image for a stock photo agency. Provide: 1. A commercially viable Title (max 70 characters), 2. A detailed Description (max 200 characters), 3. A list of 25-35 highly relevant Keywords (comma separated). Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
    
    @State private var showingKeyVerificationAlert = false
    @State private var verificationMessage = ""
    @State private var isVerifying = false
    @State private var showHelpSheet = false
    
    // Quick Templates
    private let templates: [PromptTemplate] = [
        PromptTemplate(
            id: "standard",
            name: "Стандартный",
            icon: "star.fill",
            text: "Analyze this image for a stock photo agency. Provide: 1. A commercially viable Title (max 70 characters), 2. A detailed Description (max 200 characters), 3. A list of 25-35 highly relevant Keywords (comma separated). Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
        ),
        PromptTemplate(
            id: "commercial",
            name: "Коммерческий",
            icon: "briefcase.fill",
            text: "Analyze this image for commercial stock photography. Focus on marketability, clean composition, business/lifestyle value, and clear concept. Provide: 1. A highly marketable Title (max 70 characters), 2. A detailed Description highlighting commercial applications (max 200 characters), 3. A list of 25-35 highly relevant commercial keywords (comma separated) like 'concept', 'lifestyle', 'professional'. Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
        ),
        PromptTemplate(
            id: "editorial",
            name: "Репортажный",
            icon: "newspaper.fill",
            text: "Analyze this image as a documentary or editorial/news photo. Focus on authentic storytelling, context, real emotions, and action. Provide: 1. An editorial/documentary Title (max 80 characters), 2. A factual Description explaining who, what, when and where (max 250 characters), 3. A list of 25-35 documentary and context keywords (comma separated) including editorial terms. Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...]}"
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
            .navigationTitle("ИИ-Ассистент".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        HapticHelper.trigger(.light)
                        showHelpSheet = true
                    }) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.purple)
                    }
                }
            }
            .sheet(isPresented: $showHelpSheet) {
                AIKeyHelpSheet()
            }
            .alert("Проверка ключа".localized, isPresented: $showingKeyVerificationAlert) {
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
                                Text("Проверка подключения к ".localized + "\(activeProviderName)...")
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
                Text("Интеллектуальный Помощник".localized)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Настройте ИИ для мгновенной индексации ваших кадров. Генерация коммерческих названий и SEO-тегов.".localized)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
    }
    
    private var providerCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ИИ провайдеры".localized)
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
                    color: Color(hex: "7C3AED")
                )
                
                providerCard(
                    id: AIProvider.openai.rawValue,
                    name: "GPT-4",
                    company: "OpenAI",
                    iconName: "cpu",
                    color: Color(hex: "10B981")
                )
                
                providerCard(
                    id: AIProvider.claude.rawValue,
                    name: "Claude",
                    company: "Anthropic",
                    iconName: "hourglass",
                    color: Color(hex: "F97316")
                )
            }
        }
    }
    
    @ViewBuilder
    private func providerCard(id: String, name: String, company: String, iconName: String, color: Color) -> some View {
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
                        .fill(isSelected ? color : color.opacity(0.12))
                        .frame(width: 46, height: 46)
                    
                    if #available(iOS 17.0, *) {
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isSelected ? .white : color)
                            .symbolEffect(.bounce, value: selectedProvider)
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isSelected ? .white : color)
                    }
                }
                
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
            .background(isSelected ? color.opacity(0.12) : Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? color : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2.0 : 1.0
                    )
            )
            .scaleEffect(isSelected ? 1.03 : 0.97)
        }
        .buttonStyle(PremiumButtonStyle())
    }
    
    private var apiKeyConfigSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Параметры подключения".localized)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                let hasKey = !activeKey.wrappedValue.isEmpty
                let isGemini = selectedProvider.contains("Gemini")
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeProviderName)
                            .font(.system(size: 15, weight: .bold))
                        Text(hasKey ? "Используется ваш личный API-ключ (Безлимит)".localized : (isGemini ? "Активен встроенный SmartStock ИИ".localized : "Введите личный токен аутентификации API".localized))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    // Status Badge (Glassmorphic)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(hasKey ? Color.green : (isGemini ? Color.purple : Color.orange))
                            .frame(width: 5, height: 5)
                        
                        Text((hasKey ? "Личный ключ" : (isGemini ? "Встроенный" : "Не настроен")).localized)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(hasKey ? Color.green : (isGemini ? Color.purple : Color.orange))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(hasKey ? Color.green.opacity(0.12) : (isGemini ? Color.purple.opacity(0.12) : Color.orange.opacity(0.12)))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(hasKey ? Color.green.opacity(0.3) : (isGemini ? Color.purple.opacity(0.3) : Color.orange.opacity(0.3)), lineWidth: 1)
                    )
                }
                
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        // Dynamic padlock state icon
                        Image(systemName: hasKey ? "lock.fill" : (isGemini ? "sparkles" : "lock.open.fill"))
                            .font(.system(size: 14))
                            .foregroundStyle(hasKey ? .green : (isGemini ? .purple : .orange))
                            .animation(.default, value: hasKey)
                        
                        SecureField(isGemini ? "Встроенный ключ (или вставьте свой)...".localized : "Вставьте ключ API...".localized, text: activeKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1.2)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    
                    Button(action: {
                        HapticHelper.trigger(.medium)
                        let keyToVerify = activeKey.wrappedValue.isEmpty && isGemini ? AIManager.defaultSystemGeminiKey : activeKey.wrappedValue
                        verifyKey(keyToVerify, for: activeProviderName)
                    }) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(AppleTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PremiumButtonStyle())
                }
                
                Text("💡 По умолчанию активен встроенный Gemini ИИ (до 15 запросов в день). Для полного безлимита без подписки вы можете вставить свой личный ключ от Google AI Studio, OpenAI или Claude.".localized)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .glassCard(cornerRadius: 20, padding: 14)
        }
    }
    
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Промпт для ИИ-анализа".localized)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
            
            // Templates scroll (Glass Tag Ribbon)
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
                                    .font(.system(size: 11))
                                Text(template.name.localized)
                                    .font(.system(size: 11, weight: .black))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? AppleTheme.primaryGradient : LinearGradient(colors: [Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                            .foregroundStyle(isSelected ? .white : .primary.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.15), lineWidth: 1.2)
                            )
                        }
                        .buttonStyle(PremiumButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
            
            // TextEditor Card (Glass container)
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $customPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 140)
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1.2)
                    )
                
                Text("Промпт определяет формат возвращаемого JSON-файла с заголовком и ключевыми словами.".localized)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            .glassCard(cornerRadius: 20, padding: 14)
        }
    }
    
    // MARK: - Operations
    
    private func verifyKey(_ key: String, for provider: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            verificationMessage = "Пожалуйста, введите API-ключ перед проверкой."
            showingKeyVerificationAlert = true
            return
        }
        
        isVerifying = true
        
        // 1x1 minimal JPEG image data for light API validation call
        let testJPEGData = Data([
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
            0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
            0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
            0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20,
            0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29, 0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27,
            0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
            0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01,
            0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
            0x00, 0xBE, 0x00, 0xFF, 0xD9
        ])
        
        Task {
            do {
                _ = try await AIManager.shared.analyzePhoto(
                    imagesData: [testJPEGData],
                    customPrompt: "Respond strictly with JSON: {\"title\": \"test\", \"description\": \"test\", \"keywords\": [\"test\"]}",
                    provider: provider,
                    apiKey: cleanKey
                )
                await MainActor.run {
                    self.isVerifying = false
                    self.verificationMessage = "Успешно! API-ключ \(provider) верен и готов к работе."
                    self.showingKeyVerificationAlert = true
                }
            } catch {
                await MainActor.run {
                    self.isVerifying = false
                    self.verificationMessage = "Ошибка проверки: \(error.localizedDescription)"
                    self.showingKeyVerificationAlert = true
                }
            }
        }
    }
}
