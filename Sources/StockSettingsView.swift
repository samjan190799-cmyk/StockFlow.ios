import SwiftUI

@MainActor
struct StockSettingsView: View {
    @State private var platforms: [StockPlatform] = []
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @State private var selectedPlatformId: String? = nil
    
    // For connection verification
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Интегрированные фотостоки".localized)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.leading, 4)
                        
                        LazyVStack(spacing: 12) {
                            ForEach(platforms) { platform in
                                PlatformRowView(
                                    platform: platform,
                                    onToggle: { value in
                                        togglePlatform(platform.id, isEnabled: value)
                                    },
                                    onTap: {
                                        selectedPlatformId = platform.id
                                    },
                                    color: colorForPlatform(platform.id)
                                )
                            }
                        }
                        
                        disclaimerSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Настройки стоков".localized)
            .navigationBarTitleDisplayMode(.inline)
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
                        }
                    )
                }
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
                                    .tint(.primary)
                                Text("Проверка соединения...".localized)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .glassCard(cornerRadius: 16, padding: 24)
                        )
                }
            }
        }
    }

    
    // MARK: - Brand Colors Mock
    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color(hex: "007AFF"))
                    .font(.system(size: 14))
                Text("Правовая информация и товарные знаки".localized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            Text("SmartStock является независимым инструментом и не связан, не авторизован и не спонсируется Shutterstock, Adobe Stock, Getty Images, Depositphotos, Freepik, Alamy, Dreamstime, 123RF, Pond5 или Google. Все товарные знаки и названия брендов принадлежат их правообладателям.".localized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .glassCard(cornerRadius: 16, padding: 16)
    }

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
    
    private func gradientForPlatform(_ id: String) -> LinearGradient {
        let color = colorForPlatform(id)
        return LinearGradient(
            colors: [color.opacity(0.08), color.opacity(0.01)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            self.platforms = decoded
        } else {
            // Prepopulate with defaults
            self.platforms = StockPlatform.defaults
            savePlatforms()
        }
    }
    
    private func savePlatforms() {
        for platform in platforms {
            let serviceKey = "com.samvel.smartstock.platform.\(platform.id)"
            if !platform.passwordHash.isEmpty {
                KeychainHelper.shared.save(password: platform.passwordHash, for: serviceKey)
            } else {
                KeychainHelper.shared.delete(for: serviceKey)
            }
        }
        if let encoded = try? JSONEncoder().encode(platforms) {
            UserDefaults.standard.set(encoded, forKey: "stock_platforms")
        }
    }
    
    private func togglePlatform(_ id: String, isEnabled: Bool) {
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
                try await FTPSecureClient.testConnection(
                    host: platform.host,
                    port: 21,
                    username: platform.username,
                    password: platform.passwordHash
                )
                isVerifying = false
                alertMessage = "Успешное соединение с сервером".localized + " \(platform.host)"
                showingAlert = true
            } catch {
                isVerifying = false
                alertMessage = "Ошибка соединения с".localized + " \(platform.host): \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}
@MainActor
struct PlatformRowView: View {
    @Environment(\.colorScheme) var colorScheme
    let platform: StockPlatform
    let onToggle: (Bool) -> Void
    let onTap: () -> Void
    let color: Color
    
    @State private var isPulsing = false
    
    var body: some View {
        let isConfigured = !platform.username.isEmpty && !platform.passwordHash.isEmpty
        let isDark = colorScheme == .dark
        
        HStack(spacing: 14) {
            // 3D Brand Avatar with Glass Overlay
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 1.0)
                    )
                    .shadow(color: color.opacity(platform.isEnabled ? 0.4 : 0.1), radius: 8, x: 0, y: 4)
                
                Text(String(platform.name.prefix(2)).uppercased())
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(platform.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(platform.isEnabled ? Color.primary : Color.primary.opacity(0.55))
                    
                    if platform.id == "adobe" || platform.id == "freepik" {
                        Text("SFTP")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "6366F1").opacity(0.18))
                            .foregroundStyle(Color(hex: "6366F1"))
                            .clipShape(Capsule())
                    }
                }
                
                Text(platform.host)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(isConfigured ? Color.green.opacity(0.3) : Color.orange.opacity(0.3))
                            .frame(width: 10, height: 10)
                            .scaleEffect(isPulsing && isConfigured ? 1.6 : 1.0)
                            .opacity(isPulsing && isConfigured ? 0.0 : 0.8)
                        
                        Circle()
                            .fill(isConfigured ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                    }
                    
                    Text(isConfigured ? "Подключено".localized : "Нужна настройка".localized)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isConfigured ? Color.green : Color.orange)
                }
                .padding(.top, 1)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { platform.isEnabled },
                set: { value in
                    HapticHelper.trigger(.light)
                    onToggle(value)
                }
            ))
            .labelsHidden()
            .tint(Color(hex: "007AFF"))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    platform.isEnabled
                    ? (isDark ? color.opacity(0.12) : color.opacity(0.06))
                    : (isDark ? Color(hex: "141620") : Color.white)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    platform.isEnabled
                    ? color.opacity(isDark ? 0.40 : 0.25)
                    : Color.white.opacity(isDark ? 0.08 : 0.25),
                    lineWidth: 1.0
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            HapticHelper.selection()
            onTap()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Helper Models for Sheet Presentation
struct ActiveSheetPlatformId: Identifiable, Sendable {
    let id: String
}

