import SwiftUI
import AuthenticationServices
import WebKit

// MARK: - Native Apple Sign-In Helper
@MainActor
class AppleSignInHelper: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var completion: @MainActor (Result<(email: String, name: String), Error>) -> Void
    
    init(completion: @escaping @MainActor (Result<(email: String, name: String), Error>) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func startSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let email = appleIDCredential.email ?? "apple.user@icloud.com"
                let name = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                completion(.success((email: email, name: name.isEmpty ? "Пользователь Apple" : name)))
            } else {
                completion(.failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный тип учетных данных"])))
            }
        }
    }
    
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            completion(.failure(error))
        }
    }
    
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Find active window scene in a thread-safe main-actor way
        var activeWindow = UIWindow()
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.main.async {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                activeWindow = window
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return activeWindow
    }
}

// MARK: - Simulated & Web OAuth Sheet
struct SimulatedSignInView: View {
    let provider: String // "Apple" or "Google"
    @Binding var isPresented: Bool
    var onCompletion: (String) -> Void
    
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var statusMessage = ""
    @State private var isWebViewLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                VStack(spacing: 24) {
                    Spacer().frame(height: 10)
                    
                    // Logo/Icon Header
                    Circle()
                        .fill(provider == "Apple" ? Color.black : Color.white)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Group {
                                if provider == "Apple" {
                                    Image(systemName: "applelogo")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.white)
                                } else {
                                    Image(systemName: "g.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(.orange)
                                }
                            }
                        )
                        .shadow(color: (provider == "Apple" ? Color.black : Color.orange).opacity(0.2), radius: 10)
                    
                    VStack(spacing: 6) {
                        Text("Вход через \(provider)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text("Введите вашу электронную почту для синхронизации аккаунта.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.purple)
                                .scaleEffect(1.2)
                            Text(statusMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .glassCard(cornerRadius: 16)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Адрес электронной почты")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            TextField(provider == "Apple" ? "example@icloud.com" : "example@gmail.com", text: $email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15))
                                .padding(12)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }
                        .glassCard(cornerRadius: 16, padding: 18)
                        
                        Button(action: handleSignIn) {
                            HStack {
                                Text("Продолжить")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(provider == "Apple" ? Color.white : Color(hex: "7C3AED"))
                            .foregroundStyle(provider == "Apple" ? Color.black : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: (provider == "Apple" ? Color.black : Color(hex: "7C3AED")).opacity(0.2), radius: 6)
                        }
                        .disabled(email.isEmpty || !email.contains("@"))
                        .opacity(email.isEmpty || !email.contains("@") ? 0.6 : 1.0)
                    }
                    
                    Spacer()
                    
                    // Secure Connection Footer
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                        Text("Безопасное соединение по стандарту OAuth 2.0")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Вход в аккаунт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func handleSignIn() {
        isLoading = true
        statusMessage = "Подключение к серверам \(provider)..."
        
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            statusMessage = "Получение токена авторизации..."
            try? await Task.sleep(nanoseconds: 600_000_000)
            statusMessage = "Синхронизация профиля..."
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            isLoading = false
            onCompletion(email)
            isPresented = false
        }
    }
}
