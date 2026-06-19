import Foundation

// Сервис для работы со списками фильмов (Стиль 2026: асинхронные интерфейсы, структурированное concurrency)
@MainActor
public final class MovieService: ObservableObject {
    
    @Published public private(set) var movies: [Movie] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    
    public init() {
        // Загрузка начальных данных
        loadMockMovies()
    }
    
    // Асинхронный метод для обновления каталога
    public func fetchCatalog() async {
        isLoading = true
        errorMessage = nil
        
        // Имитируем сетевую задержку для плавности UI
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 секунда
            loadMockMovies()
        } catch {
            errorMessage = "Не удалось обновить каталог"
        }
        
        isLoading = false
    }
    
    // Поиск фильма по названию
    public func searchMovies(query: String) -> [Movie] {
        guard !query.isEmpty else { return movies }
        return movies.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.originalTitle.localizedCaseInsensitiveContains(query) }
    }
    
    // Метод парсинга сайта kinogo.ec (Заготовка под парсер)
    // Cloudflare выдает 403 при стандартных запросах, поэтому здесь будет выполняться
    // расширенное проксирование или симуляция браузера в будущих версиях.
    public func fetchFromKinogoWebsite() async throws -> [Movie] {
        // В будущем здесь будет использоваться SwiftSoup с кастомным URLSession
        // и настроенными cookies/User-Agent для обхода Cloudflare.
        // Сейчас возвращаем mock-каталог во избежание сбоев в работе приложения.
        return movies
    }
    
    // Наполнение базы данных красивыми реалистичными фильмами
    private func loadMockMovies() {
        self.movies = [
            Movie(
                id: "1",
                title: "Дюна: Часть вторая",
                originalTitle: "Dune: Part Two",
                description: "Пол Атрейдес объединяется с Чани и фременами, чтобы отомстить заговорщикам, уничтожившим его семью. Между любовью всей своей жизни и судьбой известной вселенной он пытается предотвратить ужасное будущее, которое может предвидеть только он.",
                rating: 8.5,
                year: 2024,
                duration: "2 ч 46 мин",
                genres: ["Фантастика", "Приключения", "Драма"],
                director: "Дени Вильнёв",
                actors: ["Тимоти Шаламе", "Зендея", "Ребекка Фергюсон", "Остин Батлер"],
                posterURL: "https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?q=80&w=600&auto=format&fit=crop",
                videoURL: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", // Реальный HLS видеопоток (Tears of Steel)
                isFeatured: true
            ),
            Movie(
                id: "2",
                title: "Оппенгеймер",
                originalTitle: "Oppenheimer",
                description: "История жизни американского физика Роберта Оппенгеймера, который стоял во главе первых разработок ядерного оружия во время Второй мировой войны, навсегда изменивших ход истории.",
                rating: 8.4,
                year: 2023,
                duration: "3 ч 0 мин",
                genres: ["Биография", "Драма", "История"],
                director: "Кристофер Нолан",
                actors: ["Киллиан Мерфи", "Эмили Блант", "Мэтт Дэймон", "Роберт Дауни мл."],
                posterURL: "https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=600&auto=format&fit=crop",
                videoURL: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8", // Реальный HLS видеопоток
                isFeatured: false
            ),
            Movie(
                id: "3",
                title: "Интерстеллар",
                originalTitle: "Interstellar",
                description: "Когда засуха, пыльные бури и вымирание растений приводят человечество к продовольственному кризису, группа исследователей отправляется в путешествие сквозь червоточину в поисках новой планеты для жизни.",
                rating: 8.6,
                year: 2014,
                duration: "2 ч 49 мин",
                genres: ["Фантастика", "Драма", "Приключения"],
                director: "Кристофер Нолан",
                actors: ["Мэттью Макконахи", "Энн Хэтэуэй", "Джессика Честейн"],
                posterURL: "https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?q=80&w=600&auto=format&fit=crop",
                videoURL: "https://storage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4", // MP4 поток
                isFeatured: false
            ),
            Movie(
                id: "4",
                title: "Бегущий по лезвию 2049",
                originalTitle: "Blade Runner 2049",
                description: "Офицер Кей — новый блейд-раннер в Лос-Анджелесе. Он раскрывает давно погребенную тайну, которая может погрузить остатки общества в хаос, и отправляется на поиски Рика Декарда, пропавшего много лет назад.",
                rating: 8.0,
                year: 2017,
                duration: "2 ч 44 мин",
                genres: ["Фантастика", "Боевик", "Триллер"],
                director: "Дени Вильнёв",
                actors: ["Райан Гослинг", "Харрисон Форд", "Ана де Армас"],
                posterURL: "https://images.unsplash.com/photo-1514565131-fce0801e5785?q=80&w=600&auto=format&fit=crop",
                videoURL: "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", // MP4 поток
                isFeatured: false
            ),
            Movie(
                id: "5",
                title: "Аватар: Путь воды",
                originalTitle: "Avatar: The Way of Water",
                description: "После принятия человеческого облика Джейк Салли становится предводителем народа на’ви и берет на себя миссию по защите семьи от новых угроз, пришедших из космоса.",
                rating: 7.8,
                year: 2022,
                duration: "3 ч 12 мин",
                genres: ["Фантастика", "Боевик", "Приключения"],
                director: "Джеймс Кэмерон",
                actors: ["Сэм Уортингтон", "Зои Салдана", "Сигурни Уивер"],
                posterURL: "https://images.unsplash.com/photo-1518837695005-2083093ee35b?q=80&w=600&auto=format&fit=crop",
                videoURL: "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4", // MP4 поток
                isFeatured: false
            )
        ]
    }
}
