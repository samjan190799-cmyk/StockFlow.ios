import SwiftUI
import WebKit
import AuthenticationServices

struct StockSignInHelperView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let platformId: String
    var onCredentialsFound: (String, String) -> Void
    
    @State private var webView = WKWebView()
    @State private var urlString = ""
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var currentURL: URL? = nil
    
    // Состояние авто-импорта
    @State private var detectedUsername: String? = nil
    @State private var detectedPassword: String? = nil
    @State private var showingImportAlert = false
    @State private var statusMessage = "Загрузка страницы..."
    
    // Конфигурация платформы
    private var config: HelperConfig {
        HelperConfig.config(for: platformId)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                VStack(spacing: 0) {
                    // Информационная панель-подсказка сверху
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Color(hex: "7C3AED"))
                                .font(.system(size: 14))
                            
                            Text("Инструкция по настройке FTP для \(config.name):")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colorScheme == .dark ? Color(hex: "1C1C1E").opacity(0.85) : Color.white.opacity(0.85))
                    .overlay(
                        VStack {
                            Spacer()
                            Divider().background(Color.primary.opacity(0.08))
                        }
                    )
                    
                    // Сама веб-страница
                    StockWebViewRepresentable(
                        webView: webView,
                        urlString: $urlString,
                        isLoading: $isLoading,
                        canGoBack: $canGoBack,
                        currentURL: $currentURL,
                        config: config,
                        onCredentialsDetected: { username, password in
                            HapticHelper.trigger(.success)
                            self.detectedUsername = username
                            self.detectedPassword = password
                            self.statusMessage = "Данные подключения обнаружены! Нажмите 'Импортировать' для сохранения."
                            self.showingImportAlert = true
                        },
                        onStatusChanged: { msg in
                            self.statusMessage = msg
                        }
                    )
                    .background(Color.white)
                    
                    // Панель управления снизу
                    VStack(spacing: 12) {
                        Divider().background(Color.primary.opacity(0.08))
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                HapticHelper.trigger(.light)
                                webView.goBack()
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(width: 44, height: 44)
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(Circle())
                            }
                            .disabled(!canGoBack)
                            .opacity(canGoBack ? 1.0 : 0.4)
                            
                            Button(action: {
                                HapticHelper.trigger(.light)
                                webView.reload()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(width: 44, height: 44)
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(Circle())
                            }
                            
                            Button(action: parseFromClipboard) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("Из буфера")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .frame(height: 44)
                                .padding(.horizontal, 10)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                            }
                            
                            Spacer()
                            
                            // Кнопка ручного сканирования страницы
                            Button(action: triggerManualScan) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text("Сканировать")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color(hex: "7C3AED"))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "7C3AED").opacity(0.3), radius: 6)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .background(colorScheme == .dark ? Color(hex: "1C1C1E").opacity(0.9) : Color.white.opacity(0.9))
                }
            }
            .navigationTitle("Вход: \(config.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        HapticHelper.trigger(.light)
                        dismiss()
                    }
                }
            }
            .onAppear {
                self.urlString = config.signInUrl
            }
            .alert("Учетные данные обнаружены", isPresented: $showingImportAlert) {
                Button("Импортировать") {
                    if let username = detectedUsername, let password = detectedPassword {
                        onCredentialsFound(username, password)
                        dismiss()
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Обнаружены данные для настройки \(config.name):\n\nЛогин: \(detectedUsername ?? "")\nПароль: ••••••••\n\nИмпортировать в настройки приложения?")
            }
        }
    }
    
    // Ручное сканирование с помощью универсального JS-скрипта
    private func triggerManualScan() {
        HapticHelper.trigger(.medium)
        statusMessage = "Анализируем содержимое страницы..."
        
        let hostPattern = config.host
        let scanScript = """
        (function() {
            var html = document.body.innerText;
            var htmlLower = html.toLowerCase();
            var username = null;
            var password = null;
            
            // 1. Поиск инпутов
            var inputs = document.querySelectorAll('input[type="text"], input[type="password"], input[type="email"]');
            for (var i = 0; i < inputs.length; i++) {
                var input = inputs[i];
                var placeholder = (input.placeholder || "").toLowerCase();
                var id = (input.id || "").toLowerCase();
                var name = (input.name || "").toLowerCase();
                var val = input.value;
                
                if (!val || val.length < 4) continue;
                
                // Ищем пароли
                if (placeholder.includes("password") || placeholder.includes("pass") || placeholder.includes("пароль") || 
                    id.includes("password") || id.includes("pass") || name.includes("password")) {
                    password = val;
                }
                
                // Ищем юзернейм
                if (placeholder.includes("username") || placeholder.includes("user") || placeholder.includes("login") || 
                    placeholder.includes("логин") || id.includes("username") || id.includes("user") || name.includes("username")) {
                    username = val;
                }
            }
            
            // 2. Парсинг текстовых полей, если инпуты пустые
            if (!username) {
                // Ищем ID контрибьютора (обычно число 6-11 цифр)
                var digits = html.match(/\\b\\d{6,11}\\b/g);
                if (digits && digits.length > 0) {
                    username = digits[0];
                }
            }
            
            if (!password) {
                // Пытаемся найти сгенерированные пароли: буквенно-цифровые комбинации длиной 8-16 символов
                var candidates = html.match(/\\b[a-zA-Z0-9]{8,16}\\b/g);
                if (candidates) {
                    for (var j = 0; j < candidates.length; j++) {
                        var cand = candidates[j];
                        // Пароль должен содержать и буквы, и цифры, и не быть стандартным словом типа 'Shutterstock'
                        if (/[a-zA-Z]/.test(cand) && /[0-9]/.test(cand) && cand.toLowerCase() !== "\(config.id)") {
                            // Ищем наличие ключевых слов рядом (в радиусе 120 символов)
                            var idx = html.indexOf(cand);
                            var rangeText = html.substring(Math.max(0, idx - 120), Math.min(html.length, idx + 120)).toLowerCase();
                            if (rangeText.includes("ftp") || rangeText.includes("sftp") || rangeText.includes("password") || rangeText.includes("пароль")) {
                                password = cand;
                                break;
                            }
                        }
                    }
                }
            }
            
            if (username || password) {
                return { username: username, password: password };
            }
            return null;
        })();
        """
        
        webView.evaluateJavaScript(scanScript) { result, error in
            if let dict = result as? [String: Any],
               let u = dict["username"] as? String,
               let p = dict["password"] as? String {
                self.detectedUsername = u
                self.detectedPassword = p
                self.showingImportAlert = true
                self.statusMessage = "Данные успешно обнаружены!"
            } else {
                // Если не получилось авто-распознать оба поля, пытаемся выудить хотя бы юзернейм
                let userScript = "document.body.innerText.match(/\\b\\d{6,11}\\b/)"
                webView.evaluateJavaScript(userScript) { uRes, _ in
                    if let matchArr = uRes as? [String], let foundUser = matchArr.first {
                        self.detectedUsername = foundUser
                        self.statusMessage = "Найдено имя пользователя/ID: \(foundUser). Скопируйте пароль FTP со страницы вручную."
                    } else {
                        self.statusMessage = "Не удалось распознать данные на текущей странице. Убедитесь, что вы авторизовались и перешли в раздел настроек FTP/SFTP."
                    }
                }
            }
        }
    }
    
    // Ручной импорт из буфера обмена
    private func parseFromClipboard() {
        HapticHelper.trigger(.light)
        guard let clipboardString = UIPasteboard.general.string, !clipboardString.isEmpty else {
            statusMessage = "Буфер обмена пуст."
            return
        }
        
        // Пытаемся распарсить буфер обмена по строкам
        let lines = clipboardString.components(separatedBy: .newlines)
        var username: String? = nil
        var password: String? = nil
        
        for line in lines {
            let lower = line.toLowerCase()
            let parts = line.components(separatedBy: ":")
            if parts.count >= 2 {
                let value = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                if lower.contains("user") || lower.contains("login") || lower.contains("логин") || lower.contains("имя") || lower.contains("id") {
                    username = value
                } else if lower.contains("pass") || lower.contains("пароль") || lower.contains("key") {
                    password = value
                }
            }
        }
        
        // Резервный вариант: если строки не содержат двоеточий, ищем просто регулярками в буфере
        if username == nil {
            let digits = clipboardString.match("\\b\\d{6,11}\\b")
            username = digits.first
        }
        
        if password == nil {
            // Ищем строку буквенно-цифровую длиной 8-16 символов
            let candidates = clipboardString.match("\\b[a-zA-Z0-9]{8,16}\\b")
            password = candidates.first(where: { cand in
                let hasLetters = cand.rangeOfCharacter(from: CharacterSet.letters) != nil
                let hasDigits = cand.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
                return hasLetters && hasDigits
            })
        }
        
        if let u = username, let p = password {
            self.detectedUsername = u
            self.detectedPassword = p
            self.showingImportAlert = true
            self.statusMessage = "Данные успешно импортированы из буфера обмена!"
        } else {
            // Если распарсить не удалось, но в буфере есть хоть какая-то строка, даем ее как пароль, а логин просим ввести
            if clipboardString.count >= 8 && clipboardString.count <= 25 && clipboardString.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                self.detectedPassword = clipboardString
                self.statusMessage = "Строка из буфера распознана как пароль. Пожалуйста, введите логин вручную."
                self.detectedUsername = ""
                self.showingImportAlert = true
            } else {
                statusMessage = "Не удалось распознать формат данных в буфере. Скопируйте данные FTP и повторите попытку."
            }
        }
    }
}

