import SwiftUI

/// Полноэкранный/Sheet пикер файлов из облака Google Фото
struct GooglePhotosPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = GooglePhotosManager.shared
    
    var onSelectItems: ([GoogleMediaItem]) -> Void
    
    @State private var selectedItems: Set<String> = []
    @State private var filterOnlyVideos = false
    @State private var searchQuery = ""
    @State private var isDownloading = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)
    ]
    
    var filteredItems: [GoogleMediaItem] {
        manager.mediaItems.filter { item in
            let matchesFilter = filterOnlyVideos ? item.isVideo : true
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
                
                Toggle(isOn: $filterOnlyVideos) {
                    Label("Видео", systemImage: "video.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .toggleStyle(.button)
                .tint(.purple)
                .onChange(of: filterOnlyVideos) { newValue in
                    triggerHaptic()
                    Task {
                        await manager.loadMediaItems(filterVideoOnly: newValue)
                    }
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
            AsyncImage(url: item.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                case .empty:
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .overlay(ProgressView())
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.purple : Color.white.opacity(0.12), lineWidth: isSelected ? 3 : 1)
            )
            
            // Видео значок внизу
            if item.isVideo {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                        Text("VIDEO")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(6)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
            // Чекбокс выбора
            ZStack {
                Circle()
                    .fill(isSelected ? Color.purple : Color.black.opacity(0.4))
                    .frame(width: 24, height: 24)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
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
