import SwiftUI
import PhotosUI

struct UploadQueueView: View {
    @Binding var photos: [PhotoMetadata]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var searchText = ""
    @State private var selectedFilter: PhotoStatus? = nil
    @State private var editingPhotoId: UUID? = nil
    @State private var isAnalyzingAll = false
    
    // Status message toast
    @State private var toastMessage = ""
    @State private var showToast = false
    
    var filteredPhotos: [PhotoMetadata] {
        photos.filter { photo in
            let matchesSearch = searchText.isEmpty || 
                                photo.filename.localizedCaseInsensitiveContains(searchText) || 
                                photo.title.localizedCaseInsensitiveContains(searchText) ||
                                photo.keywords.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            
            let matchesFilter = selectedFilter == nil || photo.status == selectedFilter
            return matchesSearch && matchesFilter
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                VStack(spacing: 14) {
                    // Header Dashboard Summary (Sleek Apple style tags)
                    HStack(spacing: 12) {
                        summaryCard(title: "В очереди", count: photos.count, icon: "tray.fill", color: .blue)
                        summaryCard(title: "Готовы", count: photos.filter({ $0.status == .ready }).count, icon: "checkmark.circle.fill", color: .green)
                        summaryCard(title: "Загружены", count: photos.filter({ $0.status == .success }).count, icon: "paperplane.fill", color: .purple)
                    }
                    .padding(.horizontal)
                    .padding(.top, 14)
                    
                    // Drag & Drop / Selection Zone (Polished Glass Dropzone)
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 50,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(AppleTheme.primaryGradient)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Добавить фотографии")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("Выберите JPEG, PNG или HEIC")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .glassCard(cornerRadius: 12, padding: 12)
                    }
                    .padding(.horizontal)
                    .onChange(of: selectedItems) { newItems in
                        loadSelectedPhotos(from: newItems)
                    }
                    
                    // Search Bar (Sleeker and smaller)
                    HStack {
                        Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
                        TextField("Поиск...", text: $searchText)
                            .font(.system(size: 13))
                    }
                    .glassCard(cornerRadius: 10, padding: 8)
                    .padding(.horizontal)
                    
                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(text: "Все (\(photos.count))", isSelected: selectedFilter == nil) {
                                selectedFilter = nil
                            }
                            
                            ForEach(PhotoStatus.allCases, id: \.self) { status in
                                let count = photos.filter { $0.status == status }.count
                                FilterChip(text: "\(status.rawValue) (\(count))", isSelected: selectedFilter == status) {
                                    selectedFilter = status
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Photo Queue List
                    if filteredPhotos.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            SmartStockLogoView(size: 64)
                                .padding(.bottom, 6)
                            Text("Очередь пуста")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("Добавьте новые фото для обработки и автозаполнения ИИ")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity)
                        .glassCard(cornerRadius: 16, padding: 28)
                        .padding(.horizontal)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredPhotos) { photo in
                                    photoRow(photo)
                                        .glassCard(cornerRadius: 12, padding: 10)
                                        .onTapGesture {
                                            editingPhotoId = photo.id
                                        }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 80) // Leave space for floating action bar
                        }
                    }
                }
                
                // Floating Action Bar at the bottom (Neat Apple style)
                if !photos.isEmpty {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Button(action: runAIForAll) {
                                HStack {
                                    if isAnalyzingAll {
                                        ProgressView().scaleEffect(0.8).tint(.white)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text("Заполнить все ИИ")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppleTheme.primaryGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: AppleTheme.glowStart.opacity(0.25), radius: 6, x: 0, y: 3)
                            }
                            .disabled(isAnalyzingAll)
                            
                            Button(action: uploadAllReady) {
                                HStack {
                                    Image(systemName: "paperplane.fill")
                                    Text("Отправить")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial)
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                            }
                        }
                        .padding(10)
                        .glassCard(cornerRadius: 16, padding: 8)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                    }
                }
                
                // Toast notification overlay
                if showToast {
                    VStack {
                        Spacer()
                        Text(toastMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .foregroundStyle(.primary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                            .padding(.bottom, 90)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("SmartStock")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: Binding(
                get: { 
                    if let id = editingPhotoId, let index = photos.firstIndex(where: { $0.id == id }) {
                        return ActiveSheetPhoto(id: id, photos: photos, index: index)
                    }
                    return nil
                },
                set: { value in
                    editingPhotoId = value?.id
                }
            )) { wrapper in
                NavigationStack {
                    AIMetadataView(photos: wrapper.photos, currentIndex: wrapper.index) { updatedPhotos in
                        for updated in updatedPhotos {
                            if let idx = photos.firstIndex(where: { $0.id == updated.id }) {
                                photos[idx] = updated
                            }
                        }
                        editingPhotoId = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Закрыть") {
                                editingPhotoId = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Photo Row Component (Refined & Neat)
    private func photoRow(_ photo: PhotoMetadata) -> some View {
        HStack(spacing: 12) {
            // Photo Thumbnail
            Group {
                if let uiImage = photo.uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.04)
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 2)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(photo.filename)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if !photo.title.isEmpty {
                    Text(photo.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(1)
                } else {
                    Text("Нет описания ИИ")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .italic()
                }
                
                HStack(spacing: 5) {
                    Text(photo.fileSize)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text("Тегов: \(photo.keywords.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    // Small status circle
                    Circle()
                        .fill(photo.status.color)
                        .frame(width: 5, height: 5)
                    
                    Text(photo.status.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(photo.status.color)
                }
            }
            
            Spacer()
            
            // Neat Action Menu
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button(action: { runAIForPhoto(photo.id) }) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(AppleTheme.primaryGradient)
                            .clipShape(Circle())
                    }
                    
                    Button(action: { uploadPhoto(photo.id) }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                            .padding(6)
                            .background(.white.opacity(0.1))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                }
                
                Button(action: { removePhoto(photo.id) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.7))
                }
            }
        }
    }
    
    // MARK: - Dashboard Card (Polished & Compact)
    private func summaryCard(title: String, count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .padding(6)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .glassCard(cornerRadius: 10, padding: 8)
    }
    
    // MARK: - Load Photos Logic
    private func loadSelectedPhotos(from items: [PhotosPickerItem]) {
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                switch result {
                case .success(let data):
                    if let data = data {
                        let randomNum = Int.random(in: 1000...9999)
                        let filename = "IMG_\(randomNum).JPG"
                        let sizeMB = Double(data.count) / (1024.0 * 1024.0)
                        let fileSizeStr = String(format: "%.2f МБ", sizeMB)
                        
                        let newPhoto = PhotoMetadata(
                            filename: filename,
                            fileSize: fileSizeStr,
                            title: "",
                            keywords: [],
                            description: "",
                            status: .new,
                            imageData: data
                        )
                        
                        DispatchQueue.main.async {
                            self.photos.append(newPhoto)
                        }
                    }
                case .failure(let error):
                    print("Error loading image: \(error.localizedDescription)")
                }
            }
        }
        selectedItems = []
    }
    
    // MARK: - Real AI Analysis integration
    private func runAIForPhoto(_ id: UUID) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        
        let provider = UserDefaults.standard.string(forKey: "ai_provider") ?? AIProvider.gemini.rawValue
        let customPrompt = UserDefaults.standard.string(forKey: "ai_custom_prompt") ?? ""
        
        let apiKey: String
        if provider.contains("Gemini") {
            apiKey = UserDefaults.standard.string(forKey: "api_key_gemini") ?? ""
        } else if provider.contains("OpenAI") {
            apiKey = UserDefaults.standard.string(forKey: "api_key_openai") ?? ""
        } else {
            apiKey = UserDefaults.standard.string(forKey: "api_key_claude") ?? ""
        }
        
        // Check if API key is blank
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            // No Key: Demo Mode
            photos[idx].status = .aiAnalyzing
            triggerToast("Запущен демо-анализ (ключ API не введен)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if photos.count > idx {
                    photos[idx].title = "Драматичный закат в горах (Демо)"
                    photos[idx].keywords = ["закат", "облака", "небо", "горы", "пейзаж", "демо"]
                    photos[idx].description = "Демо-описание: Введите ваш API-ключ в настройках ИИ для запуска полноценного анализа вашей фотографии."
                    photos[idx].status = .ready
                    triggerToast("Демо-анализ завершен")
                }
            }
            return
        }
        
        photos[idx].status = .aiAnalyzing
        triggerToast("ИИ анализирует фотографию...")
        
        Task {
            do {
                let imageData = photos[idx].imageData ?? Data()
                let result = try await AIManager.shared.analyzePhoto(
                    imageData: imageData,
                    customPrompt: customPrompt,
                    provider: provider,
                    apiKey: apiKey
                )
                
                await MainActor.run {
                    if let currentIdx = photos.firstIndex(where: { $0.id == id }) {
                        photos[currentIdx].title = result.title
                        photos[currentIdx].description = result.description
                        photos[currentIdx].keywords = result.keywords
                        photos[currentIdx].status = .ready
                        triggerToast("Анализ ИИ успешно завершен!")
                    }
                }
            } catch {
                await MainActor.run {
                    if let currentIdx = photos.firstIndex(where: { $0.id == id }) {
                        photos[currentIdx].description = "Ошибка: \(error.localizedDescription)"
                        photos[currentIdx].status = .error
                        triggerToast("Ошибка ИИ: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func runAIForAll() {
        let newOrErrorPhotos = photos.filter { $0.status == .new || $0.status == .error }
        guard !newOrErrorPhotos.isEmpty else { return }
        
        isAnalyzingAll = true
        triggerToast("Запущен ИИ-анализ для \(newOrErrorPhotos.count) фото...")
        
        let provider = UserDefaults.standard.string(forKey: "ai_provider") ?? AIProvider.gemini.rawValue
        let customPrompt = UserDefaults.standard.string(forKey: "ai_custom_prompt") ?? ""
        let apiKey: String
        if provider.contains("Gemini") {
            apiKey = UserDefaults.standard.string(forKey: "api_key_gemini") ?? ""
        } else if provider.contains("OpenAI") {
            apiKey = UserDefaults.standard.string(forKey: "api_key_openai") ?? ""
        } else {
            apiKey = UserDefaults.standard.string(forKey: "api_key_claude") ?? ""
        }
        
        // Loop and run
        Task {
            for photo in newOrErrorPhotos {
                if let idx = photos.firstIndex(where: { $0.id == photo.id }) {
                    await MainActor.run { photos[idx].status = .aiAnalyzing }
                    
                    if apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Demo mode delay
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        await MainActor.run {
                            if photos.count > idx {
                                photos[idx].title = "Красивый снимок \(photo.filename) (Демо)"
                                photos[idx].keywords = ["фотография", "снимок", "стоки", "демо", "пейзаж"]
                                photos[idx].description = "Демо-описание: Введите ваш API-ключ в настройках ИИ для запуска полноценного анализа."
                                photos[idx].status = .ready
                            }
                        }
                    } else {
                        // Real analysis
                        do {
                            let data = photos[idx].imageData ?? Data()
                            let result = try await AIManager.shared.analyzePhoto(
                                imageData: data,
                                customPrompt: customPrompt,
                                provider: provider,
                                apiKey: apiKey
                            )
                            await MainActor.run {
                                if photos.count > idx {
                                    photos[idx].title = result.title
                                    photos[idx].description = result.description
                                    photos[idx].keywords = result.keywords
                                    photos[idx].status = .ready
                                }
                            }
                        } catch {
                            await MainActor.run {
                                if photos.count > idx {
                                    photos[idx].status = .error
                                    photos[idx].description = "Ошибка: \(error.localizedDescription)"
                                }
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                isAnalyzingAll = false
                triggerToast("ИИ-анализ всех фото завершен")
            }
        }
    }
    
    // MARK: - FTP Upload simulation with credentials check
    private func uploadPhoto(_ id: UUID) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        
        // Ensure at least one stock platform is enabled and has credentials
        guard checkStockCredentials() else {
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!")
            return
        }
        
        photos[idx].status = .uploading
        triggerToast("Загрузка файла \(photos[idx].filename)...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if photos.count > idx {
                photos[idx].status = .success
                triggerToast("Файл \(photos[idx].filename) успешно загружен на стоки!")
            }
        }
    }
    
    private func uploadAllReady() {
        let readyPhotos = photos.filter { $0.status == .ready }
        guard !readyPhotos.isEmpty else {
            triggerToast("Нет файлов, готовых к отправке.")
            return
        }
        
        guard checkStockCredentials() else {
            triggerToast("Ошибка: Нет активных стоков или не введены логин/пароль!")
            return
        }
        
        triggerToast("Началась отправка \(readyPhotos.count) файлов...")
        for i in 0..<photos.count {
            if photos[i].status == .ready {
                photos[i].status = .uploading
                let idx = i
                DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1.0...2.5)) {
                    if photos.count > idx {
                        photos[idx].status = .success
                        if idx == photos.count - 1 || i == photos.count - 1 {
                            triggerToast("Все файлы успешно загружены!")
                        }
                    }
                }
            }
        }
    }
    
    private func checkStockCredentials() -> Bool {
        if let data = UserDefaults.standard.data(forKey: "stock_platforms"),
           let decoded = try? JSONDecoder().decode([StockPlatform].self, from: data) {
            let activePlatforms = decoded.filter { $0.isEnabled }
            // Must have at least one active platform and it must have username/password
            return !activePlatforms.isEmpty && activePlatforms.contains(where: { !$0.username.isEmpty && !$0.passwordHash.isEmpty })
        }
        return false
    }
    
    private func removePhoto(_ id: UUID) {
        photos.removeAll(where: { $0.id == id })
    }
    
    private func deletePhoto(at offsets: IndexSet) {
        photos.remove(atOffsets: offsets)
    }
    
    private func triggerToast(_ message: String) {
        toastMessage = message
        withAnimation {
            showToast = true
        }
        // Dismiss after 2.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toastMessage == message {
                withAnimation {
                    showToast = false
                }
            }
        }
    }
}
