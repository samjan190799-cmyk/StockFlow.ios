import SwiftUI

// MARK: - Дубли и похожие кадры
// Поиск идёт по миниатюрам, оригиналы не читаются. Лишние файлы убираются из очереди вместе с копиями в приложении.
@MainActor
struct DuplicatesView: View {
    @ObservedObject var viewModel: QueueViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dup_sensitivity") private var sensitivityRaw: Int = DuplicateSensitivity.normal.rawValue

    @State private var groups: [DuplicateGroup] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var confirmRemoveAll = false

    private var sensitivity: DuplicateSensitivity {
        DuplicateSensitivity(rawValue: sensitivityRaw) ?? .normal
    }

    private var removableCount: Int {
        groups.reduce(0) { $0 + $1.removableIDs.count }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView()
                ScrollView {
                    VStack(spacing: 14) {
                        Picker("Чувствительность".localized, selection: $sensitivityRaw) {
                            ForEach(DuplicateSensitivity.allCases) { level in
                                Text(level.title.localized).tag(level.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("«Строго» — почти одинаковые кадры. «Серии» — похожие сюжеты одной съёмки.".localized)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        content
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Дубли".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово".localized) {
                        dismiss()
                    }
                }
            }
            .task {
                await scan()
            }
            .onChange(of: sensitivityRaw) { _ in
                Task { await scan() }
            }
            .confirmationDialog(
                "Убрать все лишние файлы из очереди?".localized,
                isPresented: $confirmRemoveAll,
                titleVisibility: .visible
            ) {
                Button("\("Убрать".localized) \(removableCount)", role: .destructive) {
                    removeAll()
                }
                Button("Отмена".localized, role: .cancel) {}
            } message: {
                Text("В каждой группе останется отмеченный зелёным кадр.".localized)
            }
        }
    }

    // MARK: Содержимое

    @ViewBuilder
    private var content: some View {
        if isScanning {
            VStack(spacing: 10) {
                ProgressView()
                Text("Поиск дублей…".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if hasScanned && groups.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(GalleryPalette.green)
                Text("Дублей не найдено".localized)
                    .font(.headline)
                Text("Все файлы в очереди уникальны.".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if !groups.isEmpty {
            VStack(spacing: 12) {
                Text("\("Групп".localized): \(groups.count) · \("можно убрать".localized): \(removableCount)")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    confirmRemoveAll = true
                } label: {
                    Text("\("Убрать все лишние".localized) (\(removableCount))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appPrimary)

                ForEach(groups) { group in
                    groupCard(group)
                }
            }
        }
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        let lookup = Dictionary(viewModel.photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.kind == .exact ? "Точная копия".localized : "Похожие кадры".localized)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(group.photoIDs.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.photoIDs, id: \.self) { id in
                        if let photo = lookup[id] {
                            thumbnail(photo, isKeep: id == group.keepID, groupID: group.id)
                        }
                    }
                }
            }

            Text("Нажмите на кадр, чтобы оставить именно его.".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                remove(group)
            } label: {
                SwiftUI.Label("Убрать лишние".localized, systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appSecondary)
        }
        .appCard(cornerRadius: 16, padding: 14)
    }

    private func thumbnail(_ photo: PhotoMetadata, isKeep: Bool, groupID: UUID) -> some View {
        LazyImageView(
            photoId: photo.id,
            maxPixelSize: 240,
            contentMode: .fill,
            isVideo: photo.isVideo,
            photo: photo
        )
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isKeep ? GalleryPalette.green : Color.clear, lineWidth: 3)
        )
        .overlay(alignment: .bottom) {
            Text(isKeep ? "Оставить".localized : "Лишний".localized)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(isKeep ? GalleryPalette.green : GalleryPalette.coral))
                .padding(4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            makeKeep(photo.id, in: groupID)
        }
    }

    // MARK: Действия

    private func scan() async {
        isScanning = true
        let items = viewModel.duplicateItems(from: viewModel.photos)
        let found = await DuplicateDetector.shared.findGroups(items: items, threshold: sensitivity.threshold)
        groups = found
        isScanning = false
        hasScanned = true
    }

    private func makeKeep(_ id: UUID, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        var ids = groups[index].photoIDs
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        groups[index].photoIDs = ids
        HapticHelper.selection()
    }

    private func remove(_ group: DuplicateGroup) {
        viewModel.removePhotosAndFiles(Set(group.removableIDs))
        groups.removeAll { $0.id == group.id }
        HapticHelper.success()
    }

    private func removeAll() {
        var ids = Set<UUID>()
        for group in groups {
            ids.formUnion(group.removableIDs)
        }
        viewModel.removePhotosAndFiles(ids)
        groups = []
        HapticHelper.success()
    }
}
