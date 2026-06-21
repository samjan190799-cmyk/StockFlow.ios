import Foundation
import SwiftUI
import Combine

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated: Bool {
        didSet {
            UserDefaults.standard.set(isAuthenticated, forKey: "auth_is_authenticated")
        }
    }
    
    @Published var currentUserEmail: String? {
        didSet {
            UserDefaults.standard.set(currentUserEmail, forKey: "auth_user_email")
        }
    }
    
    private init() {
        self.isAuthenticated = UserDefaults.standard.bool(forKey: "auth_is_authenticated")
        self.currentUserEmail = UserDefaults.standard.string(forKey: "auth_user_email")
    }
    
    /// Симуляция входа по Email и паролю
    func login(email: String, password: String) async throws -> Bool {
        // Простая валидация перед "сетевым запросом"
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmedEmail) else {
            throw NSError(domain: "Auth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный формат Email".localized])
        }
        
        guard password.count >= 6 else {
            throw NSError(domain: "Auth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Пароль должен содержать не менее 6 символов".localized])
        }
        
        // Симулируем сетевую задержку
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Имитируем успешный вход
        self.currentUserEmail = trimmedEmail
        self.isAuthenticated = true
        return true
    }
    
    /// Симуляция регистрации
    func register(email: String, password: String) async throws -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmedEmail) else {
            throw NSError(domain: "Auth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный формат Email".localized])
        }
        
        guard password.count >= 6 else {
            throw NSError(domain: "Auth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Пароль должен содержать не менее 6 символов".localized])
        }
        
        // Симулируем сетевую задержку
        try await Task.sleep(nanoseconds: 1_200_000_000)
        
        // Имитируем успешную регистрацию
        self.currentUserEmail = trimmedEmail
        self.isAuthenticated = true
        return true
    }
    
    /// Симуляция входа через Apple ID
    func loginWithApple(email: String = "apple.user@icloud.com") async throws -> Bool {
        // Симулируем быструю авторизацию лица/отпечатка
        try await Task.sleep(nanoseconds: 800_000_000)
        
        self.currentUserEmail = email
        self.isAuthenticated = true
        return true
    }
    
    /// Симуляция входа через Google
    func loginWithGoogle(email: String = "google.user@gmail.com") async throws -> Bool {
        // Симулируем выбор аккаунта Google
        try await Task.sleep(nanoseconds: 900_000_000)
        
        self.currentUserEmail = email
        self.isAuthenticated = true
        return true
    }
    
    /// Выход из системы
    func logout() {
        self.currentUserEmail = nil
        self.isAuthenticated = false
    }
    
    // Вспомогательный метод валидации email
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}
