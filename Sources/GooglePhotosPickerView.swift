import SwiftUI
import AVKit

enum MediaFilterType: String, CaseIterable, Identifiable {
    case all = "Все файлы"
    case photos = "Только фото"
    case videos = "Только видео"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all: return "photo.stack"
        case .photos: return "photo"
        case .videos: return "video.fill"
        }
    }
}

// MARK: - NSCache для миниатюр Google Photos (с жёстким лимитом памяти)
final class GoogleImageCache: @unchecked Sendable {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 500          // не более 500 миниатюр
        cache.totalCostLimit = 100 * 1024 * 1024  // 100 МБ
        return cache
    }()

    static func clearAll() {
        shared.removeAllObjects()
    }
}

// MARK: - Семафор для ограничения параллельных загрузок миниатюр
actor ThumbnailLoadSemaphore {
    static let shared = ThumbnailLoadSemaphore(maxConcurrent: 8)

    private let maxConcurrent: Int
    private var current = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire() async {
        if current < maxConcurrent {
            current += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            current = max(0, current - 1)
        }
    }
}

/// Полноэкранный/Sheet пикер файлов из облака Google Фото
@MainActor
struct GooglePhotosPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = GooglePhotosManager.shared

    var onSelectItems: ([GoogleMediaItem]) -> Void

    @State private var selectedItems: Set<String> = []
    @State private var selectedFilter: MediaFilterType = .all
    @State private var searchQuery = ""
    @State private var isDownloading = false
    @State private var previewItem: GoogleMediaItem? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)
    ]

    var filteredItems: [GoogleMediaItem] {
        manager.mediaItems.filter { item in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .photos: matchesFilter = !item.isVideo
            case .videos: matchesFilter = item.isVideo
            }
            let matchesSearch = searchQuery.isEmpty || item.filename.localizedCaseInsensitiveContains(searchQuery)
            return matchesFilter && matchesSearch
        }
    }

    @State private var showHelpSheet = false
    @AppStorage("google_oauth_client_id") private var customGoogleClientId: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()

                VStack(spacing: 14) {
                    // Статус / Авторизация
                    if !manager.isAuthenticated {
                        unauthenticatedView
                    } else {
                        authenticatedContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Google Фото".localized)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $previewItem) { item in
                GoogleMediaPreviewModal(item: item, token: manager.accessToken, onImport: {
                    triggerHaptic()
                    onSelectItems([item])
                    dismiss()
                })
            }
            .sheet(isPresented: $showHelpSheet) {
                GoogleOAuthHelpSheet()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена".localized) {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {
                            triggerHaptic()
                            showHelpSheet = true
                        }) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: "4285F4"))
                        }

                        // Кнопка принудительного обновления списка
                        if manager.isAuthenticated && !manager.isLoading {
                            Button(action: {
                                Task { await manager.loadMediaItems(forceReload: true) }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if manager.isAuthenticated && !selectedItems.isEmpty {
                            Button(action: importSelectedItems) {
                                HStack(spacing: 6) {
                                    if isDownloading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text("Импорт (\(selectedItems.count))".localized)
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.purple)
                                .clipShape(Capsule())
                            }
                            .disabled(isDownloading)
                        }
                    }
                }
            }
            .task {
                // Загружаем только если список пуст — иначе показываем кешированный
                if manager.isAuthenticated && manager.mediaItems.isEmpty {
                    await manager.loadMediaItems()
                }
            }
        }
    }

    // MARK: - Subviews

    private var unauthenticatedView: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 10)

            Circle()
                .fill(Color.white)
                .frame(width: 76, height: 76)
                .overlay(
                    Image(systemName: "photo.stack")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [.red, .yellow, .green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 12)

            VStack(spacing: 6) {
                Text("Подключение Google Фото".localized)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Выбирайте исходные видео и фото прямо из вашего облачного архива для публикации на стоках.".localized)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Google OAuth Client ID".localized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                
                TextField("Вставьте Client ID из Google Cloud Console...".localized, text: $customGoogleClientId)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }
            .padding(.horizontal, 8)

            if !manager.statusMessage.isEmpty {
                Text(manager.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Button(action: {
                triggerHaptic()
                Task {
                    await manager.signInWithGoogle()
                }
            }) {
                HStack(spacing: 10) {
                    if manager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 18))
                        Text("Войти через Google".localized)
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(LinearGradient(colors: [Color(hex: "4285F4"), Color(hex: "34A853")], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color(hex: "4285F4").opacity(0.3), radius: 6)
            }
            .disabled(manager.isLoading)
            .padding(.horizontal, 8)

            Spacer().frame(height: 10)
        }
        .glassCard(cornerRadius: 20, padding: 20)
        .padding(.vertical, 16)
    }

    private var authenticatedContent: some View {
        VStack(spacing: 12) {
            // Информация об аккаунте
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text(manager.userEmail.isEmpty ? "Google Фото подключено".localized : manager.userEmail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                // Счётчик файлов
                if !manager.mediaItems.isEmpty {
                    Text("\(manager.mediaItems.count) файлов".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Button(action: {
                    triggerHaptic()
                    manager.signOut()
                }) {
                    Text("Выйти".localized)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Поиск и Фильтры
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Поиск по файлам...".localized, text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Menu {
                    ForEach(MediaFilterType.allCases) { option in
                        Button(action: {
                            triggerHaptic()
                            selectedFilter = option
                        }) {
                            HStack {
                                Label(option.rawValue.localized, systemImage: option.iconName)
                                if selectedFilter == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedFilter.iconName)
                            .foregroundStyle(Color.purple)
                        Text(selectedFilter.rawValue.localized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // Сетка медиа
            if manager.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .tint(.purple)
                        .scaleEffect(1.3)
                    Text(manager.statusMessage.isEmpty ? "Загрузка медиафайлов...".localized : manager.statusMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                    Text("Файлы не найдены".localized)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredItems) { item in
                            mediaTile(item)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func mediaTile(_ item: GoogleMediaItem) -> some View {
        let isSelected = selectedItems.contains(item.id)

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    AuthenticatedGoogleImageView(url: item.thumbnailURL ?? URL(string: item.baseUrl), token: manager.accessToken)
                        .frame(height: 110)
                        .clipped()
                }

                // Название файла
                HStack(spacing: 4) {
                    if item.isVideo {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.purple)
                    } else {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.blue)
                    }

                    Text(item.filename)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.85))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.purple : Color.white.opacity(0.12), lineWidth: isSelected ? 3 : 1)
            )

            // Заголовок карточки: Глаз (Предпросмотр) слева и Чекбокс справа
            HStack {
                Button(action: {
                    triggerHaptic()
                    previewItem = item
                }) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Circle())
                }

                Spacer()

                Button(action: {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        if selectedItems.contains(item.id) {
                            selectedItems.remove(item.id)
                        } else {
                            selectedItems.insert(item.id)
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.purple : Color.black.opacity(0.5))
                            .frame(width: 24, height: 24)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding(6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            triggerHaptic()
            previewItem = item
        }
    }

    private func importSelectedItems() {
        triggerHaptic()
        isDownloading = true

        let chosen = manager.mediaItems.filter { selectedItems.contains($0.id) }
        onSelectItems(chosen)
        dismiss()
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - Authenticated Image Loader (с семафором параллельности)
@MainActor
struct AuthenticatedGoogleImageView: View {
    let url: URL?
    let token: String?

    @State private var image: UIImage? = nil
    @State private var isLoading = false
    @State private var isError = false

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .overlay(ProgressView().tint(.purple))
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url else {
            isError = true
            return
        }

        let cacheKey = NSString(string: url.absoluteString)
        if let cached = GoogleImageCache.shared.object(forKey: cacheKey) {
            self.image = cached
            return
        }

        // Ограничиваем параллельность через семафор (не более 8 одновременных загрузок)
        await ThumbnailLoadSemaphore.shared.acquire()
        defer {
            Task { await ThumbnailLoadSemaphore.shared.release() }
        }

        // Двойная проверка кеша после ожидания семафора
        if let cached = GoogleImageCache.shared.object(forKey: cacheKey) {
            self.image = cached
            return
        }

        isLoading = true
        isError = false

        let currentToken = token ?? GooglePhotosManager.shared.accessToken
        let urlString = url.absoluteString.lowercased()
        let isPhotosCDN = urlString.contains("googleusercontent.com") && !urlString.contains("drive")

        // 1. Для CDN Google Photos сперва пробуем прямой публичный запрос (так как подписанный baseUrl работает без Bearer)
        if isPhotosCDN {
            if let (data, response) = try? await URLSession.shared.data(from: url),
               let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
               let loadedImage = UIImage(data: data) {
                GoogleImageCache.shared.setObject(loadedImage, forKey: cacheKey, cost: data.count)
                self.image = loadedImage
                isLoading = false
                return
            }
        }

        // 2. Авторизованный запрос с Bearer токеном (Google Photos / Drive API)
        if let authToken = currentToken, !authToken.isEmpty {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20

            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResp = response as? HTTPURLResponse {
                if httpResp.statusCode == 200, let loadedImage = UIImage(data: data) {
                    let cost = data.count
                    GoogleImageCache.shared.setObject(loadedImage, forKey: cacheKey, cost: cost)
                    self.image = loadedImage
                    isLoading = false
                    return
                } else if httpResp.statusCode == 401 {
                    // Токен просрочился — пытаемся обновить
                    if await GooglePhotosManager.shared.refreshAccessTokenIfNeeded(),
                       let newToken = GooglePhotosManager.shared.accessToken {
                        var retryReq = URLRequest(url: url)
                        retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        retryReq.timeoutInterval = 20
                        if let (retryData, retryResp) = try? await URLSession.shared.data(for: retryReq),
                           (retryResp as? HTTPURLResponse)?.statusCode == 200,
                           let loadedImage = UIImage(data: retryData) {
                            let cost = retryData.count
                            GoogleImageCache.shared.setObject(loadedImage, forKey: cacheKey, cost: cost)
                            self.image = loadedImage
                            isLoading = false
                            return
                        }
                    }
                }
            }
        }

        // 3. Резервный публичный запрос
        if let (data, response) = try? await URLSession.shared.data(from: url),
           let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
           let loadedImage = UIImage(data: data) {
            let cost = data.count
            GoogleImageCache.shared.setObject(loadedImage, forKey: cacheKey, cost: cost)
            self.image = loadedImage
            isLoading = false
            return
        }

        self.isError = true
        isLoading = false
    }
}

// MARK: - Fullscreen Media Preview Modal
@MainActor
struct GoogleMediaPreviewModal: View {
    @Environment(\.dismiss) private var dismiss
    let item: GoogleMediaItem
    let token: String?
    var onImport: (() -> Void)? = nil

    @State private var player: AVPlayer? = nil
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Хедер с информацией
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.filename)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(item.isVideo ? "Видеозапись Google Фото".localized : "Фотография Google Фото".localized)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()

                Spacer()

                // Основной медиаконтент
                if item.isVideo {
                    if let player = player {
                        VideoPlayer(player: player)
                            .frame(maxHeight: 500)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onDisappear {
                                player.pause()
                            }
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().tint(.purple).scaleEffect(1.2)
                            Text("Подготовка воспроизведения видео...".localized)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    AuthenticatedGoogleImageView(url: item.previewURL ?? item.thumbnailURL ?? item.downloadURL ?? URL(string: item.baseUrl), token: token)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomScale = max(1.0, min(value, 4.0))
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        if zoomScale < 1.0 { zoomScale = 1.0 }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                zoomScale = zoomScale > 1.0 ? 1.0 : 2.5
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 12)
                }

                Spacer()

                // Нижняя панель действий
                if let onImport = onImport {
                    HStack(spacing: 14) {
                        Button(action: {
                            onImport()
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Импортировать в очередь".localized)
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.purple.opacity(0.3), radius: 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            if item.isVideo, let downloadURL = item.downloadURL ?? URL(string: item.baseUrl) {
                var headers: [String: String] = [:]
                if let token = token, !token.isEmpty {
                    headers["Authorization"] = "Bearer \(token)"
                }
                let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
                let asset = AVURLAsset(url: downloadURL, options: options)
                let playerItem = AVPlayerItem(asset: asset)
                let avPlayer = AVPlayer(playerItem: playerItem)
                self.player = avPlayer
                avPlayer.play()
            }
        }
    }
}
