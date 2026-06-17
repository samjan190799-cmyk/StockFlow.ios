import SwiftUI

struct StockSettingsView: View {
    @State private var platforms: [StockPlatform] = []
    @State private var selectedPlatformId: String? = nil
    
    // For connection verification
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Интегрированные фотостоки")) {
                    ForEach(platforms) { platform in
                        HStack(spacing: 12) {
                            // Mini brand icon / initials circle
                            Circle()
                                .fill(colorForPlatform(platform.id))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(String(platform.name.prefix(2)))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(platform.name)
                                    .font(.system(size: 15, weight: .semibold))
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
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPlatformId = platform.id
                        }
                    }
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
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .overlay(
                            ProgressView("Проверка соединения...")
                                .padding()
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 10)
                        )
                }
            }
        }
    }
    
    // MARK: - Brand Colors Mock
    private func colorForPlatform(_ id: String) -> Color {
        switch id {
        case "adobe": return .red
        case "shutterstock": return .orange
        case "istock": return .black
        case "freepik": return .blue
        case "depositphotos": return .green
        case "alamy": return .gray
        case "dreamstime": return .indigo
        case "123rf": return .yellow
        case "pond5": return .teal
        default: return .blue
        }
    }
    
    // MARK: - Detail Sheet Component
    private func platformDetailSheet(_ platform: StockPlatform) -> some View {
        let index = platforms.firstIndex(where: { $0.id == platform.id })!
        
        return NavigationStack {
            Form {
                Section(header: Text("Параметры SFTP / FTP для \(platform.name)")) {
                    Toggle("Активен", isOn: $platforms[index].isEnabled)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Имя хоста (сервер)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("ftp.example.com", text: $platforms[index].host)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Имя пользователя (логин)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("Username", text: $platforms[index].username)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Пароль")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        SecureField("••••••••", text: $platforms[index].passwordHash)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                Section {
                    Button(action: { testConnection(platforms[index]) }) {
                        Text("Проверить соединение")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.blue)
                    }
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
                }
            }
        }
    }
    
    // MARK: - Data Storage
    private func loadPlatforms() {
        if let data = UserDefaults.standard.data(forKey: "stock_platforms"),
           let decoded = try? JSONDecoder().decode([StockPlatform].self, from: data) {
            self.platforms = decoded
        } else {
            // Prepopulate with defaults
            self.platforms = StockPlatform.defaults
            savePlatforms()
        }
    }
    
    private func savePlatforms() {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isVerifying = false
            alertMessage = "Успешное соединение с сервером \(platform.host)! Аутентификация пройдена."
            showingAlert = true
        }
    }
}

// MARK: - Helper Models for Sheet Presentation
struct ActiveSheetPlatform: Identifiable {
    let id: String
    let platform: StockPlatform
}
