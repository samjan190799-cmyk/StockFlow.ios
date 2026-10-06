import SwiftUI
import UIKit

// MARK: - Плитка снимка в сетке
struct GalleryTile: View {
    let photo: PhotoMetadata
    let isSelecting: Bool
    let isSelected: Bool
    let isFocused: Bool

    private let corner: CGFloat = 10

    private var isDone: Bool {
        photo.status == .success
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                LazyImageView(
                    photoId: photo.id,
                    maxPixelSize: 320,
                    contentMode: .fill,
                    isVideo: photo.isVideo,
                    photo: photo
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            )
            .overlay(stateOverlay)
            .overlay(alignment: .topLeading) { editorialBadge }
            .overlay(alignment: .bottomLeading) { statusBadge }
            .overlay(alignment: .bottomTrailing) { demoBadge }
            .overlay(alignment: .topTrailing) { attentionBadge }
            .overlay(selectionOverlay)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // Предупреждение: метаданные готового файла неполные, сток может его отклонить
    @ViewBuilder
    private var attentionBadge: some View {
        if !isSelecting && MetadataCheck.needsAttention(photo) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(5)
                .background(Circle().fill(Color.orange))
                .padding(5)
        }
    }

    private var accessibilitySummary: String {
        var summary = "\(photo.filename), \(photo.status.rawValue)"
        if MetadataCheck.needsAttention(photo) {
            let problems = MetadataCheck.issues(for: photo).map { $0.localized }.joined(separator: ", ")
            summary += ". " + "Неполные метаданные".localized + ": " + problems
        }
        return summary
    }

