import SwiftUI

// MARK: - Google OAuth 2.0 Help Sheet
@MainActor
struct GoogleOAuthHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color(hex: "4285F4"), Color(hex: "34A853")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "photo.stack.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Настройка Google Фото".localized)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("Пошаговое руководство по получению Client ID".localized)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .glassCard(cornerRadius: 18, padding: 14)

                        // Step 1
                        instructionStep(
                            number: "1",
                            title: "Создайте проект в Google Cloud".localized,
                            description: "Перейдите в консоль разработчика Google Cloud и создайте новый бесплатный проект (например, SmartStock).".localized,
                            icon: "plus.circle.fill",
                            color: .blue
                        )

                        // Step 2
                        instructionStep(
                            number: "2",
                            title: "Включите Photos Library API".localized,
                            description: "В разделе «APIs & Services» → «Library» найдите «Photos Library API» (а также «Google Drive API») и нажмите кнопку «Enable» (Включить).".localized,
                            icon: "checkmark.seal.fill",
                            color: .green
                        )

                        // Step 3
                        instructionStep(
                            number: "3",
                            title: "Настройте OAuth Consent Screen".localized,
                            description: "В разделе «OAuth consent screen» выберите тип «External» (Внешний), укажите имя приложения и ваш email. В блоке «Test users» добавьте свой Gmail-адрес.".localized,
                            icon: "person.crop.circle.badge.checkmark",
                            color: .orange
                        )

                        // Step 4
                        instructionStep(
                            number: "4",
                            title: "Создайте OAuth Client ID".localized,
                            description: "В разделе «Credentials» нажмите «+ Create Credentials» → «OAuth client ID». Выберите тип приложения «iOS» (Bundle ID: com.samvel.smartstock.SmartStock) или «Web application».".localized,
                            icon: "key.fill",
                            color: .purple
                        )

                        // Step 5
                        instructionStep(
                            number: "5",
                            title: "Вставьте Client ID в приложение".localized,
                            description: "Скопируйте полученный идентификатор (вида xxxx.apps.googleusercontent.com) и вставьте в поле Client ID в приложении.".localized,
                            icon: "arrow.down.doc.fill",
                            color: .cyan
                        )

                        // Open Google Cloud Console Button
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            if let url = URL(string: "https://console.cloud.google.com/apis/credentials") {
                                openURL(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "safari.fill")
                                    .font(.system(size: 16))
                                Text("Открыть Google Cloud Console".localized)
                                    .font(.system(size: 15, weight: .bold))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(LinearGradient(colors: [Color(hex: "4285F4"), Color(hex: "34A853")], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color(hex: "4285F4").opacity(0.35), radius: 8, y: 4)
                        }
                        .padding(.top, 6)

                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .navigationTitle("Инструкция Google Фото".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть".localized) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                }
            }
        }
    }

    private func instructionStep(number: String, title: String, description: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(number)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: 14)
    }
}

