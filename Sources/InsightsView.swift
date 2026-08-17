import SwiftUI
import SafariServices

// MARK: - Модели данных для графика
struct EarningPoint: Identifiable, Sendable {
    let id = UUID()
    let date: String
    let value: Double
}

// MARK: - Metric Type
enum MetricType: String, CaseIterable, Identifiable, Sendable {
    case uploads  = "Загрузки"
    case success  = "Успешно"
    case failed   = "Ошибки"
    case sales    = "Покупки"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .uploads: return "arrow.up.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .failed:  return "xmark.circle.fill"
        case .sales:   return "bag.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .uploads: return Color(hex: "7C3AED")
        case .success: return Color(hex: "10B981")
        case .failed:  return Color(hex: "EF4444")
        case .sales:   return Color(hex: "F59E0B")
        }
    }
}

// MARK: - Shimmer модификатор
@MainActor
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear,                              location: 0),
                            .init(color: .white.opacity(0.18),                location: 0.4),
                            .init(color: .clear,                              location: 1),
                        ]),
                        startPoint: .init(x: phase, y: 0),
                        endPoint:   .init(x: phase + 0.6, y: 0)
                    )
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - InsightsView
struct InsightsView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var stats = StatsManager()
    @AppStorage("sys_language") private var sysLanguage: String = "Русский"

    @State private var selectedPeriod  = "30D"
    @State private var selectedMetric: MetricType = .uploads
    @State private var selectedStock   = "Все стоки"
    @State private var activeURL: URL? = nil
    @State private var showStockPicker = false
    @State private var showHistory     = false
    @State private var showClearConfirm = false

    // MARK: - Computed
    private var connectedPlatforms: [StockPlatform] {
        StatsManager.getConnectedPlatforms()
    }

    private var isDemoMode: Bool {
        connectedPlatforms.isEmpty && StatsManager.loadHistorySync().isEmpty
    }

    private var availableStocks: [String] {
        let platforms = connectedPlatforms
        if platforms.isEmpty {
            let history = StatsManager.loadHistorySync()
            let historyStocks = Array(Set(history.map { $0.platformName })).sorted()
            return ["Все стоки"] + (historyStocks.isEmpty ? ["Shutterstock", "Adobe Stock"] : historyStocks)
        }
        return ["Все стоки"] + platforms.map { $0.name }
    }

    // Иконка для выбранного стока
    private func stockIcon(_ name: String) -> (sfSymbol: String, color: Color) {
        switch name {
        case "Shutterstock":       return ("s.circle.fill",  Color(hex: "7C3AED"))
        case "Adobe Stock":        return ("a.circle.fill",  Color(hex: "EF4444"))
        case "iStock / Getty":     return ("g.circle.fill",  Color(hex: "10B981"))
        case "Alamy":              return ("a.circle",       Color(hex: "F59E0B"))
        case "Dreamstime":         return ("d.circle.fill",  Color(hex: "3B82F6"))
        case "Freepik":            return ("f.circle.fill",  Color(hex: "EC4899"))
        case "Depositphotos":      return ("d.circle",       Color(hex: "06B6D4"))
        case "123RF":              return ("1.circle.fill",  Color(hex: "F97316"))
        case "Pond5":              return ("p.circle.fill",  Color(hex: "8B5CF6"))
        default:                   return ("chart.bar.fill", Color(hex: "7C3AED"))
        }
    }

    // Значение метрики для выбранного стока
    private func metricValue(for metric: MetricType, stock: String) -> Int {
        switch metric {
        case .uploads: return stats.successUploads(for: stock) + stats.failedUploads(for: stock)
        case .success: return stats.successUploads(for: stock)
        case .failed:  return stats.failedUploads(for: stock)
        case .sales:   return stats.salesCount(for: stock)
        }
    }

    // Данные графика
    private var currentChartData: [EarningPoint] {
        return stats.chartData(for: selectedStock, period: selectedPeriod, metric: selectedMetric)
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()

                VStack(spacing: 0) {
                    // Выпадающий пикер стоков
                    stockPickerSection
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .zIndex(10)

                    ScrollView {
                        VStack(spacing: 14) {
                            // Вкладки метрик
                            metricsTabs
                                .padding(.horizontal)
                                .padding(.top, 8)

                            if stats.isLoading {
                                // Shimmer-скелетон
                                skeletonCards
                                    .padding(.horizontal)
                            } else {
                                // Карточки статистики
                                statsCard
                                    .padding(.horizontal)

                                // График
                                chartCard
                                    .padding(.horizontal)

                                // Список стоков
                                performanceSection
                                    .padding(.horizontal)

                                // История загрузок
                                historySection
                                    .padding(.horizontal)
                                    .padding(.bottom, 24)
                            }
                        }
                    }
                }

                // Информационная подсказка при отсутствии подключенных стоков
                if isDemoMode {
                    demoModeOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppleTheme.primaryGradient)

                        Text("Статистика".localized)
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.primary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        HapticHelper.selection()
                        stats.refresh()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(stats.isLoading ? 360 : 0))
                            .animation(
                                stats.isLoading
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: stats.isLoading
                            )
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { activeURL != nil },
                set: { if !$0 { activeURL = nil } }
            )) {
                if let url = activeURL {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                stats.refresh()
                // Сбрасываем выбор если выбранный сток больше не настроен
                if selectedStock != "Все стоки" && !connectedPlatforms.map({ $0.name }).contains(selectedStock) {
                    selectedStock = "Все стоки"
                }
            }
        }
    }

    // MARK: - Выпадающий пикер стоков
    private var stockPickerSection: some View {
        VStack(spacing: 0) {
            // Кнопка-заголовок пикера
            Button(action: {
                HapticHelper.selection()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    showStockPicker.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    let icon = stockIcon(selectedStock)
                    ZStack {
                        Circle()
                            .fill(icon.color.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: icon.sfSymbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(icon.color)
                    }

                    Text(selectedStock == "Все стоки" ? "Все стоки".localized : selectedStock)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    // Счётчик файлов
                    if selectedStock != "Все стоки" {
                        let count = stats.successUploads(for: selectedStock)
                        Text("\(count) " + "загрузок".localized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(stats.totalSuccessUploads) " + "всего".localized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showStockPicker ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Выпадающий список
            if showStockPicker {
                VStack(spacing: 4) {
                    ForEach(availableStocks, id: \.self) { stock in
                        Button(action: {
                            HapticHelper.selection()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedStock = stock
                                showStockPicker = false
                            }
                        }) {
                            let icon = stockIcon(stock)
                            let isSelected = stock == selectedStock
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(icon.color.opacity(isSelected ? 0.2 : 0.08))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: icon.sfSymbol)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(icon.color)
                                }

                                Text(stock == "Все стоки" ? "Все стоки".localized : stock)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .primary : .secondary)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color(hex: "7C3AED"))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                isSelected
                                    ? Color(hex: "7C3AED").opacity(0.08)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                    removal:   .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                ))
                .padding(.top, 6)
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
            }
        }
    }

    // MARK: - Shimmer-скелетон
    private var skeletonCards: some View {
        VStack(spacing: 14) {
            // Скелетон вкладок метрик
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 60)
                        .shimmer()
                }
            }

            // Скелетон карточки статистики
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 140, height: 16)
                    .shimmer()

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 90, height: 32)
                    .shimmer()

                Divider().background(Color.white.opacity(0.08))

                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 100, height: 12)
                            .shimmer()
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 60, height: 20)
                            .shimmer()
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 100, height: 12)
                            .shimmer()
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 60, height: 20)
                            .shimmer()
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))

            // Скелетон графика
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 100, height: 16)
                    .shimmer()
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 120)
                    .shimmer()
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    // MARK: - Вкладки метрик
    private var metricsTabs: some View {
        HStack(spacing: 10) {
            ForEach(MetricType.allCases) { metric in
                let isSelected = selectedMetric == metric
                let value = metricValue(for: metric, stock: selectedStock)

                Button(action: {
                    HapticHelper.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedMetric = metric
                    }
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: metric.icon)
                                .font(.system(size: 8, weight: .bold))
                            Text(metric.rawValue.localized.uppercased())
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)

                        if stats.isLoading && !isDemoMode {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 40, height: 18)
                                .shimmer()
                        } else {
                            Text(isDemoMode ? "—" : "\(value)")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        isSelected
                            ? LinearGradient(colors: [metric.color, metric.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Карточка статистики (реальные данные)
    private var statsCard: some View {
        let totalVal    = metricValue(for: selectedMetric, stock: selectedStock)
        let successVal  = stats.successUploads(for: selectedStock)
        let failedVal   = stats.failedUploads(for: selectedStock)
        let syncText    = stats.syncTime(for: selectedStock)
        let hasData     = totalVal > 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text((selectedMetric.rawValue.localized + (selectedStock == "Все стоки" ? "" : " — " + selectedStock)).uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    if isDemoMode {
                        Text("—")
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(.primary)
                    } else {
                        Text("\(totalVal)")
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }
                }

                Spacer()

                VStack(spacing: 6) {
                    Circle()
                        .fill(hasData ? Color(hex: "10B981") : Color(hex: "9CA3AF"))
                        .frame(width: 8, height: 8)
                        .neonShadow(color: hasData ? Color(hex: "10B981") : .clear, radius: 6)

                    Text(isDemoMode ? "Демо".localized : (hasData ? "Активно".localized : "Нет данных".localized))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(hasData && !isDemoMode ? Color(hex: "10B981") : .secondary)
                }
                .padding(10)
                .background((hasData && !isDemoMode ? Color(hex: "10B981") : Color.gray).opacity(0.1))
                .clipShape(Circle())
            }

            Divider().background(Color.white.opacity(0.10))

            HStack {
                // Успешных
                VStack(alignment: .leading, spacing: 4) {
                    Text("Успешно".localized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(isDemoMode ? "—" : "\(successVal)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "10B981"))
                        .contentTransition(.numericText())
                }

                Spacer()

                // Ошибок
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ошибок".localized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(isDemoMode ? "—" : "\(failedVal)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(failedVal > 0 ? Color(hex: "EF4444") : .secondary)
                        .contentTransition(.numericText())
                }

                Spacer()

                // Покупки
                VStack(alignment: .leading, spacing: 4) {
                    Text("Покупки".localized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(isDemoMode ? "—" : "\(stats.salesCount(for: selectedStock))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "F59E0B"))
                        .contentTransition(.numericText())
                }

                Spacer()

                // Последняя синхронизация
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Синхронизация".localized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(isDemoMode ? "—" : syncText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
        .glassCard(cornerRadius: 18, padding: 16)
    }

    // MARK: - График
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Динамика загрузок".localized)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)

                    if !isDemoMode {
                        Text(selectedStock == "Все стоки" ? "Все стоки".localized : selectedStock)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Переключатель периодов
                HStack(spacing: 4) {
                    ForEach(["7D", "30D", "90D"], id: \.self) { period in
                        Button(action: {
                            HapticHelper.selection()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                selectedPeriod = period
                            }
                        }) {
                            Text(period)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    if selectedPeriod == period {
                                        selectedMetric.color
                                    } else {
                                        Color.white.opacity(0.06)
                                    }
                                }
                                .foregroundStyle(selectedPeriod == period ? .white : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(2)
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            chartView
                .frame(height: 120)
                .padding(.top, 8)

            HStack {
                ForEach(currentChartData) { point in
                    Text(point.date)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
        .glassCard(cornerRadius: 18, padding: 14)
    }

    // MARK: - Построение графика
    private var chartView: some View {
        GeometryReader { geo in
            let width  = geo.size.width
            let height = geo.size.height
            let points = currentChartData.map { $0.value }
            let maxVal = max(points.max() ?? 1.0, 1.0)
            let minVal = points.min() ?? 0.0
            let diff   = maxVal - minVal == 0 ? 1.0 : maxVal - minVal

            let coordinates: [CGPoint] = points.enumerated().map { idx, val in
                let x = points.count > 1
                    ? width * CGFloat(idx) / CGFloat(points.count - 1)
                    : width / 2
                let y = height - (height * CGFloat((val - minVal) / diff) * 0.72 + height * 0.12)
                return CGPoint(x: x, y: y)
            }

            let fillColor  = selectedMetric.color
            let lineColor2 = selectedMetric == .failed ? Color(hex: "EF4444") : Color(hex: "EC4899")

            ZStack {
                // Заливка под линией
                Path { path in
                    guard !coordinates.isEmpty else { return }
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: coordinates[0])
                    for i in 1..<coordinates.count {
                        let p1 = coordinates[i - 1]
                        let p2 = coordinates[i]
                        let c1 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p1.y)
                        let c2 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p2.y)
                        path.addCurve(to: p2, control1: c1, control2: c2)
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [fillColor.opacity(0.28), fillColor.opacity(0.02), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                // Линия графика
                Path { path in
                    guard !coordinates.isEmpty else { return }
                    path.move(to: coordinates[0])
                    for i in 1..<coordinates.count {
                        let p1 = coordinates[i - 1]
                        let p2 = coordinates[i]
                        let c1 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p1.y)
                        let c2 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p2.y)
                        path.addCurve(to: p2, control1: c1, control2: c2)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [fillColor, lineColor2],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .neonShadow(color: fillColor, radius: 4)

                // Точки данных
                ForEach(Array(coordinates.enumerated()), id: \.offset) { _, pt in
                    Circle()
                        .fill(fillColor)
                        .frame(width: 6, height: 6)
                        .position(pt)
                        .neonShadow(color: fillColor, radius: 3)
                }
            }
        }
    }

    // MARK: - История загрузок
    private var historySection: some View {
        let records = stats.recentHistory(for: selectedStock, limit: 40)
        
        return VStack(alignment: .leading, spacing: 10) {
            // Заголовок + кнопка развернуть/свернуть
            HStack {
                Text("История загрузок".localized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if !records.isEmpty {
                    Text("\(records.count) " + "записей".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showHistory.toggle()
                    }
                }) {
                    Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            
            if showHistory {
                if records.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text("История пуста".localized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)
                    .glassCard(cornerRadius: 14, padding: 0)
                } else {
                    VStack(spacing: 0) {
                        ForEach(records) { record in
                            let icon = stockIcon(record.platformName)
                            let df: DateFormatter = {
                                let formatter = DateFormatter()
                                formatter.locale = Locale(identifier: "ru_RU")
                                formatter.dateFormat = "dd MMM HH:mm"
                                return formatter
                            }()
                            
                            HStack(spacing: 12) {
                                // Иконка стока
                                ZStack {
                                    Circle()
                                        .fill(icon.color.opacity(0.12))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: icon.sfSymbol)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(icon.color)
                                }
                                
                                // Имя файла и сток
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.filename)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(record.platformName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(icon.color)
                                }
                                
                                Spacer()
                                
                                // Дата и статус
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(df.string(from: record.date))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    
                                    // Бейдж успех/ошибка
                                    HStack(spacing: 3) {
                                        Image(systemName: record.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.system(size: 8))
                                        Text(record.isSuccess ? "Ок".localized : "Ошибка".localized)
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((record.isSuccess ? Color(hex: "10B981") : Color(hex: "EF4444")).opacity(0.12))
                                    .foregroundStyle(record.isSuccess ? Color(hex: "10B981") : Color(hex: "EF4444"))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            
                            if record.id != records.last?.id {
                                Divider()
                                    .background(Color.primary.opacity(0.06))
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    
                    // Кнопка очистки истории
                    Button(action: {
                        showClearConfirm = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Очистить историю".localized)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.red.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.15), lineWidth: 1))
                    }
                }
            }
        }
        .confirmationDialog("Очистить историю?".localized, isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Очистить".localized, role: .destructive) {
                stats.clearHistory()
                stats.refresh()
            }
            Button("Отмена".localized, role: .cancel) {}
        } message: {
            Text("Вся история загрузок будет удалена. Это действие нельзя отменить.".localized)
        }
    }
    
    // MARK: - Эффективность по стокам
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("По стокам".localized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(connectedPlatforms.count) " + "подключено".localized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(connectedPlatforms) { platform in
                    let icon        = stockIcon(platform.name)
                    let stokStats   = stats.statsByStock[platform.id]
                    let uploads     = stokStats?.successUploads ?? 0
                    let errors      = stokStats?.failedUploads  ?? 0
                    let syncText    = stokStats?.syncTimeText   ?? "Нет данных"
                    let loginUrl    = platformLoginUrl(platform.id)

                    Button(action: {
                        HapticHelper.trigger(.medium)
                        if let url = URL(string: loginUrl) {
                            activeURL = url
                        }
                    }) {
                        HStack(spacing: 12) {
                            // Иконка стока
                            ZStack {
                                Circle()
                                    .fill(icon.color.opacity(0.12))
                                    .frame(width: 38, height: 38)
                                Image(systemName: icon.sfSymbol)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(icon.color)
                            }
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(platform.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("Синхронизация: ".localized + syncText)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 5) {
                                HStack(spacing: 6) {
                                    // Успешных
                                    HStack(spacing: 3) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color(hex: "10B981"))
                                        Text("\(uploads)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Color(hex: "10B981"))
                                    }

                                    // Ошибок (только если есть)
                                    if errors > 0 {
                                        HStack(spacing: 3) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(Color(hex: "EF4444"))
                                            Text("\(errors)")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(Color(hex: "EF4444"))
                                        }
                                    }
                                }

                                Text(uploads > 0 ? "Активно".localized : "Нет загрузок".localized)
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((uploads > 0 ? Color(hex: "10B981") : Color.gray).opacity(0.12))
                                    .foregroundStyle(uploads > 0 ? Color(hex: "10B981") : .secondary)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(
                                            (uploads > 0 ? Color(hex: "10B981") : Color.gray).opacity(0.3),
                                            lineWidth: 1
                                        )
                                    )
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .glassCard(cornerRadius: 14, padding: 12)
                }
            }
        }
    }

    // URL личного кабинета стока
    private func platformLoginUrl(_ id: String) -> String {
        switch id {
        case "shutterstock":   return "https://submit.shutterstock.com"
        case "adobe":          return "https://contributor.adobestock.com"
        case "istock":         return "https://esp.gettyimages.com"
        case "alamy":          return "https://www.alamy.com/contributor"
        case "dreamstime":     return "https://www.dreamstime.com/sell-stock-photos"
        case "freepik":        return "https://contributor.freepik.com"
        case "depositphotos":  return "https://depositphotos.com/contributor"
        case "123rf":          return "https://www.123rf.com/contributor"
        case "pond5":          return "https://www.pond5.com/sell-stock"
        default:               return "https://google.com"
        }
    }

    // MARK: - Демо оверлей
    private var demoModeOverlay: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "7C3AED").opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppleTheme.primaryGradient)
            }
            .neonShadow(color: Color(hex: "7C3AED"), radius: 10)

            VStack(spacing: 6) {
                Text("Нет подключённых стоков".localized)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.primary)  // Адаптивный

                Text("Перейдите в раздел «Агентства» и настройте учётные данные для Shutterstock, Adobe Stock или других стоков — статистика загрузок появится здесь автоматически.".localized)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Text("Перейти в настройки агентств →".localized)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: "7C3AED"))
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)  // Адаптивный: тёмный/светлый
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1.2)  // Адаптивная обводка
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Встроенный браузер
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(red: 124/255, green: 58/255, blue: 237/255, alpha: 1.0)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

