import SwiftUI

// Главный экран приложения (Стиль 2026: просторные отступы, тонкие границы, спокойная палитра)
public struct HomeView: View {
    @StateObject private var service = MovieService()
    @State private var searchQuery = ""
    @State private var selectedGenre: String? = nil
    
    // Список доступных жанров для фильтрации
    private let genresList = ["Все", "Фантастика", "Приключения", "Драма", "Биография", "История"]
    
    public init() {
        // Настройка внешнего вида UINavigationBar для корректного отображения в темном стиле
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.Colors.primaryText)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.Colors.primaryText)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        
                        // Заголовок и Профиль
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Кинозал")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(Theme.Colors.primaryText)
                                Text("Спокойный просмотр кино")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            Spacer()
                            
                            // Минималистичная иконка профиля с тонкой гранью
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(Theme.Colors.accent)
                                .padding(8)
                                .background(Theme.Colors.surface)
                                .clipShape(Circle())
                                .modifier(FineBorderModifier())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        
                        // Строка поиска (Стиль 2026: без теней, с тонкой рамкой, сливается с фоном)
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Theme.Colors.secondaryText)
                                .font(.system(size: 16, weight: .light))
                            
                            TextField("Поиск фильмов, режиссеров...", text: $searchQuery)
                                .foregroundColor(Theme.Colors.primaryText)
                                .font(.system(size: 15, weight: .light))
                                .tint(Theme.Colors.accent)
                            
                            if !searchQuery.isEmpty {
                                Button(action: { searchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.surface)
                        .cornerRadius(Theme.Radius.card)
                        .modifier(FineBorderModifier())
                        .padding(.horizontal, 20)
                        
                        // Если идет поиск, показываем результаты
                        if !searchQuery.isEmpty {
                            SearchResultsView(movies: service.searchMovies(query: searchQuery))
                        } else {
                            // Рекомендуемый фильм (Hero Section)
                            if let featuredMovie = service.movies.first(where: { $0.isFeatured }) {
                                NavigationLink(value: featuredMovie) {
                                    HeroBannerView(movie: featuredMovie)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal, 20)
                            }
                            
                            // Карусель жанров (Селекторы)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Категории")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Theme.Colors.primaryText)
                                    .padding(.horizontal, 20)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(genresList, id: \.self) { genre in
                                            GenreTag(
                                                title: genre,
                                                isSelected: (selectedGenre == nil && genre == "Все") || selectedGenre == genre,
                                                action: {
                                                    withAnimation(Theme.Animations.swiftTransition) {
                                                        if genre == "Все" {
                                                            selectedGenre = nil
                                                        } else {
                                                            selectedGenre = genre
                                                        }
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            
                            // Фильтрованный список или Новинки
                            let filteredMovies = getFilteredMovies()
                            
                            VStack(alignment: .leading, spacing: 16) {
                                Text(selectedGenre == nil ? "Рекомендуем посмотреть" : "В жанре \(selectedGenre!)")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Theme.Colors.primaryText)
                                    .padding(.horizontal, 20)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(filteredMovies) { movie in
                                            NavigationLink(value: movie) {
                                                MovieCardView(movie: movie)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie)
            }
        }
    }
    
    private func getFilteredMovies() -> [Movie] {
        guard let genre = selectedGenre else { return service.movies }
        return service.movies.filter { $0.genres.contains(genre) }
    }
}

// Большой баннер для рекомендуемого фильма дня
struct HeroBannerView: View {
    let movie: Movie
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: movie.posterURL)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 220)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Theme.Colors.surface)
                            .frame(height: 220)
                            .overlay(ProgressView().tint(Theme.Colors.accent))
                    }
                }
                
                // Затемнение низа баннера
                LinearGradient(
                    gradient: Gradient(colors: [.clear, Color.black.opacity(0.85)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                
                // Текст поверх баннера
                VStack(alignment: .leading, spacing: 6) {
                    Text("В центре внимания")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.Colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.surface.opacity(0.8))
                        .cornerRadius(4)
                        .modifier(FineBorderModifier())
                    
                    Text(movie.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(movie.genres.joined(separator: ", "))
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(16)
            }
        }
        .cornerRadius(Theme.Radius.large)
        .modifier(FineBorderModifier())
    }
}

// Карточка фильма в карусели
struct MovieCardView: View {
    let movie: Movie
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: URL(string: movie.posterURL)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 140, height: 210)
                        .cornerRadius(Theme.Radius.card)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .fill(Theme.Colors.surface)
                        .frame(width: 140, height: 210)
                        .overlay(ProgressView().tint(Theme.Colors.accent))
                }
            }
            .modifier(FineBorderModifier())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Text(String(movie.year))
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(Theme.Colors.secondaryText)
                    
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.Colors.accent)
                        Text(String(format: "%.1f", movie.rating))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.Colors.primaryText)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 140)
    }
}

// Тег жанра для фильтрации
struct GenreTag: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .medium : .light))
                .foregroundColor(isSelected ? Theme.Colors.background : Theme.Colors.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
                .cornerRadius(Theme.Radius.button)
                .modifier(FineBorderModifier())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// Результаты поиска
struct SearchResultsView: View {
    let movies: [Movie]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Результаты поиска")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Theme.Colors.primaryText)
                .padding(.horizontal, 20)
            
            if movies.isEmpty {
                Text("Ничего не найдено")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(movies) { movie in
                        NavigationLink(value: movie) {
                            HStack(spacing: 16) {
                                AsyncImage(url: URL(string: movie.posterURL)) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 90)
                                            .cornerRadius(Theme.Radius.card)
                                    } else {
                                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                                            .fill(Theme.Colors.surface)
                                            .frame(width: 60, height: 90)
                                    }
                                }
                                .modifier(FineBorderModifier())
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(movie.title)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(Theme.Colors.primaryText)
                                    
                                    Text("\(movie.genres.joined(separator: ", ")) • \(movie.year)")
                                        .font(.system(size: 13, weight: .light))
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    
                                    HStack(spacing: 2) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.Colors.accent)
                                        Text(String(format: "%.1f", movie.rating))
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Theme.Colors.primaryText)
                                    }
                                }
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.Colors.surface.opacity(0.4))
                            .cornerRadius(Theme.Radius.card)
                            .modifier(FineBorderModifier())
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
}
