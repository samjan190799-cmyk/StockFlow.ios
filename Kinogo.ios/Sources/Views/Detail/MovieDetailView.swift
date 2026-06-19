import SwiftUI

// Экран детального описания фильма (Стиль 2026: обилие воздуха, тонкие линии, отсутствие визуального шума)
public struct MovieDetailView: View {
    let movie: Movie
    
    @Environment(\.dismiss) private var dismiss
    @State private var showPlayer = false
    
    public init(movie: Movie) {
        self.movie = movie
    }
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Блок постера с эффектом мягкого затемнения к низу
                ZStack(alignment: .bottomLeading) {
                    // Загрузка обложки фильма с плавным появлением
                    AsyncImage(url: URL(string: movie.posterURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 480)
                                .clipped()
                                .transition(.opacity)
                        case .failure:
                            // Мягкий нейтральный фон в случае сбоя сети
                            Rectangle()
                                .fill(Theme.Colors.surface)
                                .frame(height: 480)
                                .overlay(
                                    Image(systemName: "film")
                                        .font(.system(size: 40, weight: .light))
                                        .foregroundColor(Theme.Colors.secondaryText)
                                )
                        case .empty:
                            Rectangle()
                                .fill(Theme.Colors.surface)
                                .frame(height: 480)
                                .overlay(
                                    ProgressView()
                                        .tint(Theme.Colors.accent)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    
                    // Мягкий градиент для плавного перехода в фоновый цвет
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Theme.Colors.background.opacity(0.3),
                            Theme.Colors.background.opacity(0.8),
                            Theme.Colors.background
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 300)
                    
                    // Заголовок поверх постера
                    VStack(alignment: .leading, spacing: 6) {
                        Text(movie.title)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(Theme.Colors.primaryText)
                        
                        Text(movie.originalTitle)
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                
                // Информационная панель (Рейтинг, Год, Длительность)
                HStack(spacing: 24) {
                    // Рейтинг
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.accent)
                        Text(String(format: "%.1f", movie.rating))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.Colors.primaryText)
                    }
                    
                    // Год
                    Text(String(movie.year))
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(Theme.Colors.secondaryText)
                    
                    // Длительность
                    Text(movie.duration)
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(Theme.Colors.secondaryText)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Theme.Colors.surface.opacity(0.3))
                .cornerRadius(Theme.Radius.card)
                .modifier(FineBorderModifier())
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                
                // Кнопка Смотреть (Стиль 2026 - сдержанная, плоская, спокойный оливково-золотой фон)
                Button(action: {
                    showPlayer = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                        Text("Смотреть фильм")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(Theme.Colors.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.Colors.accent)
                    .cornerRadius(Theme.Radius.button)
                    .padding(.horizontal, 20)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.bottom, 32)
                
                // Описание сюжета
                VStack(alignment: .leading, spacing: 12) {
                    Text("Сюжет")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    Text(movie.description)
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(Theme.Colors.secondaryText)
                        .lineSpacing(6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                
                // Детали (Режиссер, Актеры, Жанры)
                VStack(alignment: .leading, spacing: 20) {
                    Text("О фильме")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Theme.Colors.primaryText)
                    
                    // Жанры
                    DetailRow(title: "Жанры", value: movie.genres.joined(separator: ", "))
                    
                    // Режиссер
                    DetailRow(title: "Режиссер", value: movie.director)
                    
                    // Актерский состав
                    DetailRow(title: "В главных ролях", value: movie.actors.joined(separator: ", "))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(Theme.Colors.primaryText)
                        .padding(8)
                        .background(Theme.Colors.surface.opacity(0.8))
                        .clipShape(Circle())
                        .modifier(FineBorderModifier())
                }
            }
        }
        // Переход на экран полноэкранного плеера
        .fullScreenCover(isPresented: $showPlayer) {
            if let videoURL = URL(string: movie.videoURL) {
                VideoPlayerView(videoURL: videoURL, movieTitle: movie.title)
            }
        }
    }
}

// Строка информации о фильме для секции "О фильме"
struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(Theme.Colors.secondaryText)
            
            Text(value)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Theme.Colors.primaryText)
        }
    }
}

// Элегантная пружинная анимация для кнопки "Смотреть"
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Animations.swiftTransition, value: configuration.isPressed)
    }
}
