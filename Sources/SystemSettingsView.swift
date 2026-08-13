import SwiftUI
import AuthenticationServices

@MainActor
struct SystemSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    
    // Left Column settings
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @AppStorage("sys_bg_scheduler") private var bgScheduler: Bool = false
    
    @AppStorage("sys_scheduler_folder_name") private var folderName: String = ""
    @AppStorage("sys_scheduler_interval_hours") private var schedulerIntervalHours: Int = 1
    @AppStorage("sys_scheduler_last_run") private var lastRunTimestamp: Double = 0.0
    
    // Right Column settings
    @AppStorage("sys_auto_upscale") private var autoUpscale: Bool = false
    @AppStorage("sys_upscale_threshold") private var upscaleThreshold: String = "Меньше 4 МБ (Рекомендуется)"
    @AppStorage("sys_upscale_factor") private var upscaleFactor: String = "Увеличение 2x (Бикубическое)"
    
    @AppStorage("sys_parallel_streams") private var parallelStreams: Int = 1
    @AppStorage("sys_seq_video") private var seqVideo: Bool = true
    @AppStorage("sys_seq_photo") private var seqPhoto: Bool = true
    @AppStorage("sys_retry_on_fail") private var retryOnFail: Bool = true
    @AppStorage("sys_compress_jpeg") private var compressJpeg: Bool = false
    @AppStorage("sys_notifications") private var sysNotifications: Bool = true
    @AppStorage("sys_no_cache_mode") private var noCacheMode: Bool = true
    
    // PC Server settings
    @AppStorage("sys_pc_server_enabled") private var pcServerEnabled: Bool = false
    @AppStorage("sys_pc_server_address") private var pcServerAddress: String = "192.168.1.50:5000"
    
    // Google OAuth Custom Client ID
    @AppStorage("google_oauth_client_id") private var customGoogleClientId: String = ""
    
    @ObservedObject private var googlePhotosManager = GooglePhotosManager.shared
    
    @State private var showFolderPicker = false
    @State private var isRunningScheduler = false
    @State private var cacheSizeMB: Double = 0.0
    
    @State private var showingSavedToast = false
    @State private var savedToastMessage = ""
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Параметры системы".localized)
                .navigationBarTitleDisplayMode(.inline)
                .overlay(alignment: .bottom) { toastOverlay }
                .modifier(SettingsObservers1(
                    sysLanguage: $sysLanguage,
                    bgScheduler: $bgScheduler,
                    schedulerIntervalHours: $schedulerIntervalHours,
                    autoUpscale: $autoUpscale,
                    showToast: { msg in self.showToast(msg) }
                ))
                .modifier(SettingsObservers2(
                    retryOnFail: $retryOnFail,
                    compressJpeg: $compressJpeg,
                    sysNotifications: $sysNotifications,
                    noCacheMode: $noCacheMode,
                    parallelStreams: $parallelStreams,
                    seqVideo: $seqVideo,
                    seqPhoto: $seqPhoto,
                    showToast: { msg in self.showToast(msg) }
                ))
                .sheet(isPresented: $showFolderPicker) {
                    FolderPicker { url in
                        do {
                            guard url.startAccessingSecurityScopedResource() else {
                                self.showToast("Не удалось получить доступ к папке".localized)
                                return
                            }
                            defer { url.stopAccessingSecurityScopedResource() }
                            let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                            UserDefaults.standard.set(bookmarkData, forKey: "sys_scheduler_folder_bookmark")
                            self.folderName = url.lastPathComponent
                            self.showToast("Папка успешно выбрана: ".localized + url.lastPathComponent)
                        } catch {
                            self.showToast("Ошибка сохранения папки: ".localized + error.localizedDescription)
                        }
                    } onCancel: {}
                }
        }
    }

    // MARK: - Выделенный контент (избегаем перегрузки компилятора в body)

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            LiquidBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    interfaceSection
                    googlePhotosSection
                    schedulerSection
                    upscaleSection
                    uploadSection
                    pcServerSection
                    cacheSection
                    disclaimerSection
                    saveButtonSection
                    versionFooterSection
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if showingSavedToast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Text(savedToastMessage.localized)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color(hex: "2C2C2E") : Color(hex: "E5E5EA"))
            .foregroundStyle(.primary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    
    // MARK: - Sections
    
    @ViewBuilder
    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Интерфейс и Оформление".localized, icon: "paintbrush.fill")
            pickerRow("Язык приложения".localized, selection: $sysLanguage, options: ["Русский", "English", "Հայերեն"])
            Divider().background(Color.primary.opacity(0.08))
            pickerRow("Тема оформления".localized, selection: $sysTheme, options: ["Темная", "Светлая", "Системная"])
        }
        .glassCard()
    }
    
    @ViewBuilder
    private var googlePhotosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ОБЛАКО GOOGLE ФОТО".localized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "4285F4"))
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(googlePhotosManager.isAuthenticated ? "Подключено к Google Фото".localized : "Не подключено".localized)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(googlePhotosManager.isAuthenticated ? .green : .primary)
                    
                    Text(googlePhotosManager.isAuthenticated ? googlePhotosManager.userEmail : "Импорт видео и фото из архива Google Фото".localized)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                if googlePhotosManager.isAuthenticated {
                    Button(action: {
                        HapticHelper.trigger(.medium)
                        googlePhotosManager.signOut()
                        showToast("Выход из Google Фото выполнен".localized)
                    }) {
                        Text("Выйти".localized)
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                } else {
                    Button(action: {
                        HapticHelper.trigger(.medium)
                        Task {
                            await googlePhotosManager.signInWithGoogle()
                            if googlePhotosManager.isAuthenticated {
                                showToast("Успешно подключено к Google Фото!".localized)
                            }
                        }
                    }) {
                        Text("Подключить".localized)
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hex: "4285F4"))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .glassCard()
    }
    
    @ViewBuilder
    private var schedulerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Автозагрузка папки (Планировщик)".localized, icon: "clock.arrow.circlepath")
            Toggle("Фоновый авто-сканер".localized, isOn: $bgScheduler)
                .tint(Color(hex: "007AFF"))
            
            if bgScheduler {
                Divider().background(Color.primary.opacity(0.08))
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Папка для сканирования".localized)
                            .font(.system(size: 14))
                        Text(folderName.isEmpty ? "Не выбрана".localized : folderName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        HapticHelper.trigger(.light)
                        showFolderPicker = true
                    }) {
                        Text(folderName.isEmpty ? "Выбрать".localized : "Изменить".localized)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "007AFF"))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                
                Divider().background(Color.primary.opacity(0.08))
                
                pickerRow("Интервал проверки".localized, selection: Binding(
                    get: { "\(schedulerIntervalHours) ч" },
                    set: { schedulerIntervalHours = Int($0.replacingOccurrences(of: " ч", with: "")) ?? 1 }
                ), options: ["1 ч", "2 ч", "4 ч", "8 ч", "12 ч", "24 ч"])
                
                Divider().background(Color.primary.opacity(0.08))
                
                HStack {
                    Text("Последний запуск".localized)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lastRunText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Divider().background(Color.primary.opacity(0.08))
                
                Button(action: {
                    HapticHelper.trigger(.medium)
                    runSchedulerNow()
                }) {
                    HStack {
                        if isRunningScheduler {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                                .padding(.trailing, 6)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                        }
                        Text(isRunningScheduler ? "Запуск проверки...".localized : "Запустить проверку сейчас".localized)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppleTheme.primaryGradient.opacity(isRunningScheduler ? 0.6 : 1.0))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isRunningScheduler || folderName.isEmpty)
            }
        }
        .glassCard()
    }
    
    @ViewBuilder
    private var upscaleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Автоматический Апскейл".localized, icon: "wand.and.stars")
            Toggle("Включить авто-апскейл".localized, isOn: $autoUpscale)
                .tint(Color(hex: "007AFF"))
            
            if autoUpscale {
                Divider().background(Color.primary.opacity(0.08))
                pickerRow("Порог срабатывания".localized, selection: $upscaleThreshold, options: [
                    "Меньше 4 МБ (Рекомендуется)",
                    "Меньше 2 МБ",
                    "Меньше 8 МБ"
                ])
                Divider().background(Color.primary.opacity(0.08))
                pickerRow("Коэффициент (масштаб)".localized, selection: $upscaleFactor, options: [
                    "Увеличение 2x (Бикубическое)",
                    "Увеличение 4x (Нейросеть)"
                ])
            }
        }
        .glassCard()
    }
    
    @ViewBuilder
    private var uploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Параметры выгрузки и очередность".localized, icon: "arrow.up.forward.app.fill")
            pickerIntRow("Потоки параллельной загрузки".localized, selection: $parallelStreams, options: [1, 2, 3, 5])
            Divider().background(Color.primary.opacity(0.08))
            
            Toggle("Загрузка видео по очереди (Строго 1 за 1)".localized, isOn: $seqVideo)
                .tint(Color(hex: "007AFF"))
            Text("Видеофайлы отправляются строго по очереди один за другим без перегрева процессора.".localized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            Divider().background(Color.primary.opacity(0.08))
            
            Toggle("Загрузка фото по очереди".localized, isOn: $seqPhoto)
                .tint(Color(hex: "007AFF"))
            Text("Фотографии будут отправляться строго последовательно по одной.".localized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            Divider().background(Color.primary.opacity(0.08))
            Toggle("Автоповтор при сбоях (3 попытки)".localized, isOn: $retryOnFail)
                .tint(Color(hex: "007AFF"))
            Divider().background(Color.primary.opacity(0.08))
            Toggle("Сжатие JPEG перед загрузкой".localized, isOn: $compressJpeg)
                .tint(Color(hex: "007AFF"))
            Divider().background(Color.primary.opacity(0.08))
            Toggle("Системные уведомления".localized, isOn: $sysNotifications)
                .tint(Color(hex: "007AFF"))
        }
        .glassCard()
    }
    
    @ViewBuilder
    private var pcServerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Локальный ПК-сервер".localized, icon: "server.rack")
            Toggle("Загрузка через ПК-сервер".localized, isOn: $pcServerEnabled)
                .tint(Color(hex: "007AFF"))
            
            if pcServerEnabled {
                Divider().background(Color.primary.opacity(0.08))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Адрес сервера (IP:Порт)".localized)
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
                }
            }
            
            Text("Позволяет отправлять фото через программу на вашем компьютере.".localized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }
    
    @ViewBuilder
    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Память и Очистка кэша".localized, icon: "internaldrive.fill")
            
            Toggle("Режим проводника (Прямая выгрузка без кэша)".localized, isOn: $noCacheMode)
                .tint(Color(hex: "007AFF"))
            Text("Приложение работает как прямой проводник: файлы отправляются без дублирования на диск телефона.".localized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            Divider().background(Color.primary.opacity(0.08))
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Очистка остаточного кэша".localized)
                        .font(.system(size: 14, weight: .medium))
                    Text("Использовано диска: ".localized + String(format: "%.1f MB", cacheSizeMB))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                Button(action: clearCache) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Очистить".localized)
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(Capsule())
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 16)
        .onAppear {
            calculateCacheSize()
        }
    }
    
    @ViewBuilder
    private var saveButtonSection: some View {
        Button(action: {
            HapticHelper.trigger(.medium)
            saveSettings()
        }) {
            Text("Сохранить все настройки".localized)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppleTheme.primaryGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .ambientShadow(radius: 8)
        }
        .buttonStyle(PremiumButtonStyle())
    }
    
    @ViewBuilder
    private var versionFooterSection: some View {
        HStack {
            Spacer()
            Text("SmartStock v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.6") (Сборка \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

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
            
            Text("SmartStock является независимым инструментом и не связан с Shutterstock, Adobe Stock, Getty Images, Depositphotos, Freepik, Alamy, Dreamstime, 123RF, Pond5 или Google.".localized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .glassCard(cornerRadius: 16, padding: 16)
    }
    
    // MARK: - Row Helpers
    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: "007AFF").opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "007AFF"))
            }
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 2)
    }
    
    private func pickerRow(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(action: {
                        HapticHelper.selection()
                        selection.wrappedValue = option
                    }) {
                        HStack {
                            Text(option.localized)
                            if selection.wrappedValue == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.wrappedValue.localized)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: "007AFF"))
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
    }
    
    private func pickerIntRow(_ label: String, selection: Binding<Int>, options: [Int]) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(action: {
                        HapticHelper.selection()
                        selection.wrappedValue = option
                    }) {
                        HStack {
                            Text("\(option) \(getStreamWord(option).localized)")
                            if selection.wrappedValue == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(selection.wrappedValue) \(getStreamWord(selection.wrappedValue).localized)")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: "007AFF"))
                .foregroundStyle(.white)
                .clipShape(Capsule())
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
    
    private var lastRunText: String {
        if lastRunTimestamp == 0 {
            return "Еще не запускался".localized
        }
        let date = Date(timeIntervalSince1970: lastRunTimestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func runSchedulerNow() {
        isRunningScheduler = true
        Task {
            await SchedulerManager.shared.runSchedulerUploadCycle()
            isRunningScheduler = false
            showToast("Проверка папки завершена!".localized)
        }
    }
    
    private func calculateCacheSize() {
        let photosDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos")
        guard let files = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        
        var totalBytes: Int64 = 0
        for file in files {
            if let res = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = res.fileSize {
                totalBytes += Int64(size)
            }
        }
        
        self.cacheSizeMB = Double(totalBytes) / (1024.0 * 1024.0)
    }
    
    private func clearCache() {
        HapticHelper.trigger(.medium)
        ImageCacheHelper.shared.clearCache()
        
        let photosDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos")
        if let files = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
        
        calculateCacheSize()
        showToast("Кэш скачанных медиафайлов очищен!".localized)
    }
    
    private func saveSettings() {
        showToast("Настройки успешно сохранены!".localized)
    }

    private func showToast(_ message: String) {
        savedToastMessage = message
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingSavedToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                showingSavedToast = false
            }
        }
    }
}

// MARK: - ViewModifiers для onChange (Swift 6: разбиваем type-check на независимые блоки)

@MainActor
struct SettingsObservers1: ViewModifier {
    @Binding var sysLanguage: String
    @Binding var bgScheduler: Bool
    @Binding var schedulerIntervalHours: Int
    @Binding var autoUpscale: Bool
    let showToast: @MainActor (String) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: sysLanguage) { newLang in
                HapticHelper.trigger(.light)
                let msg: String
                if newLang == "English" {
                    msg = "Language changed to English"
                } else if newLang == "Հայերեն" {
                    msg = "Լեզուն փոխվեց Հայերենի"
                } else {
                    msg = "Язык изменён на Русский"
                }
                showToast(msg)
            }
            .onChange(of: bgScheduler) { newVal in
                HapticHelper.trigger(.light)
                SchedulerManager.shared.setSchedulerEnabled(newVal)
            }
            .onChange(of: schedulerIntervalHours) { _ in
                HapticHelper.trigger(.light)
                if bgScheduler {
                    SchedulerManager.shared.scheduleNextBackgroundTask()
                }
            }
            .onChange(of: autoUpscale) { newVal in
                HapticHelper.trigger(.light)
                let msg = newVal
                    ? "Авто-апскейл включён — работает при добавлении фото".localized
                    : "Авто-апскейл отключён".localized
                showToast(msg)
            }
    }
}

