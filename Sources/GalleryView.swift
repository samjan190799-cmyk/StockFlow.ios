import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Главный экран: сетка, этапы, контекстная панель
// iPhone: чипы этапов + сетка, детали в шите.
// iPad в портрете: то же, сетка шире.
// iPad в альбомной ориентации: колонка этапов + сетка + панель деталей.
@MainActor
struct GalleryView: View {
    @ObservedObject var viewModel: QueueViewModel
    @ObservedObject private var storeManager = StoreManager.shared
    @ObservedObject private var rewardManager = RewardAdManager.shared
    @AppStorage("sys_notifications") private var sysNotifications: Bool = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var stage: GalleryStage = .all
    @State private var mediaTab: Int = 0
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedIds = Set<UUID>()
    @State private var focusedId: UUID? = nil
    @State private var detailPhoto: PhotoMetadata? = nil
    @State private var showPaywall = false
    @State private var showLogViewer = false
    @State private var showPhotosPicker = false
    @State private var showGooglePicker = false
    @State private var showFileImporter = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var confirmDelete = false
    @State private var showDuplicates = false

    private enum LayoutMode {
        case compact
        case medium
        case wide
    }

    private func layoutMode(for width: CGFloat) -> LayoutMode {
        guard sizeClass == .regular else { return .compact }
        return width >= 980 ? .wide : .medium
    }

    // MARK: Данные