// MARK: - AI Providers Help Sheet (Gemini, OpenAI, Claude)
@MainActor
struct AIKeyHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selectedTab: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Tab Selector
                        Picker("", selection: $selectedTab) {
                            Text("Gemini AI").tag(0)
                            Text("OpenAI").tag(1)
                            Text("Claude").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 4)

                        if selectedTab == 0 {
                            geminiHelpContent
                        } else if selectedTab == 1 {
                            openAIHelpContent
                        } else {
                            claudeHelpContent
                        }

                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .navigationTitle("Как получить API-ключ".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть".localized) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                }
            }
        }
    }

    // MARK: - Gemini Content
    private var geminiHelpContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Google Gemini AI")
                            .font(.system(size: 17, weight: .bold))
                        Text("Бесплатно".localized)
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                    Text("Рекомендуемый провайдер: самый быстрый и бесплатный доступ.".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .glassCard(cornerRadius: 16, padding: 12)

            instructionStep(
                number: "1",
                title: "Откройте Google AI Studio".localized,
                description: "Перейдите на официальный портал Google AI Studio (aistudio.google.com).".localized,
                icon: "globe",
                color: .blue
            )

            instructionStep(
                number: "2",
                title: "Войдите с Google-аккаунтом".localized,
                description: "Используйте ваш обычный личный аккаунт Google для входа в сервис.".localized,
                icon: "person.crop.circle.fill",
                color: .cyan
            )

            instructionStep(
                number: "3",
                title: "Нажмите «Create API key»".localized,
                description: "Нажмите синюю кнопку «Create API key» (Создать ключ API) и выберите или создайте проект.".localized,
                icon: "key.fill",
                color: .purple
            )

            instructionStep(
                number: "4",
                title: "Скопируйте и вставьте ключ".localized,
                description: "Скопируйте сгенерированный ключ (начинается на «AIzaSy...») и вставьте в приложении в поле Gemini.".localized,
                icon: "doc.on.clipboard.fill",
                color: .green
            )

            Button(action: {
                HapticHelper.trigger(.medium)
                if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                    openURL(url)
                }
            }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Получить ключ в Google AI Studio".localized)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.purple.opacity(0.3), radius: 8, y: 4)
            }
        }
    }

    // MARK: - OpenAI Content
    private var openAIHelpContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("OpenAI (ChatGPT)")
                        .font(.system(size: 17, weight: .bold))
                    Text("Высокое качество индексации через модели GPT-4o и GPT-4o-mini.".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .glassCard(cornerRadius: 16, padding: 12)

            instructionStep(
                number: "1",
                title: "Откройте OpenAI Platform".localized,
                description: "Перейдите на страницу ключей API (platform.openai.com/api-keys).".localized,
                icon: "globe",
                color: .teal
            )

            instructionStep(
                number: "2",
                title: "Создайте новый секретный ключ".localized,
                description: "Нажмите кнопку «+ Create new secret key», укажите название и сохраните ключ.".localized,
                icon: "key.fill",
                color: .green
            )

            instructionStep(
                number: "3",
                title: "Вставьте ключ в приложение".localized,
                description: "Скопируйте ключ (начинается на «sk-...») и вставьте в поле OpenAI в настройках ИИ.".localized,
                icon: "doc.on.clipboard.fill",
                color: .blue
            )

            Button(action: {
                HapticHelper.trigger(.medium)
                if let url = URL(string: "https://platform.openai.com/api-keys") {
                    openURL(url)
                }
            }) {
                HStack {
                    Image(systemName: "key.fill")
                    Text("Открыть OpenAI API Keys".localized)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [Color.teal, Color.green], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.green.opacity(0.3), radius: 8, y: 4)
            }
        }
    }

    // MARK: - Claude Content
    private var claudeHelpContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Anthropic Claude")
                        .font(.system(size: 17, weight: .bold))
                    Text("Глубокое понимание коммерческой эстетики через Claude 3.5 Sonnet.".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .glassCard(cornerRadius: 16, padding: 12)

            instructionStep(
                number: "1",
                title: "Откройте Anthropic Console".localized,
                description: "Перейдите на страницу ключей (console.anthropic.com/settings/keys).".localized,
                icon: "globe",
                color: .orange
            )

            instructionStep(
                number: "2",
                title: "Создайте API-ключ".localized,
                description: "Нажмите «Create Key», задайте имя и скопируйте сформированный токен.".localized,
                icon: "key.fill",
                color: .red
            )

            instructionStep(
                number: "3",
                title: "Вставьте ключ в приложение".localized,
                description: "Скопируйте ключ (начинается на «sk-ant-...») и вставьте в поле Claude в настройках ИИ.".localized,
                icon: "doc.on.clipboard.fill",
                color: .orange
            )

            Button(action: {
                HapticHelper.trigger(.medium)
                if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                    openURL(url)
                }
            }) {
                HStack {
                    Image(systemName: "key.fill")
                    Text("Открыть Anthropic Console".localized)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [Color.orange, Color.red], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.orange.opacity(0.3), radius: 8, y: 4)
            }
        }
    }

    private func instructionStep(number: String, title: String, description: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)
                Text(number)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, padding: 12)
    }
}
