import Foundation

extension String {
    var localized: String {
        let currentLang = UserDefaults.standard.string(forKey: "sys_language") ?? "Русский"
        if currentLang == "English" {
            return Localizer.translate(self)
        }
        return self
    }
}

struct Localizer {
    private static let translations: [String: String] = [
        // Экран параметров системы
        "Параметры системы": "System Settings",
        "Интерфейс": "Interface",
        "Язык интерфейса": "App Language",
        "Тема оформления": "Theme",
        "Темная": "Dark",
        "Светлая": "Light",
        "Системная": "System",
        "Предел частоты кадров": "Frame Rate Limit",
        "Планировщик": "Scheduler",
        "Фоновый планировщик выгрузки": "Background Upload Scheduler",
        "При активации планировщика система будет проверять новые фото и отправлять их в фоновом режиме.": "When activated, the system will check for new photos and upload them in the background.",
        "Автоматический Апскейл": "Auto Upscale",
        "Включить авто-апскейл": "Enable Auto-Upscale",
        "Порог срабатывания": "Trigger Threshold",
        "Коэффициент (масштаб)": "Scale Factor",
        "Параметры выгрузки": "Upload Parameters",
        "Потоки параллельной загрузки": "Parallel Upload Streams",
        "Автоповтор при сбоях": "Auto-retry on failures",
        "Сжатие JPEG перед загрузкой": "Compress JPEG before upload",
        "Системные уведомления": "System Notifications",
        "Локальный ПК-сервер": "Local PC Server",
        "Загрузка через ПК-сервер": "Upload via PC Server",
        "Адрес сервера (IP:Порт)": "Server Address (IP:Port)",
        "Позволяет отправлять фото через программу на вашем компьютере. Полезно, если на телефоне блокируется FTPS к Shutterstock.": "Allows sending photos via the app on your computer. Useful if FTPS to Shutterstock is blocked on the phone.",
        "Облачная синхронизация": "Cloud Sync",
        "Синхронизация профиля активна": "Profile sync is active",
        "Выйти": "Sign Out",
        "Войдите в аккаунт, чтобы синхронизировать ваши настройки стоков и ключи API в облаке.": "Sign in to synchronize your stock settings and API keys in the cloud.",
        "Вход с Google": "Sign in with Google",
        "Сохранить все настройки": "Save All Settings",
        
        // Экран стоков
        "Интегрированные фотостоки": "Integrated Stock Agencies",
        "Настройки стоков": "Stock Settings",
        "Проверка соединения...": "Verifying connection...",
        "Настроен": "Configured",
        "Нужна настройка": "Setup required",
        "Параметры SFTP / FTP для": "SFTP / FTP parameters for",
        "Активен": "Active",
        "Имя пользователя (логин)": "Username (login)",
        "Пароль": "Password",
        "Дополнительные параметры сервера": "Advanced Server Parameters",
        "Имя хоста (сервер)": "Hostname (server)",
        "Проверить соединение": "Test Connection",
        "Проверка...": "Testing...",
        "Готово": "Done",
        "Подключение": "Connection",
        "Пожалуйста, введите логин и пароль.": "Please enter username and password.",
        
        // Вкладки таб-бара
        "Очередь": "Queue",
        "ИИ-Ассистент": "AI Assistant",
        "Стоки": "Stocks",
        "Параметры": "Settings",
        
        // Экран очереди загрузки
        "Очередь выгрузки": "Upload Queue",
        "Готовы к загрузке": "Ready to upload",
        "Загружено": "Uploaded",
        "В очереди": "In Queue",
        "Ошибки": "Errors",
        "Добавить фото": "Add Photos",
        "Загрузить все": "Upload All",
        "ИИ Анализ": "AI Analysis",
        "Удалить": "Delete",
        "Редактировать": "Edit",
        "Настройки стоков для фото": "Stock settings for photo",
        "Файл": "File",
        "Размер": "Size",
        "Статус": "Status",
        
        // ИИ-Ассистент
        "Интеллектуальный ассистент": "AI Assistant",
        "Генерация ключевых слов и описаний с помощью ИИ": "AI Keywording and Description Generator",
        "Анализ изображения": "Analyze Image",
        "Результаты анализа": "Analysis Results",
        "Название": "Title",
        "Описание": "Description",
        "Ключевые слова": "Keywords",
        "Категории": "Categories",
        "Скопировать все": "Copy All",
        "Применить к фото": "Apply to Photo"
    ]
    
    static func translate(_ text: String) -> String {
        if let translation = translations[text] {
            return translation
        }
        
        // Поиск по префиксам для динамических строк
        for (key, value) in translations {
            if text.hasPrefix(key) {
                return text.replacingOccurrences(of: key, with: value)
            }
        }
        
        return text
    }
}
