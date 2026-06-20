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
        "Применить к фото": "Apply to Photo",
        
        // Новые переводы для настроек
        "Меньше 4 МБ (Рекомендуется)": "Less than 4 MB (Recommended)",
        "Меньше 2 МБ": "Less than 2 MB",
        "Меньше 8 МБ": "Less than 8 MB",
        "Увеличение 2x (Бикубическое)": "Scale 2x (Bicubic)",
        "Увеличение 4x (Нейросеть)": "Scale 4x (Neural Network)",
        "120 FPS (Ультра-плавность)": "120 FPS (Ultra-smooth)",
        "60 FPS (Стандартный)": "60 FPS (Standard)",
        "30 FPS (Энергосбережение)": "30 FPS (Power Saving)",
        "Русский": "Russian",
        "English": "English",
        "Настройки сохранены!": "Settings saved!",
        "Настройки успешно сохранены!": "Settings successfully saved!",
        "Успешный вход через Apple!": "Successfully signed in with Apple!",
        "Успешный вход через Google!": "Successfully signed in with Google!",
        "Вход с Google": "Sign in with Google",
        "Сохранить все настройки": "Save All Settings",
        "Автоповтор при сбоях": "Auto-retry on failures",
        "Сжатие JPEG перед загрузкой": "Compress JPEG before upload",
        "Системные уведомления": "System Notifications",
        "Адрес сервера (IP:Порт)": "Server Address (IP:Port)",
        "Локальный ПК-сервер": "Local PC Server",
        "Загрузка через ПК-сервер": "Upload via PC Server",
        "Облачная синхронизация": "Cloud Sync",
        "Выйти": "Sign Out",
        "Войдите в аккаунт, чтобы синхронизировать ваши настройки стоков и ключи API в облаке.": "Sign in to synchronize your stock settings and API keys in the cloud.",
        "Частота кадров: ": "Frame rate: ",
        " — применится при запуске": " — will apply on restart",
        "Параллельные потоки: ": "Parallel streams: ",
        " — применится при следующей загрузке": " — will apply on next upload",
        "Авто-апскейл включён — работает при добавлении фото": "Auto-upscale enabled — works when adding photos",
        "Авто-апскейл отключён": "Auto-upscale disabled",
        "Язык изменён на Русский": "Language changed to Russian",
        "Language changed to English": "Language changed to English",
        "Параметры системы": "System Settings",
        "Интерфейс": "Interface",
        "Язык интерфейса": "App Language",
        "Тема оформления": "Theme",
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
        "Позволяет отправлять фото через программу на вашем компьютере. Полезно, если на телефоне блокируется FTPS к Shutterstock.": "Allows sending photos via the app on your computer. Useful if FTPS to Shutterstock is blocked on the phone.",
        "Облачная синхронизация": "Cloud Sync",
        "Синхронизация профиля активна": "Profile sync is active",
        "поток": "stream",
        "потока": "streams",
        "потоков": "streams",
        "Авторизация...": "Signing in...",
        
        // Экран настроек стоков
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
        "Успешное соединение с сервером": "Successfully connected to server",
        "Ошибка соединения с": "Connection error with",
        "Внимание: Данный сток требует SFTP. Plain FTP-соединение для него может быть недоступно.": "Warning: This stock requires SFTP. Plain FTP connection may not be available.",
        
        // Новые переводы для Очереди
        "Ошибка: Нет активных стоков или не введены логин/пароль!": "Error: No active stock agencies configured or credentials missing!",
        "Загрузка файла": "Uploading file",
        "Нет файлов, готовых к отправке.": "No files ready for upload.",
        "Файл": "File",
        "успешно загружен на стоки!": "successfully uploaded to stocks!",
        "Ошибка выгрузки": "Upload error",
        "успешно загружен!": "successfully uploaded!",
        "Ошибка:": "Error:",
        "Все файлы обработаны!": "All files processed!",
        "Началась отправка": "Started upload of",
        "файлов": "files",
        "Успешная выгрузка": "Upload Successful"
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
