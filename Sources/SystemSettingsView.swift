import SwiftUI

@MainActor
struct SystemSettingsView: View {
    // Left Column settings
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"
    @AppStorage("sys_theme") private var sysTheme: String = "Темная"
    @AppStorage("sys_fps") private var sysFps: String = "120 FPS (Ультра-плавность)"
    @AppStorage("sys_bg_scheduler") private var bgScheduler: Bool = false
    
    // Right Column settings
    @AppStorage("sys_auto_upscale") private var autoUpscale: Bool = false
    @AppStorage("sys_upscale_threshold") private var upscaleThreshold: String = "Меньше 4 МБ (Рекомендуется)"
    @AppStorage("sys_upscale_factor") private var upscaleFactor: String = "Увеличение 2x (Бикубическое)"
    
    @AppStorage("sys_parallel_streams") private var parallelStreams: Int = 3
    @AppStorage("sys_retry_on_fail") private var retryOnFail: Bool = true
    @AppStorage("sys_compress_jpeg") private var compressJpeg: Bool = false
    @AppStorage("sys_notifications") private var sysNotifications: Bool = true
    
    @State private var showingSavedToast = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        
                        // SECTION 1: Interface
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Интерфейс")
                            
                            pickerRow("Язык интерфейса", selection: $sysLanguage, options: ["Русский", "English"])
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            pickerRow("Тема оформления", selection: $sysTheme, options: ["Темная", "Светлая", "Системная"])
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            pickerRow("Предел частоты кадров", selection: $sysFps, options: [
                                "120 FPS (Ультра-плавность)",
                                "60 FPS (Стандартный)",
                                "30 FPS (Энергосбережение)"
                            ])
                        }
                        .glassCard()
                        
                        // SECTION 2: Scheduler
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("Планировщик")
                            
                            Toggle("Фоновый планировщик выгрузки", isOn: $bgScheduler)
                                .tint(Color(hex: "7C3AED"))
                            
                            Text("При активации планировщика система будет проверять новые фото и отправлять их в фоновом режиме.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .glassCard()
                        
                        // SECTION 3: Auto Upscaling
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Автоматический Апскейл")
                            
                            Toggle("Включить авто-апскейл", isOn: $autoUpscale)
                                .tint(Color(hex: "7C3AED"))
                            
                            if autoUpscale {
                                Divider().background(Color.white.opacity(0.1))
                                
                                pickerRow("Порог срабатывания", selection: $upscaleThreshold, options: [
                                    "Меньше 4 МБ (Рекомендуется)",
                                    "Меньше 2 МБ",
                                    "Меньше 8 МБ"
                                ])
                                
                                Divider().background(Color.white.opacity(0.1))
                                
                                pickerRow("Коэффициент (масштаб)", selection: $upscaleFactor, options: [
                                    "Увеличение 2x (Бикубическое)",
                                    "Увеличение 4x (Нейросеть)"
                                ])
                            }
                        }
                        .glassCard()
                        
                        // SECTION 4: Upload parameters
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Параметры выгрузки")
                            
                            HStack {
                                Text("Потоки параллельной загрузки")
                                    .font(.system(size: 14))
                                Spacer()
                                Picker("", selection: $parallelStreams) {
                                    Text("1 поток").tag(1)
                                    Text("3 потока").tag(3)
                                    Text("5 потоков").tag(5)
                                }
                                .pickerStyle(.menu)
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            Toggle("Автоповтор при сбоях", isOn: $retryOnFail)
                                .tint(Color(hex: "7C3AED"))
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            Toggle("Сжатие JPEG перед загрузкой", isOn: $compressJpeg)
                                .tint(Color(hex: "7C3AED"))
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            Toggle("Системные уведомления", isOn: $sysNotifications)
                                .tint(Color(hex: "7C3AED"))
                        }
                        .glassCard()
                        
                        // Save Button
                        Button(action: saveSettings) {
                            Text("Сохранить все настройки")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppleTheme.primaryGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: AppleTheme.glowStart.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Параметры системы")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                if showingSavedToast {
                    Text("Настройки успешно сохранены!")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
    
    // MARK: - Row Helpers
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.bottom, 2)
    }
    
    private func pickerRow(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private func saveSettings() {
        withAnimation {
            showingSavedToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showingSavedToast = false
            }
        }
    }
}
