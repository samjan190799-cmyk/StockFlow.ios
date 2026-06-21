import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @ObservedObject var authManager: AuthManager
    
    @State private var isRegisterMode = false
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showPassword = false
    
    // Анимационные переменные
    @State private var animateGlow = false
    
    var body: some View {
        ZStack {
            // Задний фон в стиле жидкого темного космоса с неоновым свечением
            Color(hex: "06070C")
                .ignoresSafeArea()
            
            // Круги размытия (Ambient Light)
            ZStack {
                Circle()
                    .fill(Color(hex: "7C3AED").opacity(animateGlow ? 0.25 : 0.15))
                    .frame(width: 320, height: 320)
                    .blur(radius: 60)
                    .offset(x: -80, y: -120)
                
                Circle()
                    .fill(Color(hex: "EC4899").opacity(animateGlow ? 0.22 : 0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 50)
                    .offset(x: 100, y: 150)
            }
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: animateGlow)
            .onAppear {
                animateGlow = true
            }
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    
                    // Блок логотипа
                    VStack(spacing: 12) {
                        SmartStockLogoView(size: 80)
                            .neonShadow(color: Color(hex: "7C3AED"), radius: 12)
                            .padding(.top, 40)
                        
                        Text("SmartStock")
                            .font(.system(size: 30, weight: .black))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.white, Color(hex: "A78BFA")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .tracking(1.5)
                        
                        Text("Ваш умный микростоковый менеджер".localized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    // Форма авторизации (Карточка Glassmorphism)
                    VStack(spacing: 20) {
                        Text(isRegisterMode ? "Регистрация".localized : "Вход в систему".localized)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 6)
                        
                        // Поле Email
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email".localized)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundStyle(Color(hex: "7C3AED"))
                                    .font(.system(size: 14))
                                
                                TextField("example@domain.com", text: $email)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        
                        // Поле Пароль
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Пароль".localized)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(Color(hex: "7C3AED"))
                                    .font(.system(size: 14))
                                
                                if showPassword {
                                    TextField("••••••", text: $password)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                } else {
                                    SecureField("••••••", text: $password)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                                
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 14))
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        
                        // Сообщение об ошибке
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                        
                        // Основная кнопка действия (Вход / Регистрация)
                        Button(action: {
                            performAuthAction()
                        }) {
                            ZStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(isRegisterMode ? "Зарегистрироваться".localized : "Войти".localized)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "7C3AED"), Color(hex: "EC4899")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .neonShadow(color: Color(hex: "7C3AED"), radius: isLoading ? 0 : 5)
                        }
                        .disabled(isLoading)
                        .padding(.top, 8)
                    }
                    .padding(24)
                    .glassCard(cornerRadius: 24, padding: 0)
                    .padding(.horizontal, 20)
                    
                    // Разделитель «ИЛИ»
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1)
                        Text("или".localized)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 32)
                    
                    // Кнопка Вход через Apple ID
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignInResult(result)
                    }
                    .signInWithAppleButtonStyle(.whiteOutline)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    
                    // Кнопка Вход через Google
                    Button(action: {
                        performGoogleSignIn()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                            Text("Войти с Google".localized)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Кнопка переключения режима
                    Button(action: {
                        withAnimation {
                            isRegisterMode.toggle()
                            errorMessage = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(isRegisterMode ? "Уже есть аккаунт?".localized : "У вас нет аккаунта?".localized)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Text(isRegisterMode ? "Войти".localized : "Зарегистрироваться".localized)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: "A78BFA"))
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // Запуск авторизации
    private func performAuthAction() {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Введите ваш Email".localized
            return
        }
        guard !password.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Введите ваш пароль".localized
            return
        }
        
        HapticHelper.trigger(.medium)
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                if isRegisterMode {
                    _ = try await authManager.register(email: email, password: password)
                } else {
                    _ = try await authManager.login(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    // Обработка Apple Sign-In
    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let email = appleIDCredential.email ?? "apple.user@icloud.com"
                HapticHelper.trigger(.success)
                isLoading = true
                
                Task {
                    do {
                        _ = try await authManager.loginWithApple(email: email)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isLoading = false
                }
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // Обработка Google Sign-In
    private func performGoogleSignIn() {
        HapticHelper.trigger(.medium)
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await authManager.loginWithGoogle()
                HapticHelper.trigger(.success)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
