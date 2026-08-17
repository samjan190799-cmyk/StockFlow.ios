import SwiftUI

// MARK: - Simulated & Web OAuth Sheet
struct SimulatedSignInView: View {
    let provider: String // "Apple" or "Google"
    @Binding var isPresented: Bool
    var onCompletion: (String) -> Void
    
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var statusMessage = ""
    
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
                        Text("Вход через ".localized + "\(provider)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text("Введите вашу электронную почту для синхронизации аккаунта.".localized)
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
                            Text("Адрес электронной почты".localized)
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
                                .autocorrectionDisabled(true)
                        }
                        .glassCard(cornerRadius: 16, padding: 18)
                        
                        Button(action: handleSignIn) {
                            HStack {
                                Text("Продолжить".localized)
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(provider == "Apple" ? Color.white : Color(hex: "007AFF"))
                            .foregroundStyle(provider == "Apple" ? Color.black : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .ambientShadow(radius: 6)
                        }
                        .disabled(email.isEmpty || !email.contains("@"))
                        .opacity(email.isEmpty || !email.contains("@") ? 0.6 : 1.0)
                    }
                    
                    Spacer()
                    
                    // Secure Connection Footer
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                        Text("Безопасное соединение по стандарту OAuth 2.0".localized)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Мой аккаунт".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена".localized) {
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
