import SwiftUI

/// SwiftUI View для ленивой загрузки и отображения картинок по их UUID или PhotoMetadata
struct LazyImageView: View {
    let photoId: UUID
    var maxPixelSize: Int = 400
    var contentMode: ContentMode = .fit
    var isVideo: Bool = false
    var photo: PhotoMetadata? = nil
    
    @State private var image: UIImage? = nil
    @State private var isLoading = false
    
    private var photosDirectoryURL: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
    
    var body: some View {
        Group {
            if let image = image {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                    
                    if isVideo || (photo?.isVideo == true) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                            .padding(4)
                            .background(.black.opacity(0.6))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                            .padding(6)
                    }
                }
            } else {
                ZStack {
                    Color.white.opacity(0.04)
                    if isLoading {
                        ProgressView()
                            .tint(Color(hex: "7C3AED"))
                    } else {
                        Image(systemName: (isVideo || (photo?.isVideo == true)) ? "video" : "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: photoId) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // 1. Проверяем готовый миниатюрный тумбнейл из photo (если передан)
        if let thumbData = photo?.thumbnailData, let uiImg = UIImage(data: thumbData) {
            self.image = uiImg
            self.isLoading = false
            return
        }
        
        let key = "\(photoId.uuidString)_\(maxPixelSize)"
        if let cached = ImageCacheHelper.shared.getCachedImage(forKey: key) {
            self.image = cached
            self.isLoading = false
            return
        }
        
        isLoading = true
        
        // 2. Если есть реальный файл по локальной ссылке — загружаем напрямую по URL
        if let currentPhoto = photo ?? QueueViewModel.shared?.photos.first(where: { $0.id == photoId }),
           let (sourceURL, needStop) = QueueViewModel.shared?.resolveSourceURL(for: currentPhoto) {
            defer {
                if needStop { sourceURL.stopAccessingSecurityScopedResource() }
            }
            let loadedImage = await ImageCacheHelper.shared.loadAndDownsample(fileURL: sourceURL, maxPixelSize: maxPixelSize)
            self.image = loadedImage
            self.isLoading = false
            return
        }
        
        self.isLoading = false
    }
}
