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

/// Полноэкранный/Sheet пикер файлов из облака Google Фото
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
                GoogleMediaPreviewModal(item: item, token: manager.accessToken)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена".localized) {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
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
            .task {
                if manager.isAuthenticated {
                    await manager.loadMediaItems()
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var unauthenticatedView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)
            
            Circle()
                .fill(Color.white)
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "photo.stack")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [.red, .yellow, .green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 12)
            
            VStack(spacing: 8) {
                Text("Подключение Google Фото".localized)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("Выбирайте исходные видео и фото прямо из вашего облачного архива для публикации на стоках.".localized)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            Button(action: {
                triggerHaptic()
                Task {
                    await manager.signInWithGoogle()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 20))
                    Text("Войти через Google".localized)
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [Color(hex: "4285F4"), Color(hex: "34A853")], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color(hex: "4285F4").opacity(0.3), radius: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            Spacer()
        }
        .glassCard(cornerRadius: 20, padding: 24)
        .padding(.vertical, 20)
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
                    Text("Загрузка медиафайлов...".localized)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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
            .padding(6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            triggerHaptic()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                if selectedItems.contains(item.id) {
                    selectedItems.remove(item.id)
                } else {
                    selectedItems.insert(item.id)
                }
            }
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

// MARK: - Authenticated Image Loader
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
        
        isLoading = true
        isError = false
        
        var request = URLRequest(url: url)
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200, let loadedImage = UIImage(data: data) {
                GoogleImageCache.shared.setObject(loadedImage, forKey: cacheKey)
                self.image = loadedImage
            } else {
                self.isError = true
            }
        } catch {
            self.isError = true
        }
        isLoading = false
    }
}

private class GoogleImageCache {
    static let shared = NSCache<NSString, UIImage>()
}

// MARK: - Fullscreen Media Preview Modal
struct GoogleMediaPreviewModal: View {
    @Environment(\.dismiss) private var dismiss
    let item: GoogleMediaItem
    let token: String?
    
    @State private var player: AVPlayer? = nil
    
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
                    AuthenticatedGoogleImageView(url: item.downloadURL ?? URL(string: item.baseUrl), token: token)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 12)
                }
                
                Spacer()
            }
        }
        .onAppear {
            if item.isVideo, let downloadURL = item.downloadURL ?? URL(string: item.baseUrl) {
                let headers = token != nil ? ["Authorization": "Bearer \(token!)"] : [:]
                let asset = AVURLAsset(url: downloadURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                let playerItem = AVPlayerItem(asset: asset)
                let avPlayer = AVPlayer(playerItem: playerItem)
                self.player = avPlayer
                avPlayer.play()
            }
        }
    }
}
