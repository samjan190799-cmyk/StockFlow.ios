import SwiftUI

@MainActor
struct StockSettingsView: View {
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var platforms: [StockPlatform] = []
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @State private var selectedPlatformId: String? = nil
    @State private var selectedGuidePlatformId: String? = nil

    // For connection verification and Paywall
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    @State private var showingPaywall = false

    private let freeStockLimit = 2

    var body: some View {
        NavigationStack {
            AppScreen(maxWidth: 960) {
                platformsSection
                disclaimerSection
            }
            .navigationTitle("Настройки стоков".localized)
            .navigationBarTitleDisplayMode(.large)
            .onAppear(perform: loadPlatforms)
            .sheet(item: Binding(
                get: {
                    if let id = selectedPlatformId {
                        return ActiveSheetPlatformId(id: id)
                    }
                    return nil
                },
                set: { value in
                    selectedPlatformId = value?.id
                }
            )) { wrapper in
                if let index = platforms.firstIndex(where: { $0.id == wrapper.id }) {
                    PlatformDetailSheet(
                        platform: $platforms[index],
                        isVerifying: isVerifying,
                        onSave: {
                            savePlatforms()
                        },
                        testConnection: { platform in
                            testConnection(platform)
                        },
                        onRequirePro: {
                            showingPaywall = true
                        }
                    )
                }
            }
            .sheet(item: Binding(
                get: {
                    if let id = selectedGuidePlatformId {
                        return ActiveSheetPlatformId(id: id)
                    }
                    return nil
                },
                set: { value in
                    selectedGuidePlatformId = value?.id
                }
            )) { wrapper in
                StockAgencyGuideSheet(platformId: wrapper.id)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .alert("Подключение".localized, isPresented: $showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .overlay {
                if isVerifying {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Проверка соединения...".localized)
                                    .font(.subheadline.weight(.medium))
                            }
                            .appCard(cornerRadius: 16, padding: 24)
                        )
                }
            }
        }
    }

    // MARK: - Sections

    private var enabledCount: Int {
        platforms.filter { $0.isEnabled }.count
    }