// MARK: - Helper Configuration
struct HelperConfig {
    let id: String
    let name: String
    let signInUrl: String
    let host: String
    let instruction: String
    
    static func config(for id: String) -> HelperConfig {
        switch id {
        case "adobe":
            return HelperConfig(
                id: id,
                name: "Adobe Stock",
                signInUrl: "https://contributor.adobestock.com/",
                host: "sftp.contributor.adobestock.com",
                instruction: "Войдите. Перейдите в правый верхний угол -> Настройки учетной записи -> Настройки FTP."
            )
        case "shutterstock":
            return HelperConfig(
                id: id,
                name: "Shutterstock",
                signInUrl: "https://submit.shutterstock.com/",
                host: "ftp.shutterstock.com",
                instruction: "Войдите в кабинет. Перейдите в Account Settings -> FTP Section."
            )
        case "istock":
            return HelperConfig(
                id: id,
                name: "iStock / Getty",
                signInUrl: "https://esp.gettyimages.com/",
                host: "ftp.gettyimages.com",
                instruction: "Войдите на портал ESP. Откройте ваш профиль автора и перейдите в настройки FTP."
            )
        case "freepik":
            return HelperConfig(
                id: id,
                name: "Freepik",
                signInUrl: "https://contributor.freepik.com/",
                host: "sftp.contributor-ftp.freepik.com",
                instruction: "Войдите во Freepik Contributor. Перейдите во вкладку 'My Devices' для получения пароля."
            )
        case "depositphotos":
            return HelperConfig(
                id: id,
                name: "Depositphotos",
                signInUrl: "https://cl.depositphotos.com/",
                host: "ftp.depositphotos.com",
                instruction: "Войдите в панель поставщика. Откройте Настройки профиля -> Загрузка по FTP."
            )
        case "alamy":
            return HelperConfig(
                id: id,
                name: "Alamy",
                signInUrl: "https://contributor.alamy.com/",
                host: "ftp.upload.alamy.com",
                instruction: "Войдите на портал Alamy. Откройте раздел Upload & FTP settings."
            )
        case "dreamstime":
            return HelperConfig(
                id: id,
                name: "Dreamstime",
                signInUrl: "https://www.dreamstime.com/login",
                host: "ftp.upload.dreamstime.com",
                instruction: "Войдите в аккаунт. Перейдите в Management Area -> FTP Upload."
            )
        case "123rf":
            return HelperConfig(
                id: id,
                name: "123RF",
                signInUrl: "https://www.123rf.com/contributors/",
                host: "ftp.123rf.com",
                instruction: "Войдите в кабинет автора 123RF. Перейдите в раздел настройки FTP."
            )
        case "pond5":
            return HelperConfig(
                id: id,
                name: "Pond5",
                signInUrl: "https://www.pond5.com/login",
                host: "ftp.pond5.com",
                instruction: "Войдите в аккаунт. Перейдите в Uploads -> FTP Preferences."
            )
        default:
            return HelperConfig(
                id: id,
                name: "Фотосток",
                signInUrl: "https://google.com",
                host: "ftp.example.com",
                instruction: "Войдите в кабинет автора и перейдите на страницу параметров загрузки по FTP."
            )
        }
    }
}

