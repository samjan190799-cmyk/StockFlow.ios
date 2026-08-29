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
    @AppStorage("ai_custom_prompt") private var customPrompt: String = AIManager.defaultPrompt
    
    @ObservedObject private var rewardManager = RewardAdManager.shared
    @ObservedObject private var storeManager = StoreManager.shared
    
    @State private var showResetAlert = false
    @State private var showPaywall = false
    
    // Quick Templates
    private let templates: [PromptTemplate] = [
        PromptTemplate(
            id: "standard",
            name: "Стандартный",
            icon: "star.fill",
            text: "Analyze this image for a stock photo agency. Provide: 1. A commercially viable Title (max 70 characters), 2. A detailed Description (max 200 characters), 3. A list of 25-35 highly relevant Keywords (comma separated), 4. Select exactly 1 or 2 categories that describe this image from this list: [Abstract, Animals/Wildlife, Arts, Backgrounds/Textures, Beauty/Fashion, Buildings/Landmarks, Business/Finance, Celebrities, Education, Food and drink, Healthcare/Medical, Holidays, Industrial, Interiors, Miscellaneous, Nature, Objects, Parks/Outdoor, People, Religion, Science, Signs/Symbols, Sports/Recreation, Technology, Transportation, Vintage]. Output strictly in JSON format matching this schema: {\"title\": \"string\", \"description\": \"string\", \"keywords\": [\"keyword1\", \"keyword2\", ...], \"categories\": [\"category1\", \"category2\"]}"
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        
                        // Header info panel
                        headerPanel
                        
                        // AI Status and Plan Card
                        aiStatusCard
                        
                        // Prompt Templates & Editor
                        promptSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("ИИ-Ассистент".localized)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .alert("Сбросить промпт?".localized, isPresented: $showResetAlert) {
                Button("Отмена", role: .cancel) { }
                Button("Сбросить", role: .destructive) {
                    customPrompt = AIManager.defaultPrompt
                    HapticHelper.notification(.success)
                }
            } message: {
                Text("Промпт будет возвращён к заводскому стандартному шаблону.".localized)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerPanel: some View {
        HStack(spacing: 16) {
            SmartStockLogoView(size: 58)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("SmartStock AI Engine".localized)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Мультимодальный анализ визуальных сцен, генерация коммерческих названий, описаний и SEO-тегов.".localized)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 14)
    }
    
    private var aiStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Нейросетевое ядро".localized)
                        .font(.system(size: 14, weight: .bold))
                    Text("Google Gemini Vision / Pro".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Status Pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "10B981"))
                        .frame(width: 7, height: 7)
                    Text("Активен".localized)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "10B981"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "10B981").opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color(hex: "10B981").opacity(0.35), lineWidth: 1)
                )
            }
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // Limit / Plan status
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Дневной лимит".localized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    if storeManager.isProUser {
                        Text("Безлимитный доступ (PRO)".localized)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "F59E0B"))
                    } else {
                        let baseRemaining = max(0, 15 - rewardManager.dailyAIUsed)
                        let text = rewardManager.bonusCredits > 0 ? "\(baseRemaining)/15 (+\(rewardManager.bonusCredits) бонус)" : "\(rewardManager.remainingAIToday)/15 доступно"
                        Text(text)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
                
                Spacer()
                
                if !storeManager.isProUser {
                    Button(action: {
                        HapticHelper.trigger(.light)
                        showPaywall = true
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 11))
                            Text("Безлимит".localized)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(AppleTheme.primaryGradient)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PremiumButtonStyle())
                }
            }
        }
        .glassCard(cornerRadius: 20, padding: 14)
    }
    
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Стиль индексации".localized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, 4)
                
                Spacer()
                
                Button(action: {
                    HapticHelper.trigger(.light)
                    showResetAlert = true
                }) {
                    Text("Сбросить".localized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "6366F1"))
                }
            }
            
            // Templates scroll (Liquid Glass Tag Ribbon)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates) { template in
                        let isSelected = customPrompt == template.text
                        Button(action: {
                            HapticHelper.selection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                customPrompt = template.text
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: template.icon)
                                    .font(.system(size: 11))
                                Text(template.name.localized)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? AppleTheme.primaryGradient : LinearGradient(
                                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .foregroundStyle(isSelected ? .white : .primary.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.15), lineWidth: 1.0)
                            )
                        }
                        .buttonStyle(PremiumButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
            
            // TextEditor Card (Liquid Glass container)
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $customPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 140)
                    .background(Color.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
                    )
                
                Text("Промпт определяет формат возвращаемого JSON-файла с заголовком, описанием и ключевыми словами.".localized)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            .glassCard(cornerRadius: 20, padding: 14)
        }
    }
}
