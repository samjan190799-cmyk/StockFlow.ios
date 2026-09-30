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
            AppScreen {
                headerCard
                statusSection
                promptSection
            }
            .navigationTitle("ИИ-Ассистент".localized)
            .navigationBarTitleDisplayMode(.large)
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

    private var headerCard: some View {
        HStack(spacing: 16) {
            SmartStockLogoView(size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text("SmartStock AI Engine".localized)
                    .font(.headline)
                Text("Мультимодальный анализ визуальных сцен, генерация коммерческих названий, описаний и SEO-тегов.".localized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var statusSection: some View {
        AppSection("Нейросетевое ядро".localized, symbol: "sparkles", tint: AppPalette.amber) {
            AppRow {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Gemini Vision / Pro".localized)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                    AppChip(text: "Активен".localized, symbol: "checkmark.circle.fill", tone: .success)
                }
            }

            AppDivider()

            AppRow {
                limitBlock
            }
        }
    }

    @ViewBuilder
    private var limitBlock: some View {
        if storeManager.isProUser {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Color.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Дневной лимит".localized)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Безлимитный доступ (PRO)".localized)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Дневной лимит".localized)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(limitText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }

                ProgressView(value: limitFraction)
                    .tint(AppPalette.amber)

                Button {
                    HapticHelper.trigger(.light)
                    showPaywall = true
                } label: {
                    Label("Безлимит".localized, systemImage: "crown.fill")
                }
                .buttonStyle(.appCapsule)
            }
        }
    }

    private var baseRemaining: Int {
        max(0, RewardAdManager.baseDailyLimit - rewardManager.dailyAIUsed)
    }

    private var limitFraction: Double {
        Double(baseRemaining) / Double(max(RewardAdManager.baseDailyLimit, 1))
    }

    private var limitText: String {
        let limit = RewardAdManager.baseDailyLimit
        if rewardManager.bonusCredits > 0 {
            return "\(baseRemaining)/\(limit) (+\(rewardManager.bonusCredits) бонус)"
        }
        return "\(rewardManager.remainingAIToday)/\(limit) доступно"
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Стиль индексации".localized)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    HapticHelper.trigger(.light)
                    showResetAlert = true
                } label: {
                    Text("Сбросить".localized)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppPalette.accentLight)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates) { template in
                        templateChip(template)
                    }
                }
                .padding(.horizontal, 2)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $customPrompt)
                    .font(Font.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 180)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))

                Text("Промпт определяет формат возвращаемого JSON-файла с заголовком, описанием и ключевыми словами.".localized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appCard()
        }
    }

    private func templateChip(_ template: PromptTemplate) -> some View {
        let isSelected = customPrompt == template.text
        return Button {
            HapticHelper.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                customPrompt = template.text
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: template.icon)
                Text(template.name.localized)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
            .background(Capsule().fill(isSelected ? Color.primary : Color.primary.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.10), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
