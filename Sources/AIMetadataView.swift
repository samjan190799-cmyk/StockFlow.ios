import SwiftUI
import UIKit
import AVFoundation

// MARK: - AI metadata screen
@MainActor
struct AIMetadataView: View {
    @State private var photos: [PhotoMetadata]
    @State private var currentIndex: Int
    @State private var newKeyword = ""
    @State private var isRegenerating = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    private let shutterstockCategories = [
        "Abstract", "Animals/Wildlife", "Arts", "Backgrounds/Textures", "Beauty/Fashion",
        "Buildings/Landmarks", "Business/Finance", "Celebrities", "Education", "Food and drink",
        "Healthcare/Medical", "Holidays", "Industrial", "Interiors", "Miscellaneous",
        "Nature", "Objects", "Parks/Outdoor", "People", "Religion",
        "Science", "Signs/Symbols", "Sports/Recreation", "Technology", "Transportation", "Vintage"
    ]

    var onContinue: (@MainActor ([PhotoMetadata]) -> Void)?

    init(photos: [PhotoMetadata], currentIndex: Int = 0, onContinue: (@MainActor ([PhotoMetadata]) -> Void)? = nil) {
        self._photos = State(initialValue: photos)
        self._currentIndex = State(initialValue: currentIndex)
        self.onContinue = onContinue
    }