    private var platformsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Интегрированные фотостоки".localized)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if !storeManager.isProUser {
                    Button {
                        HapticHelper.trigger(.light)
                        showingPaywall = true
                    } label: {
                        AppChip(text: "\(min(enabledCount, freeStockLimit))/\(freeStockLimit)", symbol: "crown.fill", tone: .warning)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                ForEach(platforms) { platform in
                    PlatformRowView(
                        platform: platform,
                        onToggle: { value in
                            togglePlatform(platform.id, isEnabled: value)
                        },
                        onTap: {
                            selectedPlatformId = platform.id
                        },
                        onInfoTap: {
                            selectedGuidePlatformId = platform.id
                        },
                        color: colorForPlatform(platform.id)
                    )
                }
            }
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Правовая информация и товарные знаки".localized)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(AppPalette.accentLight)
            }

            Text("SmartStock является независимым инструментом и не связан, не авторизован и не спонсируется Shutterstock, Adobe Stock, Getty Images, Depositphotos, Freepik, Alamy, Dreamstime, 123RF, Pond5 или Google. Все товарные знаки и названия брендов принадлежат их правообладателям.".localized)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // MARK: - Brand Colors
    private func colorForPlatform(_ id: String) -> Color {
        switch id {
        case "adobe": return Color(hex: "FF0000") // Adobe Red
        case "shutterstock": return Color(hex: "FF6600") // Shutterstock Orange
        case "istock": return Color(hex: "3B82F6") // Brand Blue
        case "freepik": return Color(hex: "0066FF") // Freepik Blue
        case "depositphotos": return Color(hex: "10B981") // Mint Green
        case "alamy": return Color(hex: "6B7280") // Gray
        case "dreamstime": return Color(hex: "6366F1") // Indigo
        case "123rf": return Color(hex: "FBBF24") // Amber Yellow
        case "pond5": return Color(hex: "06B6D4") // Teal/Cyan
        default: return .blue
        }
    }

    // MARK: - Data Storage
    private func loadPlatforms() {
        guard platforms.isEmpty else { return }
        if let data = UserDefaults.standard.data(forKey: "stock_platforms"),
           var decoded = try? JSONDecoder().decode([StockPlatform].self, from: data) {
            for i in 0..<decoded.count {
                let serviceKey = "com.samvel.smartstock.platform.\(decoded[i].id)"
                decoded[i].passwordHash = KeychainHelper.shared.read(for: serviceKey) ?? ""
            }
            if !storeManager.isProUser {
                var enabledCount = 0
                for i in 0..<decoded.count {
                    if decoded[i].isEnabled {
                        enabledCount += 1
                        if enabledCount > 2 {
                            decoded[i].isEnabled = false
                        }
                    }
                }
            }
            self.platforms = decoded
            savePlatforms()
        } else {
            // Prepopulate with defaults
            self.platforms = StockPlatform.defaults
            savePlatforms()
        }
    }
    
    private func savePlatforms() {
        let platformsCopy = self.platforms
        Task.detached(priority: .utility) {
            for platform in platformsCopy {
                let serviceKey = "com.samvel.smartstock.platform.\(platform.id)"
                if !platform.passwordHash.isEmpty {
                    KeychainHelper.shared.save(password: platform.passwordHash, for: serviceKey)
                } else {
                    KeychainHelper.shared.delete(for: serviceKey)
                }
            }
            if let encoded = try? JSONEncoder().encode(platformsCopy) {
                UserDefaults.standard.set(encoded, forKey: "stock_platforms")
            }
        }
    }
    
    private func togglePlatform(_ id: String, isEnabled: Bool) {
        if isEnabled && !storeManager.isProUser {
            let activeCount = platforms.filter { $0.isEnabled && $0.id != id }.count
            if activeCount >= 2 {
                HapticHelper.notification(.warning)
                showingPaywall = true
                return
            }
        }
        if let idx = platforms.firstIndex(where: { $0.id == id }) {
            platforms[idx].isEnabled = isEnabled
            savePlatforms()
        }
    }
    
    private func testConnection(_ platform: StockPlatform) {
        guard !platform.username.isEmpty && !platform.passwordHash.isEmpty else {
            alertMessage = "Пожалуйста, введите логин и пароль.".localized
            showingAlert = true
            return
        }
        
        isVerifying = true
        Task {
            do {
                let parsed = FTPSecureClient.parseHostAndPort(from: platform.host, defaultPort: 21)
                try await FTPSecureClient.testConnection(
                    host: parsed.host,
                    port: parsed.port,
                    username: platform.username,
                    password: platform.passwordHash
                )
                isVerifying = false
                alertMessage = "Успешное соединение с сервером".localized + " \(parsed.host):\(parsed.port)"
                showingAlert = true
            } catch {
                isVerifying = false
                alertMessage = "Ошибка соединения с".localized + " \(platform.host): \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

// MARK: - Карточка платформы
@MainActor
struct PlatformRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let platform: StockPlatform
    let onToggle: (Bool) -> Void
    let onTap: () -> Void
    let onInfoTap: () -> Void
    let color: Color

    private var isConfigured: Bool {
        !platform.username.isEmpty && !platform.passwordHash.isEmpty
    }

    private var needsSFTP: Bool {
        platform.id == "adobe" || platform.id == "freepik"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                HapticHelper.selection()
                onTap()
            } label: {
                HStack(spacing: 12) {
                    brandTile

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(platform.name)
                                .font(.headline)
                                .foregroundStyle(platform.isEnabled ? Color.primary : Color.secondary)
                            if needsSFTP {
                                AppChip(text: "SFTP", tone: .info)
                            }
                        }

                        Text(platform.host)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        AppChip(
                            text: isConfigured ? "Подключено".localized : "Нужна настройка".localized,
                            symbol: isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            tone: isConfigured ? .success : .warning
                        )
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Инструкция по стоку
            Button {
                HapticHelper.trigger(.light)
                onInfoTap()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundStyle(AppPalette.accentLight)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Инструкция".localized)

            Toggle("", isOn: Binding(
                get: { platform.isEnabled },
                set: { value in
                    HapticHelper.trigger(.light)
                    onToggle(value)
                }
            ))
            .labelsHidden()
            .tint(AppPalette.accent)
            .accessibilityLabel(platform.name)
        }
        .appCard(cornerRadius: 16, padding: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(platform.isEnabled ? (colorScheme == .dark ? 0.50 : 0.35) : 0), lineWidth: 1.5)
        )
    }

    private var brandTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(String(platform.name.prefix(2)).uppercased())
                .font(Font.system(.body, design: .rounded).weight(.black))
                .foregroundStyle(platform.id == "123rf" ? Color.black.opacity(0.75) : Color.white)
        }
        .frame(width: 48, height: 48)
        .opacity(platform.isEnabled ? 1 : 0.55)
        .accessibilityHidden(true)
    }
}

