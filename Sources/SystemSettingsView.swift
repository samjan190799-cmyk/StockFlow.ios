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
    
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var showPaywall = false
    @State private var showingSavedToast = false
    @State private var savedToastMessage = ""
    @State private var showGoogleHelpSheet = false
    
    #if DEBUG
    // Секретный жест для тестировщиков (5 быстрых тапов по версии). Только в отладочной сборке:
    // в боевой скрытой функции бесплатного PRO нет (правило App Review 2.3.1 и потеря дохода).
    @State private var versionTapCount: Int = 0
    @State private var lastTapTime: Date = Date.distantPast
    @State private var showTesterPanel: Bool = StoreManager.shared.isTesterOverrideActive
    @State private var testerProEnabled: Bool = UserDefaults.standard.bool(forKey: "debug_tester_pro_mock_value")
    #endif

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Параметры системы".localized)
                .navigationBarTitleDisplayMode(.large)
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
                .sheet(isPresented: $showGoogleHelpSheet) {
                    GoogleOAuthHelpSheet()
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                }
        }
    }

    // MARK: - Контент (разбит на группы, чтобы не упираться в лимит ViewBuilder)

    private var mainContent: some View {
        AppScreen {
            primarySections
            secondarySections
            #if DEBUG
            if showTesterPanel {
                testerDebugSection
            }
            #endif
            versionFooterSection
        }
    }

    @ViewBuilder
    private var primarySections: some View {
        subscriptionSection
        interfaceSection
        googlePhotosSection
        schedulerSection
        upscaleSection
    }

    @ViewBuilder
    private var secondarySections: some View {
        uploadSection
        pcServerSection
        cacheSection
        supportSection
        disclaimerSection
    }

    // MARK: - Подписка

    @ViewBuilder
    private var subscriptionSection: some View {
        if storeManager.isProUser {
            Button {
                HapticHelper.trigger(.light)
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "crown.fill")
                            .font(.headline)
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("SmartStock PRO")
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            AppChip(text: "АКТИВЕН".localized, symbol: "checkmark.circle.fill", tone: .success)
                        }
                        Text("Все премиум-функции и безлимитный ИИ активны".localized)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .appCard()
            }
            .buttonStyle(.plain)
        } else {
            Button {
                HapticHelper.trigger(.medium)
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.20))
                        Image(systemName: "sparkles")
                            .font(.headline)
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Перейти на SmartStock PRO".localized)
                            .font(.headline)
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.leading)
                        Text("Безлимитный ИИ, 10+ стоков и автозагрузка".localized)
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppPalette.primaryGradient)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Уведомление об изменении настроек

    @ViewBuilder
    private var toastOverlay: some View {
        if showingSavedToast {
            Label {
                Text(savedToastMessage.localized)
                    .font(.footnote.weight(.semibold))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTone.success.foreground(colorScheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Интерфейс

    private var interfaceSection: some View {
        AppSection("Интерфейс и Оформление".localized, symbol: "paintbrush.fill") {
            AppPickerRow(
                title: "Язык приложения".localized,
                selection: $sysLanguage,
                options: ["Русский", "English", "Հայերեն"],
                label: { $0.localized }
            )

            AppDivider()

            AppPickerRow(
                title: "Тема оформления".localized,
                selection: $sysTheme,
                options: ["Темная", "Светлая", "Системная"],
                label: { $0.localized }
            )
        }
    }

    // MARK: - Google Фото

    private var googlePhotosSection: some View {
        AppSection("ОБЛАКО GOOGLE ФОТО".localized, symbol: "photo.stack.fill", tint: Color(hex: "4285F4")) {
            AppRow {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if googlePhotosManager.isAuthenticated {
                            Label("Подключено к Google Фото".localized, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTone.success.foreground(colorScheme))
                        } else {
                            Text("Не подключено".localized)
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(googlePhotosManager.isAuthenticated ? googlePhotosManager.userEmail : "Импорт видео и фото из архива Google Фото".localized)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if googlePhotosManager.isAuthenticated {
                        Button {
                            HapticHelper.trigger(.medium)
                            googlePhotosManager.signOut()
                            showToast("Выход из Google Фото выполнен".localized)
                        } label: {
                            Text("Выйти".localized)
                        }
                        .buttonStyle(.appDestructive)
                    } else {
                        Button {
                            HapticHelper.trigger(.medium)
                            Task {
                                await googlePhotosManager.signInWithGoogle()
                                if googlePhotosManager.isAuthenticated {
                                    showToast("Успешно подключено к Google Фото!".localized)
                                }
                            }
                        } label: {
                            if googlePhotosManager.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.white)
                            } else {
                                Text("Подключить".localized)
                            }
                        }
                        .buttonStyle(.appCapsule(tint: Color(hex: "4285F4")))
                        .disabled(googlePhotosManager.isLoading)
                    }
                }
            }

            // Результат попытки входа: раньше ошибка нигде не показывалась, и казалось, что кнопка не работает
            if !googlePhotosManager.isAuthenticated && !googlePhotosManager.statusMessage.isEmpty {
                AppDivider()

                AppRow {
                    Text(googlePhotosManager.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AppDivider()

            AppRow {
                VStack(alignment: .leading, spacing: 8) {
                    AppTextField(
                        title: "Google OAuth Client ID (необязательно)".localized,
                        placeholder: "Ваш Client ID из Google Cloud Console...".localized,
                        text: $customGoogleClientId,
                        monospaced: true
                    )

                    Text("Используется для прямого доступа к API Google Фото и Drive.".localized)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AppDivider()

            Button {
                HapticHelper.trigger(.light)
                showGoogleHelpSheet = true
            } label: {
                AppNavRowLabel(
                    symbol: "questionmark.circle.fill",
                    tint: Color(hex: "4285F4"),
                    title: "Инструкция".localized
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Планировщик

    private var schedulerSection: some View {
        AppSection("Автозагрузка папки (Планировщик)".localized, symbol: "clock.arrow.circlepath") {
            AppToggleRow(title: "Фоновый авто-сканер".localized, isOn: $bgScheduler)

            if bgScheduler {
                AppDivider()

                AppRow {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Папка для сканирования".localized)
                                .font(.body)
                            Text(folderName.isEmpty ? "Не выбрана".localized : folderName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Button {
                            HapticHelper.trigger(.light)
                            showFolderPicker = true
                        } label: {
                            Text(folderName.isEmpty ? "Выбрать".localized : "Изменить".localized)
                        }
                        .buttonStyle(.appCapsule)
                    }
                }

                AppDivider()

                AppPickerRow(
                    title: "Интервал проверки".localized,
                    selection: Binding(
                        get: { "\(schedulerIntervalHours) ч" },
                        set: { schedulerIntervalHours = Int($0.replacingOccurrences(of: " ч", with: "")) ?? 1 }
                    ),
                    options: ["1 ч", "2 ч", "4 ч", "8 ч", "12 ч", "24 ч"],
                    label: { $0.localized }
                )

                AppDivider()

                AppRow {
                    HStack {
                        Text("Последний запуск".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(lastRunText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                AppDivider()

                AppRow {
                    Button {
                        HapticHelper.trigger(.medium)
                        runSchedulerNow()
                    } label: {
                        HStack(spacing: 8) {
                            if isRunningScheduler {
                                ProgressView()
                                    .tint(Color.white)
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isRunningScheduler ? "Запуск проверки...".localized : "Запустить проверку сейчас".localized)
                        }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(isRunningScheduler || folderName.isEmpty)
                }
            }
        }
    }

    // MARK: - Апскейл

    private var upscaleSection: some View {
        AppSection("Автоматический Апскейл".localized, symbol: "wand.and.stars") {
            AppToggleRow(title: "Включить авто-апскейл".localized, isOn: $autoUpscale)

            if autoUpscale {
                AppDivider()

                AppPickerRow(
                    title: "Порог срабатывания".localized,
                    selection: $upscaleThreshold,
                    options: [
                        "Меньше 4 МБ (Рекомендуется)",
                        "Меньше 2 МБ",
                        "Меньше 8 МБ"
                    ],
                    label: { $0.localized }
                )

                AppDivider()

                AppPickerRow(
                    title: "Коэффициент (масштаб)".localized,
                    selection: $upscaleFactor,
                    options: [
                        "Увеличение 2x (Бикубическое)",
                        "Увеличение 4x (Нейросеть)"
                    ],
                    label: { $0.localized }
                )
            }
        }
    }

    // MARK: - Выгрузка

    private var uploadSection: some View {
        AppSection("Параметры выгрузки и очередность".localized, symbol: "arrow.up.forward.app.fill") {
            AppPickerRow(
                title: "Потоки параллельной загрузки".localized,
                selection: $parallelStreams,
                options: [1, 2, 3, 5],
                label: { "\($0) \(getStreamWord($0).localized)" }
            )

            AppDivider()

            AppToggleRow(
                title: "Загрузка видео по очереди (Строго 1 за 1)".localized,
                subtitle: "Видеофайлы отправляются строго по очереди один за другим без перегрева процессора.".localized,
                isOn: $seqVideo
            )

            AppDivider()

            AppToggleRow(
                title: "Загрузка фото по очереди".localized,
                subtitle: "Фотографии будут отправляться строго последовательно по одной.".localized,
                isOn: $seqPhoto
            )

            AppDivider()

            AppToggleRow(title: "Автоповтор при сбоях (3 попытки)".localized, isOn: $retryOnFail)

            AppDivider()

            AppToggleRow(title: "Сжатие JPEG перед загрузкой".localized, isOn: $compressJpeg)

            AppDivider()

            AppToggleRow(title: "Системные уведомления".localized, isOn: $sysNotifications)
        }
    }

    // MARK: - ПК-сервер

    private var pcServerSection: some View {
        AppSection(
            "Локальный ПК-сервер".localized,
            symbol: "server.rack",
            footer: "Позволяет отправлять фото через программу на вашем компьютере.".localized
        ) {
            AppToggleRow(title: "Загрузка через ПК-сервер".localized, isOn: $pcServerEnabled)

            if pcServerEnabled {
                AppDivider()

                AppRow {
                    AppTextField(
                        title: "Адрес сервера (IP:Порт)".localized,
                        placeholder: "192.168.1.50:5000",
                        text: $pcServerAddress,
                        monospaced: true
                    )
                }
            }
        }
    }

    // MARK: - Кэш

    private var cacheSection: some View {
        AppSection("Память и Очистка кэша".localized, symbol: "internaldrive.fill") {
            AppToggleRow(
                title: "Режим проводника (Прямая выгрузка без кэша)".localized,
                subtitle: "Приложение работает как прямой проводник: файлы отправляются без дублирования на диск телефона.".localized,
                isOn: $noCacheMode
            )

            AppDivider()

            AppRow {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Очистка остаточного кэша".localized)
                            .font(.body)
                        Text("Использовано диска: ".localized + String(format: "%.1f MB", cacheSizeMB))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button(action: clearCache) {
                        Label("Очистить".localized, systemImage: "trash")
                    }
                    .buttonStyle(.appDestructive)
                }
            }
        }
        .onAppear {
            calculateCacheSize()
        }
    }

    // MARK: - Поддержка

    private var supportSection: some View {
        AppSection(
            "Поддержка и связь с разработчиком".localized,
            symbol: "questionmark.circle.fill",
            footer: "Если у вас возникли вопросы, предложения или требуется помощь в настройке стоков, свяжитесь с нами напрямую:".localized
        ) {
            // Обращение на Email
            Link(destination: URL(string: "mailto:samjan190799@gmail.com?subject=SmartStock%20Support")!) {
                AppNavRowLabel(
                    symbol: "envelope.fill",
                    tint: AppPalette.accent,
                    title: "Написать в службу поддержки".localized,
                    subtitle: "samjan190799@gmail.com",
                    trailingSymbol: "arrow.up.right"
                )
            }
            .buttonStyle(.plain)

            AppDivider()

            // Официальный сайт поддержки
            Link(destination: URL(string: "https://samjan190799-cmyk.github.io/StockFlow.ios/support.html")!) {
                AppNavRowLabel(
                    symbol: "globe",
                    tint: AppPalette.violet,
                    title: "Сайт поддержки и база знаний (FAQ)".localized,
                    subtitle: "Руководства по FTP и ответы на частые вопросы".localized,
                    trailingSymbol: "arrow.up.right"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Правовая информация

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Правовая информация и конфиденциальность".localized)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(AppPalette.accentLight)
            }

            Text("SmartStock является независимым инструментом и не связан с Shutterstock, Adobe Stock, Getty Images, Depositphotos, Freepik, Alamy, Dreamstime, 123RF, Pond5 или Google.".localized)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Link("Политика конфиденциальности".localized, destination: URL(string: "https://samjan190799-cmyk.github.io/StockFlow.ios/privacy.html")!)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.accentLight)

                Link("Условия использования (EULA)".localized, destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.accentLight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // MARK: - Версия (в отладочной сборке 5 быстрых тапов открывают панель тестировщика)

    private var versionFooterSection: some View {
        Text("SmartStock v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.7") (Сборка \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "8"))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                #if DEBUG
                handleVersionTap()
                #endif
            }
    }

    #if DEBUG
    private func handleVersionTap() {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) > 1.5 {
            versionTapCount = 1
        } else {
            versionTapCount += 1
        }
        lastTapTime = now

        if versionTapCount >= 5 {
            versionTapCount = 0
            HapticHelper.notification(.warning)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showTesterPanel.toggle()
                testerProEnabled = storeManager.isProUser
            }
            if showTesterPanel {
                showToast("Режим тестирования активирован".localized)
            } else {
                showToast("Режим тестирования скрыт".localized)
            }
        } else {
            HapticHelper.trigger(.light)
        }
    }

    // MARK: - Панель тестировщика (скрыта, открывается 5 быстрыми тапами по версии)

    private var testerDebugSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label {
                    Text("Режим тестирования (QA)".localized)
                        .font(.subheadline.weight(.heavy))
                } icon: {
                    Image(systemName: "ladybug.fill")
                }
                .foregroundStyle(Color.orange)

                Spacer(minLength: 8)

                Text("TESTER OVERRIDE")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(Color.orange)
            }

            Text("Скрытая панель для тестировщиков. Позволяет проверять функции без реальной покупки в Sandbox.".localized)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(
                get: { self.testerProEnabled },
                set: { newValue in
                    self.testerProEnabled = newValue
                    storeManager.setTesterProOverride(active: true, isPro: newValue)
                    HapticHelper.trigger(.medium)
                    showToast(newValue ? "SmartStock PRO активирован (Тест)".localized : "SmartStock PRO выключен (Тест)".localized)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Эмуляция SmartStock PRO".localized)
                        .font(.subheadline.weight(.bold))
                    Text(testerProEnabled ? "Статус: PRO активен (безлимитные стоки, нет рекламы)".localized : "Статус: Базовый тариф (лимит 2 стока, реклама)".localized)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.orange)

            Button {
                HapticHelper.trigger(.medium)
                storeManager.setTesterProOverride(active: false, isPro: false)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showTesterPanel = false
                    testerProEnabled = storeManager.isProUser
                }
                showToast("Тестовый режим отключён, восстановлен реальный StoreKit".localized)
            } label: {
                Label("Сбросить на реальный StoreKit".localized, systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.appSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.45), lineWidth: 1)
        )
        .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
    }
    #endif

    // MARK: - Helpers

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
        return AppDateFormatters.shortDateTimeFormatter.string(from: date)
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
    
    private func showToast(_ message: String) {
        DispatchQueue.main.async {
            self.savedToastMessage = message
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.showingSavedToast = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeOut(duration: 0.3)) {
                    self.showingSavedToast = false
                }
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
                DispatchQueue.main.async {
                    showToast(msg)
                }
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
                DispatchQueue.main.async {
                    showToast(msg)
                }
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
                DispatchQueue.main.async {
                    showToast(msg)
                }
            }
            .onChange(of: parallelStreams) { newVal in
                HapticHelper.trigger(.light)
                let msg = "Параллельные потоки: ".localized + "\(newVal)"
                DispatchQueue.main.async {
                    showToast(msg)
                }
            }
            .onChange(of: seqVideo) { newVal in
                HapticHelper.trigger(.light)
                let msg = newVal
                    ? "Загрузка видео по очереди включена".localized
                    : "Загрузка видео по очереди отключена".localized
                DispatchQueue.main.async {
                    showToast(msg)
                }
            }
            .onChange(of: seqPhoto) { newVal in
                HapticHelper.trigger(.light)
                let msg = newVal
                    ? "Загрузка фото по очереди включена".localized
                    : "Загрузка фото по очереди отключена".localized
                DispatchQueue.main.async {
                    showToast(msg)
                }
            }
    }
}


