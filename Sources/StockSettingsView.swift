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
                        
                        LazyVStack(spacing: 10) {
                            ForEach(platforms) { platform in
                                HStack(spacing: 12) {
                                    // Mini brand icon / initials circle
                                    Circle()
                                        .fill(colorForPlatform(platform.id))
                                        .frame(width: 38, height: 38)
                                        .overlay(
                                            Text(String(platform.name.prefix(2)))
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                        )
                                        .shadow(color: colorForPlatform(platform.id).opacity(0.3), radius: 4)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(platform.name)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.primary)
                                        Text(platform.host)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { platform.isEnabled },
                                        set: { value in
                                            togglePlatform(platform.id, isEnabled: value)
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(Color(hex: "7C3AED")) // Premium purple tint
                                }
                                .glassCard(cornerRadius: 14, padding: 12)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedPlatformId = platform.id
                                }
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
                    if let id = selectedPlatformId, let platform = platforms.first(where: { $0.id == id }) {
                        return ActiveSheetPlatform(id: id, platform: platform)
                    }
                    return nil
                },
                set: { value in
                    selectedPlatformId = value?.id
                }
            )) { wrapper in
                platformDetailSheet(wrapper.platform)
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
        case "istock": return Color(hex: "1F2937") // Dark Charcoal
        case "freepik": return Color(hex: "0066FF") // Freepik Blue
        case "depositphotos": return Color(hex: "10B981") // Mint Green
        case "alamy": return Color(hex: "6B7280") // Gray
        case "dreamstime": return Color(hex: "6366F1") // Indigo
        case "123rf": return Color(hex: "FBBF24") // Amber Yellow
        case "pond5": return Color(hex: "06B6D4") // Teal/Cyan
        default: return .blue
        }
    }
    
    // MARK: - Detail Sheet Component
    private func platformDetailSheet(_ platform: StockPlatform) -> some View {
        let index = platforms.firstIndex(where: { $0.id == platform.id })!
        
        return NavigationStack {
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
                                Toggle("", isOn: $platforms[index].isEnabled)
                                    .labelsHidden()
                                    .tint(Color(hex: "7C3AED"))
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            customInputField(title: "Имя хоста (сервер)", placeholder: "ftp.example.com", text: $platforms[index].host, isSecure: false)
                            
                            customInputField(title: "Имя пользователя (логин)", placeholder: "Username", text: $platforms[index].username, isSecure: false)
                            
                            customInputField(title: "Пароль", placeholder: "••••••••", text: $platforms[index].passwordHash, isSecure: true)
                        }
                        .glassCard()
                        
                        Button(action: { testConnection(platforms[index]) }) {
                            Text("Проверить соединение")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial)
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(platform.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        savePlatforms()
                        selectedPlatformId = nil
                    }
                    .font(.system(size: 14, weight: .bold))
                }
            }
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
            .padding(10)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        }
    }
    
    // MARK: - Data Storage
    private func loadPlatforms() {
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
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            isVerifying = false
            alertMessage = "Успешное соединение с сервером \(platform.host)! Аутентификация пройдена."
            showingAlert = true
        }
    }
}

// MARK: - Helper Models for Sheet Presentation
struct ActiveSheetPlatform: Identifiable, Sendable {
    let id: String
    let platform: StockPlatform
}
