import SwiftUI

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
            Form {
                Section(header: Text("Интерфейс")) {
                    Picker("Язык интерфейса", selection: $sysLanguage) {
                        Text("Русский").tag("Русский")
                        Text("English").tag("English")
                    }
                    
                    Picker("Тема оформления", selection: $sysTheme) {
                        Text("Темная").tag("Темная")
                        Text("Светлая").tag("Светлая")
                        Text("Системная").tag("Системная")
                    }
                    
                    Picker("Предел частоты кадров", selection: $sysFps) {
                        Text("120 FPS (Ультра-плавность)").tag("120 FPS (Ультра-плавность)")
                        Text("60 FPS (Стандартный)").tag("60 FPS (Стандартный)")
                        Text("30 FPS (Энергосбережение)").tag("30 FPS (Энергосбережение)")
                    }
                }
                
                Section(header: Text("Планировщик"), footer: Text("При активации планировщика система будет проверять новые фото и отправлять их в фоновом режиме.")) {
                    Toggle("Фоновый планировщик выгрузки", isOn: $bgScheduler)
                }
                
                Section(header: Text("Автоматический Апскейл мелких фото")) {
                    Toggle("Включить авто-апскейл", isOn: $autoUpscale)
                    
                    if autoUpscale {
                        Picker("Порог срабатывания", selection: $upscaleThreshold) {
                            Text("Меньше 4 МБ (Рекомендуется)").tag("Меньше 4 МБ (Рекомендуется)")
                            Text("Меньше 2 МБ").tag("Меньше 2 МБ")
                            Text("Меньше 8 МБ").tag("Меньше 8 МБ")
                        }
                        
                        Picker("Коэффициент (масштаб)", selection: $upscaleFactor) {
                            Text("Увеличение 2x (Бикубическое)").tag("Увеличение 2x (Бикубическое)")
                            Text("Увеличение 4x (Нейросеть)").tag("Увеличение 4x (Нейросеть)")
                        }
                    }
                }
                
                Section(header: Text("Параметры выгрузки")) {
                    Picker("Параллельные загрузки (потоки)", selection: $parallelStreams) {
                        Text("1 поток").tag(1)
                        Text("3 потока (По умолчанию)").tag(3)
                        Text("5 потоков").tag(5)
                    }
                    
                    Toggle("Автоповтор при сбоях", isOn: $retryOnFail)
                    Toggle("Сжатие JPEG перед загрузкой", isOn: $compressJpeg)
                    Toggle("Системные уведомления", isOn: $sysNotifications)
                }
                
                Section {
                    Button(action: saveSettings) {
                        Text("Сохранить все настройки")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.white)
                            .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.blue)
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
                        .background(Color.black.opacity(0.85))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(radius: 5)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
    
    private func saveSettings() {
        withAnimation {
            showingSavedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showingSavedToast = false
            }
        }
    }
}
