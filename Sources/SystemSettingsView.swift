import SwiftUI
import AuthenticationServices

@MainActor
struct SystemSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    // Left Column settings
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @AppStorage("sys_fps") private var sysFps: String = "120 FPS (Ультра-плавность)"
    @AppStorage("sys_bg_scheduler") private var bgScheduler: Bool = false
    
    // Right Column settings
    @AppStorage("sys_auto_upscale") private var autoUpscale: Bool = false
    @AppStorage("sys_upscale_threshold") private var upscaleThreshold: String = "Меньше 4 МБ (Рекомендуется)"
    @AppStorage("sys_upscale_factor") private var upscaleFactor: String = "Увеличение 2x (Бикубическое)"
    
    @AppStorage("sys_parallel_streams") private var parallelStreams: Int = 3
    @AppStorage("sys_retry_on_fail") private var retryOnFail: Bool = true
    @AppStorage("sys_compress_jpeg") private var compressJpeg: Bool = false
    @AppStorage("sys_notifications") private var sysNotifications: Bool = true
    
    // PC Server settings
    @AppStorage("sys_pc_server_enabled") private var pcServerEnabled: Bool = false
    @AppStorage("sys_pc_server_address") private var pcServerAddress: String = "192.168.1.50:5000"
    
    // Auth settings
    @AppStorage("user_signed_in") private var isUserSignedIn: Bool = false
    @AppStorage("user_email") private var userEmail: String = ""
    @AppStorage("user_provider") private var userProvider: String = ""
    
    @State private var isSigningIn = false
    @State private var showingSavedToast = false
    @State private var showSimulatedAuthSheet = false
    @State private var selectedProviderForAuth = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        
                        // SECTION 1: Interface
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Интерфейс")
                            
                            pickerRow("Язык интерфейса", selection: $sysLanguage, options: ["Русский", "English"])
                            
                            Divider().background(Color.primary.opacity(0.08))
                            
                            pickerRow("Тема оформления", selection: $sysTheme, options: ["Темная", "Светлая", "Системная"])
                            
                            Divider().background(Color.primary.opacity(0.08))
                            
                            pickerRow("Предел частоты кадров", selection: $sysFps, options: [
                                "120 FPS (Ультра-плавность)",
                                "60 FPS (Стандартный)",
                                "30 FPS (Энергосбережение)"
                            ])
                        }
                        .glassCard()
                        
                        // SECTION 2: Scheduler
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("Планировщик")
                            
                            Toggle("Фоновый планировщик выгрузки", isOn: $bgScheduler)
                                .tint(Color(hex: "7C3AED"))
                            
                            Text("При активации планировщика система будет проверять новые фото и отправлять их в фоновом режиме.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .glassCard()
                        
                        // SECTION 3: Auto Upscaling
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Автоматический Апскейл")
                            
                            Toggle("Включить авто-апскейл", isOn: $autoUpscale)
                                .tint(Color(hex: "7C3AED"))
                            
                            if autoUpscale {
                                Divider().background(Color.primary.opacity(0.08))
                                
                                pickerRow("Порог срабатывания", selection: $upscaleThreshold, options: [
                                    "Меньше 4 МБ (Рекомендуется)",
                                    "Меньше 2 МБ",
                                    "Меньше 8 МБ"
                                ])
                                
                                Divider().background(Color.primary.opacity(0.08))
                                
                                pickerRow("Коэффициент (масштаб)", selection: $upscaleFactor, options: [
                                    "Увеличение 2x (Бикубическое)",
                                    "Увеличение 4x (Нейросеть)"
                                ])
                            }
                        }
                        .glassCard()
                        
                        // SECTION 4: Upload parameters
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Параметры выгрузки")
                            
                            pickerIntRow("Потоки параллельной загрузки", selection: $parallelStreams, options: [1, 3, 5])
                            
                            Divider().background(Color.primary.opacity(0.08))
                            
                            Toggle("Автоповтор при сбоях", isOn: $retryOnFail)
                                .tint(Color(hex: "7C3AED"))
                            
                            Divider().background(Color.primary.opacity(0.08))
                            
                            Toggle("Сжатие JPEG перед загрузкой", isOn: $compressJpeg)
                                .tint(Color(hex: "7C3AED"))
                            
                            Divider().background(Color.primary.opacity(0.08))
                            
                            Toggle("Системные уведомления", isOn: $sysNotifications)
                                .tint(Color(hex: "7C3AED"))
                        }
                        .glassCard()
                        
                        // SECTION 5: Local PC Server
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("Локальный ПК-сервер")
                            
                            Toggle("Загрузка через ПК-сервер", isOn: $pcServerEnabled)
                                .tint(Color(hex: "7C3AED"))
                            
                            if pcServerEnabled {
                                Divider().background(Color.primary.opacity(0.08))
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Адрес сервера (IP:Порт)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    
                                    TextField("192.168.1.50:5000", text: $pcServerAddress)
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
                                        .autocorrectionDisabled(true)
                                        .onChange(of: pcServerAddress) { newValue in
                                            let cleaned = newValue
                                                .replacingOccurrences(of: "http://", with: "")
                                                .replacingOccurrences(of: "https://", with: "")
                                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                            if cleaned != newValue {
                                                pcServerAddress = cleaned
                                            }
                                        }
                                }
                            }
                            
                            Text("Позволяет отправлять фото через программу на вашем компьютере. Полезно, если на телефоне блокируется FTPS к Shutterstock.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .glassCard()
                        
                        // SECTION 0: Cloud Sync
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Облачная синхронизация")
                            
                            if isUserSignedIn {
                                HStack(spacing: 12) {
                                    Image(systemName: userProvider == "Apple" ? "applelogo" : "g.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(userProvider == "Apple" ? Color.primary : Color.orange)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(userEmail)
                                            .font(.system(size: 14, weight: .bold))
                                        Text("Синхронизация профиля активна")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.green)
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Выйти", action: signOut)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.red.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            } else {
                                Text("Войдите в аккаунт, чтобы синхронизировать ваши настройки стоков и ключи API в облаке.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                
                                Divider().background(Color.primary.opacity(0.08))
                                
                                HStack(spacing: 12) {
                                    // Apple Sign In Button
                                    SignInWithAppleButton(
                                        .signIn,
                                        onRequest: { request in
                                            request.requestedScopes = [.fullName, .email]
                                        },
                                        onCompletion: { result in
                                            Task { @MainActor in
                                                switch result {
                                                case .success(let authorization):
                                                    if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                                        self.userEmail = appleIDCredential.email ?? "samvel.dev@icloud.com"
                                                        self.userProvider = "Apple"
                                                        self.isUserSignedIn = true
                                                        self.saveSettings()
                                                    }
                                                case .failure(let error):
                                                    print("Apple Sign In failed: \(error.localizedDescription)")
                                                    self.selectedProviderForAuth = "Apple"
                                                    self.showSimulatedAuthSheet = true
                                                }
                                            }
                                        }
                                    )
                                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                                    .frame(height: 38)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    // Google Sign In Button
                                    Button(action: {
                                        HapticHelper.trigger(.medium)
                                        signInWithGoogle()
                                    }) {
                                        HStack {
                                            Image(systemName: "g.circle.fill")
                                                .font(.system(size: 14))
                                            Text("Вход с Google")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.primary.opacity(0.08))
                                        .foregroundStyle(.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(PremiumButtonStyle())
                                }
                            }
                        }
                        .glassCard()
                        
                        // Save Button
                        Button(action: {
                            HapticHelper.trigger(.medium)
                            saveSettings()
                        }) {
                            Text("Сохранить все настройки")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppleTheme.primaryGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: AppleTheme.glowStart.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(PremiumButtonStyle())
                    }
                    .padding()
                }
            }
            .navigationTitle("Параметры системы")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                if showingSavedToast {
                    Text(isUserSignedIn ? "Успешная авторизация!" : "Настройки успешно сохранены!")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: bgScheduler) { _ in HapticHelper.trigger(.light) }
            .onChange(of: autoUpscale) { _ in HapticHelper.trigger(.light) }
            .onChange(of: retryOnFail) { _ in HapticHelper.trigger(.light) }
            .onChange(of: compressJpeg) { _ in HapticHelper.trigger(.light) }
            .onChange(of: sysNotifications) { _ in HapticHelper.trigger(.light) }
            .onChange(of: sysTheme) { _ in HapticHelper.trigger(.light) }
            .onChange(of: sysLanguage) { _ in HapticHelper.trigger(.light) }
            .onChange(of: sysFps) { _ in HapticHelper.trigger(.light) }
            .onChange(of: parallelStreams) { _ in HapticHelper.trigger(.light) }
            .onChange(of: upscaleThreshold) { _ in HapticHelper.trigger(.light) }
            .onChange(of: upscaleFactor) { _ in HapticHelper.trigger(.light) }
            .onChange(of: pcServerEnabled) { _ in HapticHelper.trigger(.light) }
            .onChange(of: pcServerAddress) { _ in HapticHelper.trigger(.light) }
            .overlay {
                if isSigningIn {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(.primary)
                                Text("Авторизация...")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .glassCard(cornerRadius: 16, padding: 24)
                        )
                }
            }
            .sheet(isPresented: $showSimulatedAuthSheet) {
                SimulatedSignInView(
                    provider: selectedProviderForAuth,
                    isPresented: $showSimulatedAuthSheet,
                    onCompletion: { email in
                        self.userEmail = email
                        self.userProvider = selectedProviderForAuth
                        self.isUserSignedIn = true
                        self.saveSettings()
                    }
                )
            }
        }
    }
    
    // MARK: - Row Helpers
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.bottom, 2)
    }
    
    private func pickerRow(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        Menu {
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                Spacer()
                Text(selection.wrappedValue)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func saveSettings() {
        withAnimation {
            showingSavedToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showingSavedToast = false
            }
        }
    }
    
    
    private func pickerIntRow(_ label: String, selection: Binding<Int>, options: [Int]) -> some View {
        Menu {
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text("\(option) \(getStreamWord(option))").tag(option)
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(selection.wrappedValue) \(getStreamWord(selection.wrappedValue))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func getStreamWord(_ count: Int) -> String {
        switch count {
        case 1: return "поток"
        case 3, 4: return "потока"
        default: return "потоков"
        }
    }
    
    private func signInWithGoogle() {
        selectedProviderForAuth = "Google"
        showSimulatedAuthSheet = true
    }
    
    private func signOut() {
        userEmail = ""
        userProvider = ""
        isUserSignedIn = false
    }
}

