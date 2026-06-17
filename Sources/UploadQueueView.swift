import SwiftUI
import PhotosUI

struct UploadQueueView: View {
    @Binding var photos: [PhotoMetadata]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var searchText = ""
    @State private var selectedFilter: PhotoStatus? = nil
    @State private var editingPhotoId: UUID? = nil
    @State private var isAnalyzingAll = false
    
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
            VStack(spacing: 0) {
                // Header Dashboard Summary
                HStack(spacing: 16) {
                    summaryCard(title: "В очереди", count: photos.count, icon: "tray.and.arrow.down.fill", color: .blue)
                    summaryCard(title: "Готовы", count: photos.filter({ $0.status == .ready }).count, icon: "checkmark.circle.fill", color: .green)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // Drag & Drop / Selection Zone
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 50,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                        Text("Нажмите для выбора фотографий")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("JPEG/PNG файлы")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundStyle(Color(.systemGray3))
                    )
                }
                .padding()
                .onChange(of: selectedItems) { newItems in
                    loadSelectedPhotos(from: newItems)
                }
                
                // Action Buttons Toolbar
                if !photos.isEmpty {
                    HStack(spacing: 10) {
                        Button(action: runAIForAll) {
                            HStack {
                                if isAnalyzingAll {
                                    ProgressView().scaleEffect(0.8).tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text("ИИ-Заполнение")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(isAnalyzingAll)
                        
                        Button(action: uploadAllReady) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("Отправить на стоки")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.primary)
                            .foregroundStyle(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
                
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
                .padding(.bottom, 10)
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Поиск по названию, тегам...", text: $searchText)
                        .font(.system(size: 14))
                }
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // Photo Queue List
                if filteredPhotos.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Очередь пуста")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Добавьте новые фото для обработки")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(filteredPhotos) { photo in
                            photoRow(photo)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .background(Color(.systemBackground))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingPhotoId = photo.id
                                }
                        }
                        .onDelete(perform: deletePhoto)
                    }
                    .listStyle(.plain)
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
    
    // MARK: - Photo Row Component
    private func photoRow(_ photo: PhotoMetadata) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Photo Thumbnail
                Group {
                    if let uiImage = photo.uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.systemGray5)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 1)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(photo.filename)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    
                    if !photo.title.isEmpty {
                        Text(photo.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text("Нет заголовка")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    
                    HStack(spacing: 6) {
                        Text(photo.fileSize)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        
                        Text("Тегов: \(photo.keywords.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Status Badge
                    HStack {
                        Circle()
                            .fill(photo.status.color)
                            .frame(width: 6, height: 6)
                        Text(photo.status.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(photo.status.color)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(photo.status.color.opacity(0.12))
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                // Quick actions
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: { runAIForPhoto(photo.id) }) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .padding(8)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }
                        
                        Button(action: { uploadPhoto(photo.id) }) {
                            Image(systemName: "paperplane")
                                .font(.system(size: 12))
                                .padding(8)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }
                    }
                    
                    Button(action: { removePhoto(photo.id) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            Divider()
                .padding(.leading, 92)
        }
    }
    
    // MARK: - Dashboard Card
    private func summaryCard(title: String, count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .padding(10)
                .background(color.opacity(0.12))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold))
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Load Photos Logic
    private func loadSelectedPhotos(from items: [PhotosPickerItem]) {
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                switch result {
                case .success(let data):
                    if let data = data {
                        // Create mock photo entry
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
        // Reset selection so user can pick again
        selectedItems = []
    }
    
    // MARK: - Actions Logic
    private func runAIForPhoto(_ id: UUID) {
        if let idx = photos.firstIndex(where: { $0.id == id }) {
            photos[idx].status = .aiAnalyzing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if photos.count > idx {
                    photos[idx].title = "Драматичное закатное небо"
                    photos[idx].keywords = ["закат", "облака", "небо", "пейзаж", "природа", "красиво"]
                    photos[idx].description = "Красивый закат над горизонтом с драматичными облаками."
                    photos[idx].status = .ready
                }
            }
        }
    }
    
    private func runAIForAll() {
        isAnalyzingAll = true
        for i in 0..<photos.count {
            if photos[i].status == .new || photos[i].status == .error {
                photos[i].status = .aiAnalyzing
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            for i in 0..<photos.count {
                if photos[i].status == .aiAnalyzing {
                    photos[i].title = "Красивое закатное небо"
                    photos[i].keywords = ["пейзаж", "закат", "природа", "небо", "солнце"]
                    photos[i].description = "Прекрасный пейзаж с ярким закатом и облаками."
                    photos[i].status = .ready
                }
            }
            isAnalyzingAll = false
        }
    }
    
    private func uploadPhoto(_ id: UUID) {
        if let idx = photos.firstIndex(where: { $0.id == id }) {
            photos[idx].status = .uploading
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if photos.count > idx {
                    photos[idx].status = .success
                }
            }
        }
    }
    
    private func uploadAllReady() {
        for i in 0..<photos.count {
            if photos[i].status == .ready {
                photos[i].status = .uploading
                let idx = i
                DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1.0...2.5)) {
                    if photos.count > idx {
                        photos[idx].status = .success
                    }
                }
            }
        }
    }
    
    private func removePhoto(_ id: UUID) {
        photos.removeAll(where: { $0.id == id })
    }
    
    private func deletePhoto(at offsets: IndexSet) {
        photos.remove(atOffsets: offsets)
    }
}

// MARK: - Helper Models for Sheet Presentation
struct ActiveSheetPhoto: Identifiable {
    let id: UUID
    let photos: [PhotoMetadata]
    let index: Int
}

// MARK: - Filter Chip Component
struct FilterChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray6))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