// MARK: - Helper Models for Sheet Presentation
struct ActiveSheetPlatformId: Identifiable, Sendable {
    let id: String
}

// MARK: - Platform Detail Sheet
struct PlatformDetailSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Binding var platform: StockPlatform
    var isVerifying: Bool
    var onSave: () -> Void
    var testConnection: (StockPlatform) -> Void
    var onRequirePro: () -> Void
    @State private var showingOAuthHelp = false
    @State private var showingStockHelper = false
    @State private var showingGuideSheet = false
    @State private var showingAdvanced = false

    private var needsSFTP: Bool {
        platform.id == "adobe" || platform.id == "freepik"
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { platform.isEnabled },
            set: { value in
                if value && !StoreManager.shared.isProUser && !platform.isEnabled {
                    if let data = UserDefaults.standard.data(forKey: "stock_platforms"),
                       let saved = try? JSONDecoder().decode([StockPlatform].self, from: data) {
                        let activeCount = saved.filter { $0.isEnabled && $0.id != platform.id }.count
                        if activeCount >= 2 {
                            HapticHelper.notification(.warning)
                            onRequirePro()
                            return
                        }
                    }
                }
                platform.isEnabled = value
                onSave()
            }
        )
    }

    var body: some View {
        NavigationStack {
            AppScreen(maxWidth: 560) {
                credentialsSection
                helpersSection
                serverSection
                testButton
            }
            .navigationTitle(platform.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticHelper.trigger(.light)
                        showingGuideSheet = true
                    } label: {
                        Label("Инструкция".localized, systemImage: "questionmark.circle.fill")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово".localized) {
                        HapticHelper.trigger(.light)
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingGuideSheet) {
                StockAgencyGuideSheet(platformId: platform.id)
            }
            .sheet(isPresented: $showingStockHelper) {
                StockSignInHelperView(platformId: platform.id) { username, password in
                    platform.username = username
                    platform.passwordHash = password
                }
            }
            .sheet(isPresented: $showingOAuthHelp) {
                OAuthHelpSheet()
            }
        }
        .onDisappear {
            onSave()
        }
    }

    // MARK: - Sections

    private var credentialsSection: some View {
        AppSection("Параметры SFTP / FTP для".localized + " \(platform.name)") {
            AppToggleRow(title: "Активен".localized, isOn: activeBinding)

            AppDivider()

            AppRow {
                AppTextField(
                    title: "Имя пользователя (логин)".localized,
                    placeholder: "Username",
                    text: $platform.username,
                    contentType: .username
                )
            }

            AppDivider()

            AppRow {
                AppTextField(
                    title: "Пароль".localized,
                    placeholder: "••••••••",
                    text: $platform.passwordHash,
                    isSecure: true,
                    contentType: .password
                )
            }
        }
    }

    private var helpersSection: some View {
        AppSection {
            Button {
                HapticHelper.trigger(.light)
                showingStockHelper = true
            } label: {
                AppNavRowLabel(
                    symbol: "safari.fill",
                    tint: AppPalette.accent,
                    title: "Войти через Помощник (авто-настройка)".localized,
                    trailingSymbol: "sparkles"
                )
            }
            .buttonStyle(.plain)

            AppDivider()

            Button {
                HapticHelper.trigger(.light)
                showingOAuthHelp = true
            } label: {
                AppNavRowLabel(
                    symbol: "questionmark.circle.fill",
                    tint: AppPalette.amber,
                    title: "Вошли через Google или Apple?".localized
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var serverSection: some View {
        AppSection(footer: "Сервер выгрузки:".localized + " \(platform.host)") {
            DisclosureGroup("Дополнительные параметры сервера".localized, isExpanded: $showingAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    AppTextField(
                        title: "Имя хоста (сервер)".localized,
                        placeholder: "ftp.example.com",
                        text: $platform.host,
                        monospaced: true
                    )

                    if needsSFTP {
                        Label {
                            Text("Внимание: Данный сток требует SFTP. Plain FTP-соединение для него может быть недоступно.".localized)
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(AppTone.warning.foreground(colorScheme))
                    }
                }
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
            .tint(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var testButton: some View {
        Button {
            HapticHelper.trigger(.medium)
            testConnection(platform)
        } label: {
            HStack(spacing: 8) {
                if isVerifying {
                    ProgressView()
                    Text("Проверка...".localized)
                } else {
                    Image(systemName: "bolt.horizontal.fill")
                    Text("Проверить соединение".localized)
                }
            }
        }
        .buttonStyle(.appPrimary)
        .disabled(isVerifying)
    }
}

// MARK: - OAuthHelpSheet (Инструкции для входа через Google / Apple)
struct OAuthHelpSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AppScreen(maxWidth: 560) {
                warningCard

                instructionCard(
                    title: "Инструкция для Adobe Stock",
                    steps: [
                        "1. Войдите в личный кабинет автора на contributor.adobestock.com.",
                        "2. Перейдите в 'Настройки учетной записи' (нажав на свой профиль в правом верхнем углу).",
                        "3. В подразделе 'Настройки FTP' вы увидите ваш персональный логин (ID) и сгенерированный FTP-пароль.",
                        "4. Вставьте эти данные в настройки Adobe Stock в приложении."
                    ],
                    linkTitle: "Открыть Adobe Stock Contributor",
                    urlString: "https://contributor.adobestock.com/",
                    brand: Color(hex: "E11D1D")
                )

                instructionCard(
                    title: "Инструкция для Shutterstock",
                    steps: [
                        "1. Войдите в кабинет автора на submit.shutterstock.com.",
                        "2. Перейдите в настройки аккаунта 'Account Settings'.",
                        "3. Найдите раздел FTP и скопируйте предоставленные учетные данные (обычно логином является ваш email).",
                        "4. Введите их в настройки Shutterstock в приложении."
                    ],
                    linkTitle: "Открыть submit.shutterstock.com",
                    urlString: "https://submit.shutterstock.com/",
                    brand: Color(hex: "D95700")
                )
            }
            .navigationTitle("Вход через Google / Apple".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово".localized) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // Важное предупреждение
    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Важно для Google / Apple".localized)
                    .font(.subheadline.weight(.bold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTone.warning.foreground(colorScheme))
            }

            Text("Если вы регистрировались на фотостоках через аккаунт Google или Apple, прямой вход по паролю этих сервисов не поддерживается для FTP/SFTP загрузки (это техническое ограничение самих стоков).".localized)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Для выгрузки из приложения вам необходимо использовать специальный FTP-пароль, сгенерированный в личном кабинете автора.".localized)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func instructionCard(title: String, steps: [String], linkTitle: String, urlString: String, brand: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.localized)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(steps, id: \.self) { step in
                    Text(step.localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(linkTitle.localized, systemImage: "safari")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(brand))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}
