import SwiftUI
import UIKit

// MARK: - AI metadata screen
@MainActor
struct AIMetadataView: View {
    @State private var photos: [PhotoMetadata]
    @State private var currentIndex: Int
    @State private var newKeyword = ""
    @State private var isRegenerating = false

    var onContinue: (([PhotoMetadata]) -> Void)?

    init(photos: [PhotoMetadata], currentIndex: Int = 0, onContinue: (([PhotoMetadata]) -> Void)? = nil) {
        self._photos = State(initialValue: photos)
        self._currentIndex = State(initialValue: currentIndex)
        self.onContinue = onContinue
    }

    var body: some View {
        ZStack {
            LiquidBackgroundView()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Photo Navigator Panel
                    photoNavigator
                        .glassCard(cornerRadius: 14, padding: 12)
                    
                    // Title Panel
                    titleField
                        .glassCard(cornerRadius: 14, padding: 14)
                    
                    // Keywords Panel
                    keywordsField
                        .glassCard(cornerRadius: 14, padding: 14)
                    
                    // Description Panel
                    descriptionField
                        .glassCard(cornerRadius: 14, padding: 14)
                    
                    // Continue Button
                    continueButton
                        .padding(.top, 4)
                }
                .padding()
            }
        }
        .navigationTitle("Метаданные")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private var photoNavigator: some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticHelper.trigger(.light)
                goToPrevious()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.white.opacity(0.1))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(PremiumButtonStyle())
            .disabled(currentIndex == 0)
            .opacity(currentIndex == 0 ? 0.3 : 1.0)

            // Image Preview (if present) or Placeholder
            Group {
                if let uiImage = photos[currentIndex].uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.05)
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text("Фото \(currentIndex + 1) из \(photos.count)")
                    .font(.system(size: 13, weight: .bold))
                Text(photos[currentIndex].filename)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                HapticHelper.trigger(.light)
                goToNext()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.white.opacity(0.1))
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
                Text("Заголовок")
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
                        Text("Заново").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color(hex: "7C3AED"))
                }
                .buttonStyle(PremiumButtonStyle())
                .disabled(isRegenerating)
            }
            
            TextField("Заголовок фото", text: binding(\.title))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private var keywordsField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ключевые слова")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(photos[currentIndex].keywords, id: \.self) { keyword in
                    KeywordChip(text: keyword, onRemove: { removeKeyword(keyword) })
                }
            }

            HStack(spacing: 8) {
                TextField("Добавить слово", text: $newKeyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .onSubmit(addKeyword)
                
                Button("Добавить", action: {
                    HapticHelper.trigger(.light)
                    addKeyword()
                })
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppleTheme.primaryGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .buttonStyle(PremiumButtonStyle())
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Описание")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            TextEditor(text: binding(\.description))
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(height: 90)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private var continueButton: some View {
        Button(action: {
            HapticHelper.trigger(.medium)
            onContinue?(photos)
        }) {
            Text("Сохранить изменения")
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppleTheme.primaryGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: AppleTheme.glowStart.opacity(0.3), radius: 8, x: 0, y: 4)
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
            // Mock fallback
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                self.photos[curIdx].title = "Драматичное закатное небо над горой Арарат (Демо)"
                self.photos[curIdx].keywords = ["Арарат", "гора", "закат", "Армения", "пейзаж", "природа", "демо"]
                self.photos[curIdx].description = "Демо-описание: Введите ваш API-ключ в настройках ИИ для запуска полноценного анализа."
                self.isRegenerating = false
            }
            return
        }
        
        let data = photos[curIdx].imageData ?? Data()
        
        Task {
            do {
                let result = try await AIManager.shared.analyzePhoto(
                    imageData: data,
                    customPrompt: customPrompt,
                    provider: provider,
                    apiKey: apiKey
                )
                self.photos[curIdx].title = result.title
                self.photos[curIdx].description = result.description
                self.photos[curIdx].keywords = result.keywords
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
                .font(.system(size: 11, weight: .medium))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