    /// Файлы выбранной вкладки (фото/видео) с учётом поиска — по ним считаются этапы.
    private var scopedPhotos: [PhotoMetadata] {
        let wantVideo = mediaTab == 1
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return viewModel.photos.filter { photo in
            guard photo.isVideo == wantVideo else { return false }
            if query.isEmpty { return true }
            return photo.filename.localizedCaseInsensitiveContains(query)
                || photo.title.localizedCaseInsensitiveContains(query)
                || photo.keywords.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private var visiblePhotos: [PhotoMetadata] {
        scopedPhotos.filter { stage.includes($0.status) }
    }

    // MARK: Корневая разметка

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let mode = layoutMode(for: geo.size.width)
                ZStack {
                    LiquidBackgroundView()
                    if viewModel.photos.isEmpty {
                        emptyState
                    } else {
                        content(mode: mode)
                    }
                }
                .overlay(alignment: .bottom) { toast }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .top, spacing: 0) {
                AdBannerView()
            }
            #if DEBUG
            .task {
                await ScreenshotScenario.run(
                    viewModel: viewModel,
                    focus: { focusedId = $0.id },
                    openDetail: { detailPhoto = $0 }
                )
            }
            #endif
            .sheet(item: $detailPhoto) { photo in
                PhotoDetailSheet(photo: photo, viewModel: viewModel)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showLogViewer) {
                LogViewer()
            }
            .sheet(isPresented: $showDuplicates) {
                DuplicatesView(viewModel: viewModel)
            }
            .sheet(isPresented: $showGooglePicker) {
                GooglePhotosPickerView { items in
                    viewModel.addGoogleMediaItems(items)
                }
            }
            .photosPicker(
                isPresented: $showPhotosPicker,
                selection: $pickerItems,
                maxSelectionCount: 50,
                matching: mediaTab == 0 ? .images : .videos,
                photoLibrary: .shared()
            )
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: mediaTab == 0 ? [.image] : [.movie, .video],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    viewModel.addLocalFiles(urls)
                case .failure(let error):
                    viewModel.triggerToast("Ошибка выбора файлов: \(error.localizedDescription)")
                }
            }
            .onChange(of: pickerItems) { items in
                guard !items.isEmpty else { return }
                HapticHelper.trigger(.medium)
                viewModel.importPickerItems(items)
                pickerItems = []
            }
            .onChange(of: mediaTab) { _ in
                selectedIds.removeAll()
            }
            .onChange(of: viewModel.shouldShowPaywallFromLimit) { show in
                if show {
                    showPaywall = true
                    viewModel.shouldShowPaywallFromLimit = false
                }
            }
            .alert("Дневной лимит исчерпан".localized, isPresented: $viewModel.shouldShowDailyLimitAlert) {
                Button("👑 SmartStock PRO".localized) {
                    showPaywall = true
                }
                if AdManager.shared.canOfferRewarded {
                    Button("\("Смотреть рекламу".localized) (+\(AdConfig.rewardCredits))") {
                        watchRewardedAd()
                    }
                }
                Button("Закрыть".localized, role: .cancel) {}
            } message: {
                Text("В бесплатной версии доступно 15 ИИ-анализов и 15 отправок на стоки в день. Вы можете перейти на безлимитный PRO.".localized)
            }
            .confirmationDialog(
                "Удалить выбранные файлы?".localized,
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Удалить".localized, role: .destructive) {
                    deleteSelected()
                }
                Button("Отмена".localized, role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func content(mode: LayoutMode) -> some View {
        let counts = GalleryCounts(scopedPhotos)
        switch mode {
        case .wide:
            HStack(spacing: 0) {
                GallerySidebar(selection: $stage, counts: counts) {
                    showPaywall = true
                }
                .frame(width: 232)
                Divider()
                mainColumn(counts: counts, showChips: false, mode: mode)
                Divider()
                inspector
                    .frame(width: 340)
            }
        case .compact, .medium:
            mainColumn(counts: counts, showChips: true, mode: mode)
        }
    }

    private func mainColumn(counts: GalleryCounts, showChips: Bool, mode: LayoutMode) -> some View {
        VStack(spacing: 0) {
            headerControls(counts: counts, showChips: showChips)
            photoGrid(mode: mode)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
    }

    // MARK: Верхняя часть: тип файлов, лента этапов, чипы

    private var queueTitle: String {
        isSelecting ? "\("Выбрано".localized) \(selectedIds.count)" : "Очередь".localized
    }

    private func headerControls(counts: GalleryCounts, showChips: Bool) -> some View {
        VStack(spacing: 10) {
            ScreenLargeTitle(text: queueTitle)
                .padding(.horizontal, 16)

            ScreenSearchField(text: $searchText, prompt: "Поиск по названию и ключам".localized)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Text("\(mediaTab == 0 ? "Фото".localized : "Видео".localized) · \(counts.total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Picker("Тип файлов".localized, selection: $mediaTab) {
                    Text("Фото".localized).tag(0)
                    Text("Видео".localized).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            .padding(.horizontal, 16)

            if viewModel.photos.contains(where: { $0.isDemo }) {
                demoBanner
                    .padding(.horizontal, 16)
            }

            GalleryPipelineBar(counts: counts)
                .padding(.horizontal, 16)

            if showChips {
                GalleryStageChips(selection: $stage, counts: counts)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: Реклама за бонусные действия

    private func watchRewardedAd() {
        viewModel.triggerToast("Загружаю рекламу…".localized)
        AdManager.shared.showRewardedAd(
            onReward: {
                RewardAdManager.shared.grantBonus(AdConfig.rewardCredits)
                viewModel.triggerToast("+\(AdConfig.rewardCredits) " + "бонусных действий".localized)
                HapticHelper.notification(.success)
            },
            onFailure: { message in
                viewModel.triggerToast(message)
            }
        )
    }

    // MARK: Демо-режим

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.rectangle.fill")
                .foregroundStyle(GalleryPalette.amber)
            Text("Демо-режим: файлы никуда не отправляются.".localized)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Убрать демо".localized) {
                viewModel.removeDemoFiles()
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    // MARK: Сетка

    private func photoGrid(mode: LayoutMode) -> some View {
        let photos = visiblePhotos
        return ScrollView {
            if photos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("На этом этапе файлов нет".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110, maximum: 220), spacing: 4)],
                    spacing: 4
                ) {
                    ForEach(photos) { photo in
                        GalleryTile(
                            photo: photo,
                            isSelecting: isSelecting,
                            isSelected: selectedIds.contains(photo.id),
                            isFocused: mode == .wide && focusedId == photo.id
                        )
                        .onTapGesture {
                            handleTap(photo, mode: mode)
                        }
                        .contextMenu {
                            tileMenu(for: photo)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func tileMenu(for photo: PhotoMetadata) -> some View {
        Button {
            viewModel.runAIForPhoto(photo.id)
        } label: {
            Label("ИИ-анализ".localized, systemImage: "sparkles")
        }
        Button {
            viewModel.uploadPhoto(photo.id)
        } label: {
            Label("Отправить".localized, systemImage: "paperplane")
        }
        Button {
            startSelecting(with: photo.id)
        } label: {
            Label("Выбрать".localized, systemImage: "checkmark.circle")
        }
        Button(role: .destructive) {
            viewModel.removePhoto(photo.id)
        } label: {
            Label("Удалить".localized, systemImage: "trash")
        }
    }

    private func handleTap(_ photo: PhotoMetadata, mode: LayoutMode) {
        HapticHelper.selection()
        if isSelecting {
            if selectedIds.contains(photo.id) {
                selectedIds.remove(photo.id)
            } else {
                selectedIds.insert(photo.id)
            }
            return
        }
        if mode == .wide {
            focusedId = photo.id
        } else {
            detailPhoto = photo
        }
    }

    // MARK: Режим выбора

    private func startSelecting(with id: UUID? = nil) {
        isSelecting = true
        if let id {
            selectedIds = [id]
        } else {
            selectedIds = []
        }
    }

    private func endSelecting() {
        isSelecting = false
        selectedIds.removeAll()
    }

    private func selectAllVisible() {
        selectedIds = Set(visiblePhotos.map { $0.id })
    }

    private func runAIForSelected() {
        let ids = Array(selectedIds)
        for id in ids {
            viewModel.runAIForPhoto(id)
        }
        endSelecting()
    }

    private func sendSelected() {
        let ids = Array(selectedIds)
        for id in ids {
            viewModel.uploadPhoto(id)
        }
        endSelecting()
    }

    private func deleteSelected() {
        let ids = Array(selectedIds)
        for id in ids {
            viewModel.removePhoto(id)
            if focusedId == id { focusedId = nil }
        }
        endSelecting()
    }

    // MARK: Нижняя панель

    private var actionBar: some View {
        GalleryActionBar(
            isSelecting: isSelecting,
            selectedCount: selectedIds.count,
            aiCount: viewModel.photos.filter { $0.status == .new || $0.status == .error }.count,
            sendCount: viewModel.photos.filter { $0.status == .ready }.count,
            isAutopilotRunning: viewModel.isRunningAutopilot,
            isAnalyzing: viewModel.isAnalyzingAll,
            onAutopilot: { viewModel.runAutopilotPipeline() },
            onAIAll: { viewModel.runAIForAll() },
            onSendAll: { viewModel.uploadAllReady() },
            onAISelected: { runAIForSelected() },
            onSendSelected: { sendSelected() },
            onDeleteSelected: { confirmDelete = true }
        )
    }

    // MARK: Панель деталей (iPad, альбомная)

    private var inspector: some View {
        Group {
            if let id = focusedId, viewModel.photos.contains(where: { $0.id == id }) {
                GalleryInspector(photoId: id, viewModel: viewModel)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Выберите снимок".localized)
                        .font(.headline)
                    Text("Здесь появятся заголовок, ключевые слова и стоки для отправки.".localized)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    // MARK: Пустая очередь

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenLargeTitle(text: queueTitle)
                    .padding(.horizontal, 16)
                emptyStateContent
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var emptyStateContent: some View {
        VStack(spacing: 16) {
            SmartStockLogoView(size: 72)
            Text("Очередь пуста".localized)
                .font(.title3.weight(.bold))
            Text("Выберите снимки, чтобы запустить ИИ-подбор метаданных и отправить их на микростоки.".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            addMenu {
                Label("Добавить".localized, systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(GalleryPalette.primaryGradient))
            }

            onboardingCard

            VStack(spacing: 6) {
                Button {
                    HapticHelper.trigger(.medium)
                    viewModel.addDemoFiles()
                } label: {
                    SwiftUI.Label("Попробовать демо".localized, systemImage: "play.circle")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Примеры файлов без аккаунтов и ключей: ИИ-анализ и отправка имитируются.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: 420)
    }

    // MARK: Вводная карточка: путь от первого запуска до первой отправки

    private var onboardingCard: some View {
        let stockReady = viewModel.hasConfiguredStock
        return VStack(alignment: .leading, spacing: 12) {
            Text("Как это работает".localized)
                .font(.subheadline.weight(.bold))
            onboardingStep(
                number: 1,
                title: "Подключите сток".localized,
                detail: stockReady
                    ? "Готово: логин и пароль сохранены".localized
                    : "Логин и пароль от FTP вашего стока".localized,
                done: stockReady,
                actionTitle: stockReady ? nil : "Открыть".localized
            ) {
                AppRouter.shared.selectedTab = .agencies
            }
            onboardingStep(
                number: 2,
                title: "Добавьте фото или видео".localized,
                detail: "Из галереи, Google Фото или Файлов".localized,
                done: false,
                actionTitle: nil,
                action: {}
            )
            onboardingStep(
                number: 3,
                title: "ИИ заполнит метаданные".localized,
                detail: "Название, описание, ключевые слова и категории".localized,
                done: false,
                actionTitle: nil,
                action: {}
            )
            onboardingStep(
                number: 4,
                title: "Отправьте на сток".localized,
                detail: "Одним нажатием, с прогрессом по каждому файлу".localized,
                done: false,
                actionTitle: nil,
                action: {}
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, padding: 14)
    }

    private func onboardingStep(
        number: Int,
        title: String,
        detail: String,
        done: Bool,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? GalleryPalette.green : GalleryPalette.accent.opacity(0.16))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.white)
                } else {
                    Text("\(number)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(GalleryPalette.accent)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle) {
                    HapticHelper.selection()
                    action()
                }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Тост

    @ViewBuilder
    private var toast: some View {
        if viewModel.showToast {
            Text(viewModel.toastMessage)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.horizontal, 24)
                .padding(.bottom, viewModel.photos.isEmpty ? 24 : 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    // MARK: Тулбар

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if isSelecting {
                Button("Отмена".localized) {
                    endSelecting()
                }
            } else {
                limitsPill
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if isSelecting {
                Button("Выбрать все".localized) {
                    selectAllVisible()
                }
                moreMenu
            } else {
                if !viewModel.photos.isEmpty {
                    Button("Выбрать".localized) {
                        startSelecting()
                    }
                }
                addMenu {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(GalleryPalette.accent)
                        .accessibilityLabel("Добавить файлы".localized)
                }
                moreMenu
            }
        }
    }

    private var limitsPill: some View {
        Button {
            HapticHelper.trigger(.light)
            showPaywall = true
        } label: {
            HStack(spacing: 6) {
                if storeManager.isProUser {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Color.yellow)
                    Text("PRO")
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(GalleryPalette.amber)
                    Text("\(rewardManager.remainingAIToday)")
                        .monospacedDigit()
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(GalleryPalette.blue)
                    Text("\(rewardManager.remainingUploadsToday)")
                        .monospacedDigit()
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            storeManager.isProUser
                ? "PRO Безлимит".localized
                : "\("ИИ".localized) \(rewardManager.remainingAIToday), \("Отправки".localized) \(rewardManager.remainingUploadsToday)"
        )
    }

    private func addMenu<LabelContent: View>(@ViewBuilder label: @escaping () -> LabelContent) -> some View {
        Menu {
            Button {
                HapticHelper.trigger(.medium)
                showPhotosPicker = true
            } label: {
                SwiftUI.Label("Галерея iOS".localized, systemImage: "photo.on.rectangle")
            }
            Button {
                HapticHelper.trigger(.medium)
                if storeManager.isProUser {
                    showGooglePicker = true
                } else {
                    showPaywall = true
                }
            } label: {
                SwiftUI.Label(
                    storeManager.isProUser ? "Google Фото".localized : "Google Фото · PRO".localized,
                    systemImage: storeManager.isProUser ? "photo.stack.fill" : "lock.fill"
                )
            }
            Button {
                HapticHelper.trigger(.medium)
                showFileImporter = true
            } label: {
                SwiftUI.Label("Файлы на устройстве".localized, systemImage: "folder.badge.plus")
            }
        } label: {
            label()
        }
    }

    private var moreMenu: some View {
        let exportIds: Set<UUID>? = (isSelecting && !selectedIds.isEmpty) ? selectedIds : nil
        return Menu {
            if !viewModel.photos.isEmpty {
                ShareLink(
                    item: CSVDocument(csvText: viewModel.generateShutterstockCSV(forIds: exportIds)),
                    preview: SharePreview("shutterstock_metadata.csv", image: Image(systemName: "tablecells"))
                ) {
                    SwiftUI.Label("Shutterstock CSV", systemImage: "s.circle.fill")
                }
                ShareLink(
                    item: CSVDocument(csvText: viewModel.generateAdobeStockCSV(forIds: exportIds)),
                    preview: SharePreview("adobe_stock_metadata.csv", image: Image(systemName: "tablecells"))
                ) {
                    SwiftUI.Label("Adobe Stock CSV", systemImage: "a.circle.fill")
                }
                ShareLink(
                    item: CSVDocument(csvText: viewModel.generatePond5CSV(forIds: exportIds)),
                    preview: SharePreview("pond5_metadata.csv", image: Image(systemName: "tablecells"))
                ) {
                    SwiftUI.Label("Pond5 CSV", systemImage: "p.circle.fill")
                }
                ShareLink(
                    item: CSVDocument(csvText: viewModel.generateDreamstimeCSV(forIds: exportIds)),
                    preview: SharePreview("dreamstime_metadata.csv", image: Image(systemName: "tablecells"))
                ) {
                    SwiftUI.Label("Dreamstime CSV", systemImage: "d.circle.fill")
                }
            }
            if viewModel.photos.count > 1 {
                Button {
                    showDuplicates = true
                } label: {
                    SwiftUI.Label("Найти дубли".localized, systemImage: "square.on.square")
                }
            }
            if viewModel.photos.contains(where: { $0.isDemo }) {
                Button(role: .destructive) {
                    viewModel.removeDemoFiles()
                } label: {
                    SwiftUI.Label("Убрать демо-файлы".localized, systemImage: "xmark.bin")
                }
            } else {
                Button {
                    viewModel.addDemoFiles()
                } label: {
                    SwiftUI.Label("Демо-режим: добавить примеры".localized, systemImage: "play.circle")
                }
            }
            Button {
                showLogViewer = true
            } label: {
                SwiftUI.Label("Журнал FTP".localized, systemImage: "doc.text")
            }
            Button {
                HapticHelper.selection()
                sysNotifications.toggle()
                if sysNotifications {
                    NotificationHelper.requestAuthorization()
                }
            } label: {
                SwiftUI.Label(
                    sysNotifications ? "Уведомления включены".localized : "Уведомления выключены".localized,
                    systemImage: sysNotifications ? "bell.fill" : "bell.slash"
                )
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .accessibilityLabel("Ещё".localized)
        }
    }
}
