import SwiftUI

// MARK: - Модели данных для статистики
struct EarningPoint: Identifiable, Sendable {
    let id = UUID()
    let date: String
    let value: Double
}

struct AgencyPerformance: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let iconName: String
    let iconColor: Color
    let syncTime: String
    let amount: Double
    let isPositive: Bool
    let statusText: String
    let statusColor: Color
}

struct InsightsView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedPeriod = "30D"
    @State private var animateChart = false
    
    // Демонстрационные данные для разных периодов
    private let data7D = [
        EarningPoint(date: "15 ИЮН", value: 120.0),
        EarningPoint(date: "16 ИЮН", value: 180.0),
        EarningPoint(date: "17 ИЮН", value: 140.0),
        EarningPoint(date: "18 ИЮН", value: 290.0),
        EarningPoint(date: "19 ИЮН", value: 210.0),
        EarningPoint(date: "20 ИЮН", value: 340.0),
        EarningPoint(date: "21 ИЮН", value: 310.0)
    ]
    
    private let data30D = [
        EarningPoint(date: "01 MAY", value: 250.0),
        EarningPoint(date: "08 MAY", value: 230.0),
        EarningPoint(date: "15 MAY", value: 380.0),
        EarningPoint(date: "22 MAY", value: 360.0),
        EarningPoint(date: "31 MAY", value: 320.0)
    ]
    
    private let data90D = [
        EarningPoint(date: "АПР", value: 950.0),
        EarningPoint(date: "МАЙ", value: 1420.0),
        EarningPoint(date: "ИЮН", value: 1890.0)
    ]
    
    // Текущие отображаемые точки в зависимости от выбранного периода
    var currentData: [EarningPoint] {
        switch selectedPeriod {
        case "7D": return data7D
        case "90D": return data90D
        default: return data30D
        }
    }
    
    // Эффективность по агентствам
    private let agencies = [
        AgencyPerformance(
            name: "Getty Images",
            iconName: "g.circle.fill",
            iconColor: Color(hex: "10B981"),
            syncTime: "2 ч. назад",
            amount: 120.0,
            isPositive: true,
            statusText: "Проверено",
            statusColor: Color(hex: "10B981")
        ),
        AgencyPerformance(
            name: "Adobe Stock",
            iconName: "a.circle.fill",
            iconColor: Color(hex: "EF4444"),
            syncTime: "5 ч. назад",
            amount: 85.40,
            isPositive: false,
            statusText: "В ожидании",
            statusColor: Color(hex: "60A5FA")
        ),
        AgencyPerformance(
            name: "Shutterstock",
            iconName: "s.circle.fill",
            iconColor: Color(hex: "7C3AED"),
            syncTime: "12 ч. назад",
            amount: 245.15,
            isPositive: true,
            statusText: "Проверено",
            statusColor: Color(hex: "10B981")
        ),
        AgencyPerformance(
            name: "National Geographic",
            iconName: "n.circle.fill",
            iconColor: Color(hex: "F59E0B"),
            syncTime: "1 д. назад",
            amount: 1420.0,
            isPositive: false,
            statusText: "На удержании",
            statusColor: Color(hex: "9CA3AF")
        )
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Карточка общего баланса
                        balanceCard
                            .padding(.horizontal)
                            .padding(.top, 12)
                        
                        // Карточка истории доходов (график)
                        earningsHistoryCard
                            .padding(.horizontal)
                        
                        // Раздел эффективности по агентствам
                        performanceSection
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 10) {
                        // Аватарка пользователя
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(AppleTheme.primaryGradient)
                            .neonShadow(color: Color(hex: "7C3AED"), radius: 4)
                        
                        Text("Статистика".localized)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {
                            HapticHelper.trigger(.medium)
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        
                        Button(action: {
                            HapticHelper.trigger(.medium)
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Карточка общего баланса
    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Общий баланс".localized.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    Text("$14,285.50")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                // Зеленая светящаяся точка
                Circle()
                    .fill(Color(hex: "10B981"))
                    .frame(width: 8, height: 8)
                    .neonShadow(color: Color(hex: "10B981"), radius: 6)
                    .padding(8)
                    .background(Color(hex: "10B981").opacity(0.12))
                    .clipShape(Circle())
            }
            
            Divider()
                .background(Color.white.opacity(0.10))
            
            HStack {
                // Колонка за последние 30 дней
                VStack(alignment: .leading, spacing: 4) {
                    Text("За последние 30 дней".localized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("+$2,410.20")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "EC4899"))
                }
                
                Spacer()
                
                // Колонка ожидания подтверждения
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ожидает подтверждения".localized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("$845.00")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
            }
        }
        .glassCard(cornerRadius: 20, padding: 18)
        .neonShadow(color: Color(hex: "7C3AED").opacity(0.3), radius: 10)
    }
    
    // MARK: - Карточка истории доходов
    private var earningsHistoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("История доходов".localized)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                
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
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background {
                                    if selectedPeriod == period {
                                        Color(hex: "7C3AED")
                                    } else {
                                        Color.white.opacity(0.06)
                                    }
                                }
                                .foregroundStyle(selectedPeriod == period ? .white : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(2)
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // График
            chartView
                .frame(height: 140)
                .padding(.top, 10)
            
            // Подписи дат
            HStack {
                ForEach(currentData) { point in
                    Text(point.date)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
        .glassCard(cornerRadius: 20, padding: 16)
    }
    
    // MARK: - Построение графика
    private var chartView: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let points = currentData.map { $0.value }
            let maxVal = points.max() ?? 1.0
            let minVal = points.min() ?? 0.0
            let diff = maxVal - minVal == 0 ? 1.0 : maxVal - minVal
            
            // Координаты для рисования
            let coordinates: [CGPoint] = points.enumerated().map { idx, val in
                let x = width * CGFloat(idx) / CGFloat(points.count - 1)
                let y = height - (height * CGFloat((val - minVal) / diff) * 0.7 + height * 0.15)
                return CGPoint(x: x, y: y)
            }
            
            ZStack {
                // Градиент под графиком
                Path { path in
                    guard !coordinates.isEmpty else { return }
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: coordinates[0])
                    
                    for i in 1..<coordinates.count {
                        let p1 = coordinates[i - 1]
                        let p2 = coordinates[i]
                        let control1 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p1.y)
                        let control2 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p2.y)
                        path.addCurve(to: p2, control1: control1, control2: control2)
                    }
                    
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.close()
                }
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "7C3AED").opacity(0.24), Color(hex: "EC4899").opacity(0.02), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Сама линия графика
                Path { path in
                    guard !coordinates.isEmpty else { return }
                    path.move(to: coordinates[0])
                    
                    for i in 1..<coordinates.count {
                        let p1 = coordinates[i - 1]
                        let p2 = coordinates[i]
                        let control1 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p1.y)
                        let control2 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p2.y)
                        path.addCurve(to: p2, control1: control1, control2: control2)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "7C3AED"), Color(hex: "EC4899")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .neonShadow(color: Color(hex: "EC4899"), radius: 4)
            }
        }
    }
    
    // MARK: - Эффективность агентств
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Эффективность агентств".localized)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button(action: {
                    HapticHelper.trigger(.medium)
                }) {
                    Text("Показать все".localized)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: "7C3AED"))
                }
            }
            
            VStack(spacing: 10) {
                ForEach(agencies) { agency in
                    HStack(spacing: 12) {
                        // Логотип агентства в стеклянном стиле
                        ZStack {
                            Circle()
                                .fill(agency.iconColor.opacity(0.12))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: agency.iconName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(agency.iconColor)
                        }
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .neonShadow(color: agency.iconColor, radius: 4)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(agency.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                            
                            Text("Синхронизация: ".localized + agency.syncTime.localized)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            // Сумма дохода
                            Text((agency.isPositive ? "+" : "") + String(format: "$%.2f", agency.amount))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(agency.isPositive ? Color(hex: "10B981") : .primary)
                            
                            // Статус-плашка
                            Text(agency.statusText.localized)
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(agency.statusColor.opacity(0.12))
                                .foregroundStyle(agency.statusColor)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(agency.statusColor.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .glassCard(cornerRadius: 14, padding: 12)
                }
            }
        }
    }
}