    var body: some View {
        ZStack {
            LiquidBackgroundView()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    
                    // Photo Navigator Panel
                    photoNavigator
                        .glassCard(cornerRadius: 16, padding: 12)
                    
                    // Large Premium Image Preview Header
                    imagePreviewHeader
                    
                    // Title Panel
                    titleField
                        .glassCard(cornerRadius: 18, padding: 14)
                    
                    // Keywords Panel
                    keywordsField
                        .glassCard(cornerRadius: 18, padding: 14)
                    
                    // Categories Panel
                    categoriesField
                        .glassCard(cornerRadius: 18, padding: 14)
                    
                    // Description Panel
                    descriptionField
                        .glassCard(cornerRadius: 18, padding: 14)
                    
                    // Continue Button
                    continueButton
                        .padding(.top, 4)
                }
                .padding()
            }
        }
        .navigationTitle("Метаданные".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert("ИИ-Ассистент".localized, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: Sections

    private var imagePreviewHeader: some View {
        ZStack {
            // Soft blurred shadow projection
            LazyImageView(photoId: photos[currentIndex].id, maxPixelSize: 150, contentMode: .fill, isVideo: photos[currentIndex].isVideo, photo: photos[currentIndex])
                .frame(height: 150)
                .blur(radius: 24)
                .opacity(0.35)
                .scaleEffect(0.94)
            
            LazyImageView(photoId: photos[currentIndex].id, maxPixelSize: 400, contentMode: .fit, isVideo: photos[currentIndex].isVideo, photo: photos[currentIndex])
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var photoNavigator: some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticHelper.trigger(.light)
                withAnimation(.easeInOut(duration: 0.25)) {
                    goToPrevious()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(PremiumButtonStyle())
            .disabled(currentIndex == 0)
            .opacity(currentIndex == 0 ? 0.3 : 1.0)

            Spacer()

            VStack(spacing: 2) {
                Text("Файл".localized + " \(currentIndex + 1) " + "из".localized + " \(photos.count)")
                    .font(.system(size: 13, weight: .black))
                Text(photos[currentIndex].filename)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                HapticHelper.trigger(.light)
                withAnimation(.easeInOut(duration: 0.25)) {
                    goToNext()
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(PremiumButtonStyle())
            .disabled(currentIndex == photos.count - 1)
            .opacity(currentIndex == photos.count - 1 ? 0.3 : 1.0)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Заголовок".localized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button(action: {
                    HapticHelper.trigger(.medium)
                    regenerate()
                }) {
                    HStack(spacing: 4) {
                        if #available(iOS 17.0, *) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .symbolEffect(.pulse, options: .repeating, value: isRegenerating)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        Text("Заново".localized).font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color(hex: "007AFF"))
                }
                .buttonStyle(PremiumButtonStyle())
                .disabled(isRegenerating)
            }
            
            TextField("Заголовок фото".localized, text: binding(\.title))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(12)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1.2)
                )
        }
    }

    private var keywordsField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ключевые слова".localized)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(photos[currentIndex].keywords, id: \.self) { keyword in
                    KeywordChip(text: keyword, onRemove: { removeKeyword(keyword) })
                }
            }

            HStack(spacing: 8) {
                TextField("Добавить слово".localized, text: $newKeyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1.2)
                    )
                    .onSubmit(addKeyword)
                
                Button("Добавить".localized, action: {
                    HapticHelper.trigger(.light)
                    addKeyword()
                })
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppleTheme.primaryGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .buttonStyle(PremiumButtonStyle())
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                .neonShadow(color: Color(hex: "7C3AED"), radius: 4)
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Описание".localized)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            TextEditor(text: binding(\.description))
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(height: 90)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1.2)
                )
        }
    }

    private var categoriesField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Категории (Макс. 2)".localized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                if photos[currentIndex].categories.count < 2 {
                    Menu {
                        ForEach(shutterstockCategories.filter { !photos[currentIndex].categories.contains($0) }, id: \.self) { category in
                            Button(category) {
                                HapticHelper.trigger(.light)
                                photos[currentIndex].categories.append(category)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Добавить".localized)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color(hex: "7C3AED"))
                    }
                } else {
                    Text("Лимит достигнут".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if photos[currentIndex].categories.isEmpty {
                Text("Категории не выбраны. Выберите до 2 категорий.".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(photos[currentIndex].categories, id: \.self) { category in
                        KeywordChip(text: category, onRemove: { removeCategory(category) })
                    }
                }
            }
        }
    }

    private var continueButton: some View {
        Button(action: {
            HapticHelper.trigger(.medium)
            onContinue?(photos)
        }) {
            Text("Сохранить изменения".localized)
                .font(.system(size: 14, weight: .black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppleTheme.primaryGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .neonShadow(color: Color(hex: "7C3AED"), radius: 6)
        }
        .buttonStyle(PremiumButtonStyle())
    }

    // MARK: Helpers

    private func binding<T>(_ keyPath: WritableKeyPath<PhotoMetadata, T>) -> Binding<T> {
        Binding(
            get: { photos[currentIndex][keyPath: keyPath] },
            set: { photos[currentIndex][keyPath: keyPath] = $0 }
        )
    }

    private func goToPrevious() {
        if currentIndex > 0 { currentIndex -= 1 }
    }

    private func goToNext() {
        if currentIndex < photos.count - 1 { currentIndex += 1 }
    }

    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !photos[currentIndex].keywords.contains(trimmed) else { return }
        photos[currentIndex].keywords.append(trimmed)
        newKeyword = ""
    }

    private func removeKeyword(_ keyword: String) {
        photos[currentIndex].keywords.removeAll { $0 == keyword }
    }

    private func removeCategory(_ category: String) {
        photos[currentIndex].categories.removeAll { $0 == category }
    }

    private func regenerate() {
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
        
        isRegenerating = true
        let curIdx = currentIndex
        
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            isRegenerating = false
            alertMessage = "Для генерации метаданных с помощью ИИ укажите API-ключ в настройках ИИ-Ассистента (Gemini, OpenAI или Claude).".localized
            showingAlert = true
            return
        }
        
        let dirURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos")
        let photo = photos[curIdx]
        let isVideo = photo.isVideo
        
        let resolved = QueueViewModel.shared?.resolveSourceURL(for: photo)
        let fileURL: URL = resolved?.url ?? {
            let ext = isVideo ? (URL(fileURLWithPath: photo.filename).pathExtension.lowercased()) : "jpg"
            let actualExt = ext.isEmpty ? (isVideo ? "mp4" : "jpg") : ext
            return dirURL.appendingPathComponent("\(photo.id.uuidString).\(actualExt)")
        }()
        let needStopAccess = resolved?.needAccessStop ?? false
        
        Task {
            defer {
                if needStopAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let imagesData: [Data]
                if isVideo {
                    imagesData = await ImageCacheHelper.shared.extractFrames(
                        fileURL: fileURL,
                        count: 3
                    )
                } else {
                    if let image = await ImageCacheHelper.shared.loadAndDownsample(fileURL: fileURL, maxPixelSize: 1568),
                       let jpeg = image.jpegData(compressionQuality: 0.85) {
                        imagesData = [jpeg]
                    } else if let data = try? Data(contentsOf: fileURL), let uiImg = UIImage(data: data), let jpeg = uiImg.jpegData(compressionQuality: 0.85) {
                        imagesData = [jpeg]
                    } else {
                        imagesData = []
                    }
                }
                
                let result = try await AIManager.shared.analyzePhoto(
                    imagesData: imagesData,
                    customPrompt: customPrompt,
                    provider: provider,
                    apiKey: apiKey
                )
                self.photos[curIdx].title = result.title
                self.photos[curIdx].description = result.description
                self.photos[curIdx].keywords = result.keywords
                self.photos[curIdx].categories = result.categories ?? []
                self.isRegenerating = false
            } catch {
                self.photos[curIdx].description = "Ошибка: \(error.localizedDescription)"
                self.isRegenerating = false
            }
        }
    }
}

// MARK: - Keyword chip
private struct KeywordChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
            Button(action: {
                HapticHelper.trigger(.light)
                onRemove()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PremiumButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - Wrapping layout for keyword chips
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