    // Пометка демо-файла: он не уходит в сеть
    @ViewBuilder
    private var demoBadge: some View {
        if photo.isDemo {
            Text("ДЕМО".localized)
                .scaledFont(size: 9, weight: .heavy)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange))
                .padding(5)
        }
    }

    // Затемнение и индикаторы процесса поверх превью
    @ViewBuilder
    private var stateOverlay: some View {
        switch photo.status {
        case .uploading:
            ZStack {
                Color.black.opacity(0.45)
                GalleryProgressRing(progress: photo.uploadProgress)
                    .frame(width: 46, height: 46)
            }
        case .aiAnalyzing:
            ZStack {
                Color.black.opacity(0.35)
                ProgressView()
                    .tint(.white)
            }
        case .error:
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(GalleryPalette.coral, lineWidth: 2)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var editorialBadge: some View {
        if photo.isEditorial {
            Text("ED")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(6)
        }
    }

    // Значок статуса в левом нижнем углу (справа LazyImageView рисует иконку видео)
    @ViewBuilder
    private var statusBadge: some View {
        if photo.status != .uploading {
            Image(systemName: photo.status.gallerySymbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isDone ? Color.black.opacity(0.85) : photo.status.galleryColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isDone ? GalleryPalette.green : Color.black.opacity(0.72)))
                .padding(6)
        }
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelecting {
            ZStack(alignment: .topTrailing) {
                if isSelected {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(GalleryPalette.accent.opacity(0.22))
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(GalleryPalette.accentLight, lineWidth: 3)
                }
                selectionMark
            }
        } else if isFocused {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(GalleryPalette.accentLight, lineWidth: 3)
        }
    }

    private var selectionMark: some View {
        ZStack {
            Circle().fill(isSelected ? GalleryPalette.accent : Color.black.opacity(0.35))
            Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .padding(6)
    }
}

// MARK: - Кольцо прогресса загрузки
struct GalleryProgressRing: View {
    let progress: Double

    private var clamped: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(GalleryPalette.violet, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(clamped * 100))%")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Лента этапов: распределение очереди одной полосой
struct GalleryPipelineBar: View {
    let counts: GalleryCounts

    private struct Segment: Identifiable {
        let id: GalleryStage
        let color: Color
        let count: Int
    }

    private var segments: [Segment] {
        GalleryStage.allCases.compactMap { stage in
            guard let color = stage.color else { return nil }
            let n = counts.count(stage)
            return n > 0 ? Segment(id: stage, color: color, count: n) : nil
        }
    }

    var body: some View {
        GeometryReader { geo in
            let segs = segments
            if segs.isEmpty {
                Capsule().fill(Color.primary.opacity(0.10))
            } else {
                let total = CGFloat(segs.reduce(0) { $0 + $1.count })
                let gaps = CGFloat(segs.count - 1) * 2
                let usable = max(geo.size.width - gaps, 0)
                HStack(spacing: 2) {
                    ForEach(segs) { seg in
                        Rectangle()
                            .fill(seg.color)
                            .frame(width: usable * CGFloat(seg.count) / total)
                    }
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - Чипы этапов (iPhone и iPad в портрете)
struct GalleryStageChips: View {
    @Binding var selection: GalleryStage
    let counts: GalleryCounts

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GalleryStage.allCases) { stage in
                    GalleryStageChip(
                        stage: stage,
                        count: counts.count(stage),
                        isActive: selection == stage
                    ) {
                        selection = stage
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct GalleryStageChip: View {
    let stage: GalleryStage
    let count: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let color = stage.color {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(stage.title)
                Text("\(count)")
                    .opacity(0.7)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isActive ? Color(.systemBackground) : Color.primary)
            .background(Capsule().fill(isActive ? Color.primary : Color.primary.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isActive ? 0 : 0.10), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.title), \(count)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Левая колонка на iPad (альбомная ориентация): этапы и лимиты дня
struct GallerySidebar: View {
    @Binding var selection: GalleryStage
    let counts: GalleryCounts
    let onUpgrade: () -> Void

    @ObservedObject private var rewardManager = RewardAdManager.shared
    @ObservedObject private var storeManager = StoreManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Этапы".localized.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(GalleryStage.allCases) { stage in
                stageRow(stage)
            }

            Spacer(minLength: 16)

            limitsCard
        }
        .padding(12)
    }

    private func stageRow(_ stage: GalleryStage) -> some View {
        let isActive = selection == stage
        return Button {
            selection = stage
        } label: {
            HStack(spacing: 10) {
                if let color = stage.color {
                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(stage.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(counts.count(stage))")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.title), \(counts.count(stage))")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Сегодня".localized.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if storeManager.isProUser {
                Label("PRO Безлимит".localized, systemImage: "crown.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.yellow)
            } else {
                limitRow(title: "ИИ".localized, symbol: "sparkles", tint: GalleryPalette.amber, remaining: rewardManager.remainingAIToday)
                limitRow(title: "Отправки".localized, symbol: "paperplane.fill", tint: GalleryPalette.blue, remaining: rewardManager.remainingUploadsToday)

                Button {
                    HapticHelper.trigger(.light)
                    onUpgrade()
                } label: {
                    Label("SmartStock PRO", systemImage: "crown.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func limitRow(title: String, symbol: String, tint: Color, remaining: Int) -> some View {
        let base = max(RewardAdManager.baseDailyLimit, 1)
        let fraction = min(1.0, Double(remaining) / Double(base))
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(remaining)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Плавающая панель действий
@MainActor
struct GalleryActionBar: View {
    let isSelecting: Bool
    let selectedCount: Int
    let aiCount: Int
    let sendCount: Int
    let isAutopilotRunning: Bool
    let isAnalyzing: Bool
    let onAutopilot: () -> Void
    let onAIAll: () -> Void
    let onSendAll: () -> Void
    let onAISelected: () -> Void
    let onSendSelected: () -> Void
    let onDeleteSelected: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isSelecting {
                barButton(
                    title: "ИИ для".localized,
                    symbol: "sparkles",
                    tint: .white,
                    count: selectedCount,
                    prominent: true,
                    disabled: selectedCount == 0,
                    action: onAISelected
                )
                barButton(
                    title: "Отправить".localized,
                    symbol: "paperplane.fill",
                    tint: GalleryPalette.blue,
                    count: selectedCount,
                    prominent: false,
                    disabled: selectedCount == 0,
                    action: onSendSelected
                )
                Menu {
                    Button(role: .destructive, action: onDeleteSelected) {
                        Label("Удалить".localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.10)))
                }
                .disabled(selectedCount == 0)
                .accessibilityLabel("Ещё".localized)
            } else {
                barButton(
                    title: "Автопилот".localized,
                    symbol: "bolt.fill",
                    tint: .white,
                    count: nil,
                    prominent: true,
                    disabled: isAutopilotRunning,
                    action: onAutopilot
                )
                barButton(
                    title: "ИИ".localized,
                    symbol: "sparkles",
                    tint: GalleryPalette.amber,
                    count: aiCount,
                    prominent: false,
                    disabled: isAnalyzing || isAutopilotRunning,
                    action: onAIAll
                )
                barButton(
                    title: "Отправить".localized,
                    symbol: "paperplane.fill",
                    tint: GalleryPalette.blue,
                    count: sendCount,
                    prominent: false,
                    disabled: isAutopilotRunning,
                    action: onSendAll
                )
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 6)
        .frame(maxWidth: 560)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private func barButton(
        title: String,
        symbol: String,
        tint: Color,
        count: Int?,
        prominent: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticHelper.trigger(.medium)
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(prominent ? Color.white : tint)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(prominent ? Color.white.opacity(0.22) : Color.primary.opacity(0.14)))
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                    if prominent {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(GalleryPalette.primaryGradient)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

// MARK: - Панель деталей (iPad, альбомная ориентация)
@MainActor
struct GalleryInspector: View {
    let photoId: UUID
    @ObservedObject var viewModel: QueueViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var showEditor = false

    private let titleLimit = 70
    private let descriptionLimit = 200

    private var photo: PhotoMetadata? {
        viewModel.photos.first(where: { $0.id == photoId })
    }

    private var enabledPlatforms: [StockPlatform] {
        guard let data = UserDefaults.standard.data(forKey: "stock_platforms"),
              let platforms = try? JSONDecoder().decode([StockPlatform].self, from: data) else {
            return []
        }
        return platforms.filter { $0.isEnabled }
    }

    var body: some View {
        if let photo {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(photo)
                    preview(photo)

                    Text("\(photo.filename) · \(photo.fileSize)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if photo.status == .error, let message = photo.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(GalleryPalette.badText(colorScheme))
                    }

                    textBlock(
                        title: "Заголовок".localized,
                        value: photo.title,
                        limit: titleLimit,
                        placeholder: "Запустите ИИ-анализ, чтобы получить заголовок.".localized
                    )
                    textBlock(
                        title: "Описание".localized,
                        value: photo.description,
                        limit: descriptionLimit,
                        placeholder: "Запустите ИИ-анализ, чтобы получить описание.".localized
                    )
                    keywordsBlock(photo)
                    stocksBlock(photo)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actions(photo)
            }
            .sheet(isPresented: $showEditor) {
                editor(photo)
            }
        }
    }

    // MARK: Заголовок панели

    private func header(_ photo: PhotoMetadata) -> some View {
        HStack {
            Text("Детали".localized)
                .font(.headline)
            Spacer()
            brandChip(photo)
        }
    }

    private func brandResult(_ photo: PhotoMetadata) -> TrademarkShieldResult? {
        guard !photo.isEditorial, !(photo.title.isEmpty && photo.keywords.isEmpty) else {
            return nil
        }
        return TrademarkShield.shared.inspect(title: photo.title, keywords: photo.keywords)
    }

    @ViewBuilder
    private func brandChip(_ photo: PhotoMetadata) -> some View {
        if photo.isEditorial {
            chip(text: "Editorial", symbol: "newspaper", tint: GalleryPalette.blue)
        } else if let result = brandResult(photo) {
            if result.hasViolations {
                chip(
                    text: "\("Бренды".localized): \(result.matches.count)",
                    symbol: "exclamationmark.shield.fill",
                    tint: GalleryPalette.amber
                )
            } else {
                chip(text: "Без брендов".localized, symbol: "checkmark.shield.fill", tint: GalleryPalette.green)
            }
        }
    }

    private func chip(text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.16)))
    }

    // MARK: Превью

    private func preview(_ photo: PhotoMetadata) -> some View {
        LazyImageView(photoId: photo.id, maxPixelSize: 900, contentMode: .fill, isVideo: photo.isVideo, photo: nil)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Image(systemName: photo.status.gallerySymbol)
                    Text(photo.status.rawValue)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(photo.status.galleryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .padding(10)
            }
    }

    // MARK: Текстовые поля со счётчиком символов

    private func textBlock(title: String, value: String, limit: Int, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                counter(value.count, limit: limit)
            }
            Text(value.isEmpty ? placeholder : value)
                .font(.subheadline)
                .foregroundStyle(value.isEmpty ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }

    private func counter(_ count: Int, limit: Int) -> some View {
        let color: Color
        if count == 0 {
            color = Color.secondary
        } else if count <= limit {
            color = GalleryPalette.okText(colorScheme)
        } else {
            color = GalleryPalette.badText(colorScheme)
        }
        return Text("\(count) / \(limit)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    // MARK: Ключевые слова

    private func keywordsBlock(_ photo: PhotoMetadata) -> some View {
        let inRange = (25...35).contains(photo.keywords.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ключевые слова".localized)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(photo.keywords.count) · \("рекомендуется 25–35".localized)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(inRange ? GalleryPalette.okText(colorScheme) : Color.secondary)
            }
            if photo.keywords.isEmpty {
                Text("Ключевые слова отсутствуют. Запустите ИИ-анализ.".localized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                QueueFlowLayout(spacing: 6) {
                    ForEach(photo.keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
            }
        }
    }

    // MARK: Куда отправлять

    private func protocolLabel(_ platform: StockPlatform) -> String {
        platform.host.lowercased().contains("sftp") ? "SFTP · нужен ПК-сервер".localized : "FTPS"
    }

    private func stocksBlock(_ photo: PhotoMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Отправить на".localized)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)

            let platforms = enabledPlatforms
            if platforms.isEmpty {
                Text("Подключите стоки во вкладке «Агентства».".localized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(platforms) { platform in
                    Toggle(isOn: Binding(
                        get: { photo.selectedStocks.contains(platform.name) },
                        set: { _ in viewModel.toggleStockForPhoto(photo.id, stockName: platform.name) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(platform.name)
                                .font(.subheadline.weight(.semibold))
                            Text(protocolLabel(platform))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(GalleryPalette.green)
                }
            }
        }
    }

    // MARK: Кнопки действий

    private func actions(_ photo: PhotoMetadata) -> some View {
        let isSent = photo.status == .success
        let isBusy = photo.status == .uploading || photo.status == .aiAnalyzing
        return HStack(spacing: 8) {
            Button {
                HapticHelper.trigger(.medium)
                viewModel.runAIForPhoto(photo.id)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .accessibilityLabel("ИИ-анализ".localized)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(GalleryPalette.amber)
                    .frame(width: 48, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .disabled(photo.status == .aiAnalyzing)
            .accessibilityLabel("ИИ заново".localized)

            Button {
                showEditor = true
            } label: {
                Text("Редактировать".localized)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.10)))
            }
            .buttonStyle(.plain)

            Button {
                HapticHelper.trigger(.medium)
                viewModel.uploadPhoto(photo.id)
            } label: {
                Label(isSent ? "Отправлено".localized : "Отправить".localized, systemImage: isSent ? "checkmark" : "paperplane.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GalleryPalette.primaryGradient))
            }
            .buttonStyle(.plain)
            .disabled(isSent || isBusy)
            .opacity((isSent || isBusy) ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: Редактор метаданных (как в PhotoDetailSheet)

    private func editor(_ photo: PhotoMetadata) -> some View {
        NavigationStack {
            AIMetadataView(
                photos: viewModel.photos,
                currentIndex: viewModel.photos.firstIndex(where: { $0.id == photo.id }) ?? 0
            ) { updatedPhotos in
                for updated in updatedPhotos {
                    if let idx = viewModel.photos.firstIndex(where: { $0.id == updated.id }) {
                        viewModel.photos[idx] = updated
                    }
                }
                showEditor = false
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Закрыть".localized) {
                        showEditor = false
                    }
                }
            }
        }
    }
}
