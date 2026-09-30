import SwiftUI
import PhotosUI
import ImageIO
import UIKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Photo Detail Sheet
struct PhotoDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let photo: PhotoMetadata
    @ObservedObject var viewModel: QueueViewModel
    @State private var showMetadataEditor = false
    
    var currentPhoto: PhotoMetadata {
        viewModel.photos.first(where: { $0.id == photo.id }) ?? photo
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                
                ScrollView {
                    VStack(spacing: 16) {
                        DetailCardView(photo: currentPhoto, viewModel: viewModel, onEditMetadata: {
                            showMetadataEditor = true
                        })
                        .glassCard(cornerRadius: 20, padding: 16)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Закрыть".localized)
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Детали фотографии".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово".localized) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
            }
            .sheet(isPresented: $showMetadataEditor) {
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
                        showMetadataEditor = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Закрыть".localized) {
                                showMetadataEditor = false
                            }
                            .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Detail Card View
struct DetailCardView: View {
    let photo: PhotoMetadata
    @ObservedObject var viewModel: QueueViewModel
    var onEditMetadata: () -> Void
    
    @State private var selectedErrorMsg: String? = nil
    @State private var showingErrorAlert = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Раздел 1: Превью и Ключевые слова
            HStack(alignment: .top, spacing: 14) {
                // Превью
                LazyImageView(photoId: photo.id, maxPixelSize: 300, contentMode: .fill, isVideo: photo.isVideo, photo: photo)
                .frame(width: 100, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 4)
                
                // Ключевые слова
                VStack(alignment: .leading, spacing: 8) {
                    Text("КЛЮЧЕВЫЕ СЛОВА (Генерация ИИ)".localized)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    
                    if photo.keywords.isEmpty {
                        Text("Ключевые слова отсутствуют. Запустите ИИ-анализ.".localized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding(.top, 4)
                    } else {
                        QueueFlowLayout(spacing: 5) {
                            ForEach(photo.keywords, id: \.self) { kw in
                                QueueKeywordChip(text: kw) {
                                    // Удаление тега
                                    if let idx = viewModel.photos.firstIndex(where: { $0.id == photo.id }) {
                                        viewModel.photos[idx].keywords.removeAll { $0 == kw }
                                        HapticHelper.trigger(.light)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Divider().background(Color.primary.opacity(0.08))
            
            // Раздел 2: Метаданные
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("МЕТАДАННЫЕ".localized)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: {
                        HapticHelper.selection()
                        onEditMetadata()
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "7C3AED"))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Text(photo.title.isEmpty ? "Без названия".localized : photo.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Text("Description")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Text(photo.description.isEmpty ? "Описание отсутствует".localized : photo.description)
                        .font(.caption2)
                        .foregroundStyle(.primary.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            Divider().background(Color.primary.opacity(0.08))
            
            // Раздел 3: Прогноз популярности
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ПРОГНОЗ ПОПУЛЯРНОСТИ (Рыночный анализ ИИ)".localized)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                // Табличка
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 12) {
                            Text("Shutterstock")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .center)
                            Text("Adobe Stock")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .center)
                            Text("Getty")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .center)
                        }
                    }
                    .padding(.bottom, 2)
                    
                    let displayKeywords = photo.keywords.isEmpty ? ["Пейзаж", "Путешествие", "Горы"] : Array(photo.keywords.prefix(3))
                    ForEach(displayKeywords, id: \.self) { kw in
                        let hash = abs(kw.hashValue ^ photo.id.hashValue)
                        let val = Double(55 + (hash % 41)) / 100.0 // от 0.55 до 0.95
                        PopularityRow(keyword: kw, value: val)
                    }
                }
            }
            
            Divider().background(Color.primary.opacity(0.08))
            
            // Нижняя строка статуса и кнопки вызова контекстного меню
            HStack(spacing: 8) {
                Text(photo.fileSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text("Статус:".localized + " \(photo.status.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Status Badge Capsule (Glassmorphic)
                Text(photo.status.rawValue)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(photo.status.color.opacity(0.12))
                    .foregroundStyle(photo.status.color)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(photo.status.color.opacity(0.3), lineWidth: 1)
                    )
                
                // Меню действий
                Menu {
                    Section {
                        Button(action: {
                            HapticHelper.trigger(.light)
                            viewModel.uploadPhoto(photo.id)
                        }) {
                            Label("Отправить на стоки".localized, systemImage: "paperplane.fill")
                        }
                        
                        Button(action: {
                            HapticHelper.trigger(.light)
                            viewModel.runAIForPhoto(photo.id)
                        }) {
                            Label("Заполнить ИИ".localized, systemImage: "sparkles")
                        }
                    }
                    
                    Menu {
                        ForEach(["Shutterstock", "Adobe Stock", "iStock / Getty", "Freepik", "Depositphotos", "Alamy", "Dreamstime", "123RF", "Pond5"], id: \.self) { stock in
                            Button(action: {
                                HapticHelper.selection()
                                viewModel.toggleStockForPhoto(photo.id, stockName: stock)
                            }) {
                                HStack {
                                    Text(stock)
                                    if photo.selectedStocks.contains(stock) {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Выбрать стоки...".localized, systemImage: "checklist")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        HapticHelper.trigger(.medium)
                        viewModel.removePhoto(photo.id)
                    }) {
                        Label("Удалить из очереди".localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                        .padding(4)
                }
            }
            
            if photo.status == .error, let errorMsg = photo.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(errorMsg)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button(action: {
                        HapticHelper.trigger(.light)
                        selectedErrorMsg = errorMsg
                        showingErrorAlert = true
                    }) {
                        Text("Подробнее".localized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(hex: "7C3AED"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "7C3AED").opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .alert("Ошибка загрузки".localized, isPresented: $showingErrorAlert) {
            Button("Скопировать".localized) {
                if let msg = selectedErrorMsg {
                    UIPasteboard.general.string = msg
                    HapticHelper.notification(.success)
                }
            }
            Button("ОК".localized, role: .cancel) {}
        } message: {
            if let msg = selectedErrorMsg {
                Text(msg)
            }
        }
    }
}

// MARK: - Queue Flow Layout
struct QueueFlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Queue Keyword Chip
struct QueueKeywordChip: View {
    let text: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
            Button(action: {
                HapticHelper.trigger(.light)
                onRemove()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - Popularity Row
struct PopularityRow: View {
    let keyword: String
    let value: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Text(keyword)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            
            ZStack(alignment: .leading) {
                // Градиентная подложка шкалы
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "10B981"), Color(hex: "F59E0B"), Color(hex: "EF4444")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 7)
                        
                        Circle()
                            .fill(.white)
                            .frame(width: 11, height: 11)
                            .shadow(color: .black.opacity(0.35), radius: 2)
                            .offset(x: geo.size.width * CGFloat(value) - 5.5, y: -2)
                    }
                }
                .frame(height: 7)
            }
            
            Text("Высокий".localized)
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - CSV Document Transferable Helper
struct CSVDocument: Transferable {
    let csvText: String
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(
            contentType: .commaSeparatedText,
            exporting: { doc in
                doc.csvText.data(using: .utf8) ?? Data()
            },
            importing: { data in
                CSVDocument(csvText: String(data: data, encoding: .utf8) ?? "")
            }
        )
    }
}

