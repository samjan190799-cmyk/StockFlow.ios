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
    
    @AppStorage("sys_parallel_streams") private var parallelStreams: Int = 3
    @AppStorage("sys_retry_on_fail") private var retryOnFail: Bool = true
    @AppStorage("sys_compress_jpeg") private var compressJpeg: Bool = false
    @AppStorage("sys_notifications") private var sysNotifications: Bool = true
    
    // PC Server settings
    @AppStorage("sys_pc_server_enabled") private var pcServerEnabled: Bool = false
    @AppStorage("sys_pc_server_address") private var pcServerAddress: String = "192.168.1.50:5000"
    

    
    @State private var showFolderPicker = false
    @State private var isRunningScheduler = false
    
    @State private var showingSavedToast = false
    @State private var savedToastMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        interfaceSection
                        schedulerSection
                        upscaleSection
                        uploadSection
                        pcServerSection
                        saveButtonSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Параметры системы".localized)
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
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
            .onChange(of: sysLanguage) { newLang in
                HapticHelper.trigger(.light)
                let toastMsg: String
                if newLang == "English" {
                    toastMsg = "Language changed to English"
                } else if newLang == "Հայերեն" {
                    toastMsg = "Լեզուն փոխվեց Հայերենի"
                } else {
                    toastMsg = "Язык изменён на Русский"
                }
                showToast(toastMsg)
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
                showToast(newVal ? "Авто-апскейл включён — работает при добавлении фото" : "Авто-апскейл отключён")
            }
            .onChange(of: retryOnFail) { _ in HapticHelper.trigger(.light) }
            .onChange(of: compressJpeg) { _ in HapticHelper.trigger(.light) }
            .onChange(of: sysNotifications) { _ in HapticHelper.trigger(.light) }
            .onChange(of: parallelStreams) { newVal in
                HapticHelper.trigger(.light)
                showToast("Параллельные потоки: ".localized + "\(newVal)" + " — применится при следующей загрузке".localized)
            }
            .onChange(of: upscaleThreshold) { _ in HapticHelper.trigger(.light) }
            .onChange(of: upscaleFactor) { _ in HapticHelper.trigger(.light) }
            .onChange(of: pcServerEnabled) { _ in HapticHelper.trigger(.light) }
            .onChange(of: pcServerAddress) { _ in HapticHelper.trigger(.light) }
            .sheet(isPresented: $showFolderPicker) {
                FolderPicker { url in
                    do {
                        guard url.startAccessingSecurityScopedResource() else {
                            showToast("Не удалось получить доступ к папке".localized)
                            return
                        }
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                        UserDefaults.standard.set(bookmarkData, forKey: "sys_scheduler_folder_bookmark")
                        
                        self.folderName = url.lastPathComponent
                        
                        showToast("Папка успешно выбрана: ".localized + url.lastPathComponent)
                    } catch {
                        showToast("Ошибка сохранения папки: ".localized + error.localizedDescription)
                    }
                } onCancel: {
                    // Отмена
                }
            }
        }
    }
    
    // MARK: - Sections
    @ViewBuilder
    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Интерфейс".localized, icon: "paintpalette.fill")
            pickerRow("Язык интерфейса".localized, selection: $sysLanguage, options: ["Русский", "English", "Հայերեն"])
            Divider().background(Color.primary.opacity(0.08))
            pickerRow("Тема оформления".localized, selection: $sysTheme, options: ["Темная", "Светлая", "Системная"])
        }
        .glassCard()
    }
    
    @ViewBuilder
    private var schedulerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Планировщик".localized, icon: "clock.fill")
            Toggle("Фоновый планировщик выгрузки".localized, isOn: $bgScheduler)
                .tint(Color(hex: "007AFF"))
            
            if bgScheduler {
                Divider().background(Color.primary.opacity(0.08))
                
                Button(action: {
                    HapticHelper.trigger(.light)
                    showFolderPicker = true
                }) {
                    HStack {
                        Text("Папка для импорта".localized)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(folderName.isEmpty ? "Выбрать...".localized : folderName)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "007AFF"))
                    }
                }
                
                Divider().background(Color.primary.opacity(0.08))
                
                Menu {
                    Picker("", selection: $schedulerIntervalHours) {
                        ForEach([1, 2, 4, 8, 12, 24], id: \.self) { hr in
                            Text("Каждые".localized + " \(hr) " + getHoursWord(hr).localized).tag(hr)
                        }
                    }
                } label: {
                    HStack {
                        Text("Интервал проверки".localized)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("Каждые".localized + " \(schedulerIntervalHours) " + getHoursWord(schedulerIntervalHours).localized)
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
                .buttonStyle(.plain)
                
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
            
            Text("При активации планировщика система будет проверять новые фото в выбранной папке и отправлять их в фоновом режиме.".localized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
            sectionHeader("Параметры выгрузки".localized, icon: "arrow.up.forward.app.fill")
            pickerIntRow("Потоки параллельной загрузки".localized, selection: $parallelStreams, options: [1, 3, 5])
            Divider().background(Color.primary.opacity(0.08))
            Toggle("Автоповтор при сбоях".localized, isOn: $retryOnFail)
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
            
            Text("Позволяет отправлять фото через программу на вашем компьютере. Полезно, если на телефоне блокируется FTPS к Shutterstock.".localized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .glassCard()
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
    
    private func saveSettings() {
        showToast("Настройки успешно сохранены!")
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
    
    private func getHoursWord(_ count: Int) -> String {
        switch count {
        case 1: return "час"
        case 2, 3, 4: return "часа"
        default: return "часов"
        }
    }
    
    private func runSchedulerNow() {
        isRunningScheduler = true
        Task {
            await SchedulerManager.shared.runSchedulerUploadCycle()
            isRunningScheduler = false
            showToast("Проверка папки завершена!")
        }
    }
}

