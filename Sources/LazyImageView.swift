import SwiftUI

/// SwiftUI View для ленивой загрузки и отображения картинок по их UUID
struct LazyImageView: View {
    let photoId: UUID
    var maxPixelSize: Int = 400
    var contentMode: ContentMode = .fit
    var isVideo: Bool = false
    
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
                    
                    if isVideo {
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
                        Image(systemName: isVideo ? "video" : "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        // .task автоматически перезапускает и отменяет загрузку при переиспользовании ячейки
        .task(id: photoId) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        let key = "\(photoId.uuidString)_\(maxPixelSize)"
        
        // Быстрый синхронный кэш на главном потоке
        if let cached = ImageCacheHelper.shared.getCachedImage(forKey: key) {
            self.image = cached
            return
        }
        
        isLoading = true
        let loadedImage = await ImageCacheHelper.shared.loadAndDownsample(
            photoId: photoId,
            fromDir: photosDirectoryURL,
            maxPixelSize: maxPixelSize
        )
        
        withAnimation(.easeIn(duration: 0.15)) {
            self.image = loadedImage
            self.isLoading = false
        }
    }
}