// MARK: - WebView Representable
struct StockWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    @Binding var urlString: String
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var currentURL: URL?
    
    let config: HelperConfig
    var onCredentialsDetected: (String, String) -> Void
    var onStatusChanged: (String) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        let configuration = webView.configuration
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: StockWebViewRepresentable
        
        init(_ parent: StockWebViewRepresentable) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.onStatusChanged("Загрузка страницы...")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.canGoBack = webView.canGoBack
            parent.currentURL = webView.url
            
            let urlStr = webView.url?.absoluteString ?? ""
            
            // Анализ URL для вывода подсказок
            if urlStr.contains("login") || urlStr.contains("signin") || urlStr.contains("auth") {
                parent.onStatusChanged("Пожалуйста, выполните вход в свой аккаунт \(parent.config.name) (можно использовать Google/Apple при наличии).")
            } else {
                // Подсказка на основе инструкции конфигурации стока
                parent.onStatusChanged("Вы вошли. \(parent.config.instruction) После перехода нажмите кнопку 'Сканировать'.")
                
                // Пробуем запустить авто-сканирование через 2 секунды
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.autoScanPage(webView: webView)
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.onStatusChanged("Ошибка соединения: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        private func autoScanPage(webView: WKWebView) {
            let scanScript = """
            (function() {
                var html = document.body.innerText;
                var username = null;
                var password = null;
                
                // Простой поиск ID
                var idMatch = html.match(/\\b\\d{7,10}\\b/);
                if (idMatch) { username = idMatch[0]; }
                
                // Поиск полей ввода
                var inputs = document.querySelectorAll('input[type="text"], input[type="password"]');
                for (var i = 0; i < inputs.length; i++) {
                    var input = inputs[i];
                    var placeholder = (input.placeholder || "").toLowerCase();
                    var value = input.value;
                    if ((placeholder.includes("password") || placeholder.includes("ftp") || placeholder.includes("pass")) && value && value.length >= 8) {
                        password = value;
                    }
                }
                
                if (username && password) {
                    return { username: username, password: password };
                }
                return null;
            })();
            """
            
            webView.evaluateJavaScript(scanScript) { result, _ in
                if let dict = result as? [String: Any],
                   let username = dict["username"] as? String,
                   let password = dict["password"] as? String {
                    self.parent.onCredentialsDetected(username, password)
                }
            }
        }
    }
}

// MARK: - String Regex Extension for Parser
extension String {
    func match(_ regex: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let results = regex.matches(in: self, range: NSRange(location: 0, length: self.utf16.count))
            return results.compactMap { match in
                guard let range = Range(match.range, in: self) else { return nil }
                return String(self[range])
            }
        } catch {
            return []
        }
    }
    
    func toLowerCase() -> String {
        self.lowercased()
    }
}
