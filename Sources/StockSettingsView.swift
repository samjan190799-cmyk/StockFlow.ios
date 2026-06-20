import SwiftUI

@MainActor
struct StockSettingsView: View {
    @State private var platforms: [StockPlatform] = []
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
                        Text("Интегрированные фотостоки")
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
                    }
                    .padding()
                }
            }
            .navigationTitle("Настройки стоков")
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
            .alert("Подключение", isPresented: $showingAlert) {
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
                                Text("Проверка соединения...")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .glassCard(cornerRadius: 16, padding: 24)
                        )
                }
            }
        }
    }

    
    // MARK: - Brand Colors Mock
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
            alertMessage = "Пожалуйста, введите логин и пароль."
            showingAlert = true
            return
        }
        
        isVerifying = true
        Task {
            do {
                try await FTPClient.testConnection(
                    host: platform.host,
                    port: 21,
                    username: platform.username,
                    password: platform.passwordHash
                )
                isVerifying = false
                alertMessage = "Успешное соединение с сервером \(platform.host)! Аутентификация пройдена."
                showingAlert = true
            } catch {
                isVerifying = false
                alertMessage = "Ошибка соединения с \(platform.host): \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}
@MainActor
struct PlatformRowView: View {
    let platform: StockPlatform
    let onToggle: (Bool) -> Void
    let onTap: () -> Void
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            // 3D Brand Logo initials circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Text(String(platform.name.prefix(2)))
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.white)
                )
                .shadow(color: color.opacity(platform.isEnabled ? 0.45 : 0.15), radius: platform.isEnabled ? 8 : 4)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(platform.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(platform.isEnabled ? Color.primary : Color.primary.opacity(0.6))
                Text(platform.host)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                let isConfigured = !platform.username.isEmpty && !platform.passwordHash.isEmpty
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConfigured ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Text(isConfigured ? "Настроен" : "Нужна настройка")
                        .font(.system(size: 10, weight: .semibold))
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
            .tint(Color(hex: "7C3AED"))
        }
        .padding(16)
        .background(platform.isEnabled ? color.opacity(0.06) : Color.clear)
        .glassCard(cornerRadius: 22, padding: 0)
        .shadow(color: color.opacity(platform.isEnabled ? 0.12 : 0.0), radius: 10, x: 0, y: 5)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticHelper.selection()
            onTap()
        }
    }
}

// MARK: - Helper Models for Sheet Presentation
struct ActiveSheetPlatformId: Identifiable, Sendable {
    let id: String
}

// MARK: - Platform Detail Sheet
struct PlatformDetailSheet: View {
    @Binding var platform: StockPlatform
    var isVerifying: Bool
    var onSave: () -> Void
    var testConnection: (StockPlatform) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Параметры SFTP / FTP для \(platform.name)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            HStack {
                                Text("Активен")
                                    .font(.system(size: 14, weight: .medium))
                                Spacer()
                                Toggle("", isOn: $platform.isEnabled)
                                    .labelsHidden()
                                    .tint(Color(hex: "7C3AED"))
                            }
                            
                            Divider().background(Color.primary.opacity(0.08))
                            
                            customInputField(title: "Имя пользователя (логин)", placeholder: "Username", text: $platform.username, isSecure: false)
                            
                            customInputField(title: "Пароль", placeholder: "••••••••", text: $platform.passwordHash, isSecure: true)
                            
                            HStack {
                                Text("Сервер выгрузки: \(platform.host)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            
                            DisclosureGroup("Дополнительные параметры сервера") {
                                VStack(alignment: .leading, spacing: 8) {
                                    customInputField(title: "Имя хоста (сервер)", placeholder: "ftp.example.com", text: $platform.host, isSecure: false)
                                    
                                    if platform.id == "adobe" || platform.id == "freepik" {
                                        Text("Внимание: Данный сток требует SFTP. Plain FTP-соединение для него может быть недоступно.")
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
                                    Text("Проверка...")
                                } else {
                                    Text("Проверить соединение")
                                }
                            }
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
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