// MARK: - Platform Detail Sheet
struct PlatformDetailSheet: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var platform: StockPlatform
    var isVerifying: Bool
    var onSave: () -> Void
    var testConnection: (StockPlatform) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingOAuthHelp = false
    @State private var showingStockHelper = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Параметры SFTP / FTP для".localized + " \(platform.name)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            HStack {
                                Text("Активен".localized)
                                    .font(.system(size: 14, weight: .medium))
                                Spacer()
                                Toggle("", isOn: $platform.isEnabled)
                                    .labelsHidden()
                                    .tint(Color(hex: "007AFF"))
                            }
                            
                            Divider().background(Color.primary.opacity(0.08))
                            
                            customInputField(title: "Имя пользователя (логин)".localized, placeholder: "Username", text: $platform.username, isSecure: false)
                            
                            customInputField(title: "Пароль".localized, placeholder: "••••••••", text: $platform.passwordHash, isSecure: true)
                            
                            Button(action: {
                                HapticHelper.trigger(.light)
                                showingStockHelper = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "safari.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white)
                                    
                                    Text("Войти через Помощник (авто-настройка)".localized)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "007AFF"), Color(hex: "0051A8")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .ambientShadow(radius: 4)
                            }
                            .buttonStyle(PremiumButtonStyle())
                            .padding(.top, 2)
                            .sheet(isPresented: $showingStockHelper) {
                                StockSignInHelperView(platformId: platform.id) { username, password in
                                    platform.username = username
                                    platform.passwordHash = password
                                }
                            }
                            
                            // Кнопка помощи для входа через Google / Apple
                            Button(action: {
                                HapticHelper.trigger(.light)
                                showingOAuthHelp = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(hex: "007AFF"))
                                    
                                    Text("Вошли через Google или Apple?".localized)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color(hex: "007AFF"))
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(hex: "007AFF").opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PremiumButtonStyle())
                            .padding(.top, 2)
                            .sheet(isPresented: $showingOAuthHelp) {
                                OAuthHelpSheet()
                            }
                            
                            HStack {
                                Text("Сервер выгрузки:".localized + " \(platform.host)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            
                            DisclosureGroup("Дополнительные параметры сервера".localized) {
                                VStack(alignment: .leading, spacing: 8) {
                                    customInputField(title: "Имя хоста (сервер)".localized, placeholder: "ftp.example.com", text: $platform.host, isSecure: false)
                                    
                                    if platform.id == "adobe" || platform.id == "freepik" {
                                        Text("Внимание: Данный сток требует SFTP. Plain FTP-соединение для него может быть недоступно.".localized)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.orange)
                                            .lineLimit(nil)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tint(.secondary)
                        }
                        .glassCard(cornerRadius: 24, padding: 20)
                        
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            testConnection(platform)
                        }) {
                            HStack(spacing: 8) {
                                if isVerifying {
                                    ProgressView()
                                        .tint(.primary)
                                    Text("Проверка...".localized)
                                } else {
                                    Text("Проверить соединение".localized)
                                }
                            }
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1.2)
                            )
                        }
                        .buttonStyle(PremiumButtonStyle())
                        .disabled(isVerifying)
                    }
                    .padding()
                }
            }
            .navigationTitle(platform.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово".localized) {
                        HapticHelper.trigger(.light)
                        onSave()
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                }
            }
        }
        .onDisappear {
            onSave()
        }
    }
    
    // MARK: - Custom Input Field
    private func customInputField(title: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                        .textContentType(.password)
                } else {
                    TextField(placeholder, text: text)
                        .textContentType(.username)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(12)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1.2)
            )
            .textInputAutocapitalization(.never)
        }
    }
}

// MARK: - OAuthHelpSheet (Инструкции для входа через Google / Apple)
struct OAuthHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Важное предупреждение
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Важно для Google / Apple".localized)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            
                            Text("Если вы регистрировались на фотостоках через аккаунт Google или Apple, прямой вход по паролю этих сервисов не поддерживается для FTP/SFTP загрузки (это техническое ограничение самих стоков).".localized)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                            
                            Text("Для выгрузки из приложения вам необходимо использовать специальный FTP-пароль, сгенерированный в личном кабинете автора.".localized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineSpacing(4)
                        }
                        .glassCard(cornerRadius: 18, padding: 16)
                        
                        // Раздел Adobe Stock
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Инструкция для Adobe Stock".localized)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("1. Войдите в личный кабинет автора на contributor.adobestock.com.".localized)
                                Text("2. Перейдите в 'Настройки учетной записи' (нажав на свой профиль в правом верхнем углу).".localized)
                                Text("3. В подразделе 'Настройки FTP' вы увидите ваш персональный логин (ID) и сгенерированный FTP-пароль.".localized)
                                Text("4. Вставьте эти данные в настройки Adobe Stock в приложении.".localized)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            
                            Link(destination: URL(string: "https://contributor.adobestock.com/")!) {
                                HStack {
                                    Image(systemName: "safari")
                                    Text("Открыть Adobe Stock Contributor".localized)
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(hex: "FF0000"))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PremiumButtonStyle())
                        }
                        .glassCard(cornerRadius: 18, padding: 16)
                        
                        // Раздел Shutterstock
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Инструкция для Shutterstock".localized)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("1. Войдите в кабинет автора на submit.shutterstock.com.".localized)
                                Text("2. Перейдите в настройки аккаунта 'Account Settings'.".localized)
                                Text("3. Найдите раздел FTP и скопируйте предоставленные учетные данные (обычно логином является ваш email).".localized)
                                Text("4. Введите их в настройки Shutterstock в приложении.".localized)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            
                            Link(destination: URL(string: "https://submit.shutterstock.com/")!) {
                                HStack {
                                    Image(systemName: "safari")
                                    Text("Открыть submit.shutterstock.com".localized)
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(hex: "FF6600"))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(PremiumButtonStyle())
                        }
                        .glassCard(cornerRadius: 18, padding: 16)
                    }
                    .padding()
                }
            }
            .navigationTitle("Вход через Google / Apple".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово".localized) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                }
            }
        }
    }
}