@MainActor
struct SettingsObservers2: ViewModifier {
    @Binding var retryOnFail: Bool
    @Binding var compressJpeg: Bool
    @Binding var sysNotifications: Bool
    @Binding var noCacheMode: Bool
    @Binding var parallelStreams: Int
    @Binding var seqVideo: Bool
    @Binding var seqPhoto: Bool
    let showToast: @MainActor (String) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: retryOnFail) { _ in HapticHelper.trigger(.light) }
            .onChange(of: compressJpeg) { _ in HapticHelper.trigger(.light) }
            .onChange(of: sysNotifications) { _ in HapticHelper.trigger(.light) }
            .onChange(of: noCacheMode) { newVal in
                HapticHelper.trigger(.light)
                let msg = newVal
                    ? "Режим проводника активен: 0 МБ кэша".localized
                    : "Кэширование включено".localized
                showToast(msg)
            }
            .onChange(of: parallelStreams) { newVal in
                HapticHelper.trigger(.light)
                let msg = "Параллельные потоки: ".localized + "\(newVal)"
                showToast(msg)
            }
            .onChange(of: seqVideo) { newVal in
                HapticHelper.trigger(.light)
                let msg = newVal
                    ? "Загрузка видео по очереди включена".localized
                    : "Загрузка видео по очереди отключена".localized
                showToast(msg)
            }
            .onChange(of: seqPhoto) { newVal in
                HapticHelper.trigger(.light)
                let msg = newVal
                    ? "Загрузка фото по очереди включена".localized
                    : "Загрузка фото по очереди отключена".localized
                showToast(msg)
            }
    }
}


