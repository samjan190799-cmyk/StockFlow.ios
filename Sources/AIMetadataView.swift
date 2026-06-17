import SwiftUI

// MARK: - AI metadata screen

struct AIMetadataView: View {
    @State private var photos: [PhotoMetadata]
    @State private var currentIndex = 0
    @State private var newKeyword = ""
    @State private var isRegenerating = false

    var onContinue: (([PhotoMetadata]) -> Void)?

    init(photos: [PhotoMetadata], currentIndex: Int = 0, onContinue: (([PhotoMetadata]) -> Void)? = nil) {
        self._photos = State(initialValue: photos)
        self._currentIndex = State(initialValue: currentIndex)
        self.onContinue = onContinue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                photoNavigator
                titleField
                keywordsField
                descriptionField
                continueButton
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .navigationTitle("Метаданные")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }

    // MARK: Sections

    private var photoNavigator: some View {
        HStack(spacing: 10) {
            Button(action: goToPrevious) {
                Image(systemName: "chevron.left").foregroundStyle(.secondary)
            }
            .disabled(currentIndex == 0)

            Group {
                if let uiImage = photos[currentIndex].uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray5)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Фото \(currentIndex + 1) из \(photos.count)")
                    .font(.system(size: 13))
                Text(photos[currentIndex].filename)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: goToNext) {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .disabled(currentIndex == photos.count - 1)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Заголовок")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: regenerate) {
                    HStack(spacing: 4) {
                        if isRegenerating {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11))
                        }
                        Text("Заново").font(.system(size: 12))
                    }
                    .foregroundStyle(.blue)
                }
                .disabled(isRegenerating)
            }
            TextField("Заголовок фото", text: binding(\.title))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var keywordsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ключевые слова")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(photos[currentIndex].keywords, id: \.self) { keyword in
                    KeywordChip(text: keyword, onRemove: { removeKeyword(keyword) })
                }
            }

            HStack(spacing: 8) {
                TextField("Добавить слово", text: $newKeyword)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit(addKeyword)
                Button("Добавить", action: addKeyword)
                    .font(.system(size: 13))
                    .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Описание")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextEditor(text: binding(\.description))
                .font(.system(size: 14))
                .frame(height: 80)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
        }
    }

    private var continueButton: some View {
        Button(action: { 
            onContinue?(photos) 
        }) {
            Text("Сохранить и закрыть")
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
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
        isRegenerating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            photos[currentIndex].title = "Драматичное закатное небо над горой Арарат"
            photos[currentIndex].keywords = ["Арарат", "гора", "закат", "Армения", "пейзаж", "природа", "драматичное небо"]
            photos[currentIndex].description = "Силуэт горы Арарат на фоне яркого закатного неба, снято в сельской местности Армении."
            photos[currentIndex].status = .ready
            isRegenerating = false
        }
    }
}

// MARK: - Keyword chip

private struct KeywordChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 12))
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.systemGray6))
        .foregroundStyle(.secondary)
        .clipShape(Capsule())
    }
}

// MARK: - Wrapping layout for keyword chips (requires iOS 16+)

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
