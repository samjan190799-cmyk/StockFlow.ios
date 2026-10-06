import SwiftUI
import UIKit

#if DEBUG
/// Сценарии для съёмки скриншотов App Store в симуляторе (только отладочная сборка, в релиз не попадает).
/// Сценарий выбирается аргументом запуска `-ss_scene <имя>`; когда экран готов, в папке Documents
/// появляется файл `ss_done`, по которому скрипт `.github/scripts/take_screenshots.sh` понимает, что можно снимать.
@MainActor
enum ScreenshotScenario {
    static var name: String? {
        UserDefaults.standard.string(forKey: "ss_scene")
    }

    static var isActive: Bool { name != nil }

    /// Запускает сценарий. `openDetail` открывает карточку файла поверх очереди (iPhone),
    /// `focus` выбирает файл в правой панели (iPad).
    static func run(
        viewModel: QueueViewModel,
        focus: @escaping (PhotoMetadata) -> Void,
        openDetail: @escaping (PhotoMetadata) -> Void
    ) async {
        guard let scene = name else { return }
        let marker = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ss_done")
        try? FileManager.default.removeItem(at: marker)

        // PRO: без рекламы и без ограничений, чтобы на скриншотах не было баннеров
        // (аргумент -ss_ads 1 оставляет рекламу: так проверяют, как выглядит баннер)
        let showAds = UserDefaults.standard.bool(forKey: "ss_ads")
        StoreManager.shared.setTesterProOverride(active: true, isPro: !showAds)

        switch scene {
        case "prompt":
            AppRouter.shared.selectedTab = .prompt
        case "agencies":
            AppRouter.shared.selectedTab = .agencies
        case "settings":
            AppRouter.shared.selectedTab = .settings
        default:
            AppRouter.shared.selectedTab = .queue
            viewModel.removeDemoFiles()
            viewModel.addDemoFiles()
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            if scene != "queue-new" {
                viewModel.runAIForAll()
                await wait(until: { viewModel.photos.allSatisfy { $0.status == .ready } }, timeout: 40)
            }
            if scene == "queue-uploaded" {
                viewModel.uploadAllReady()
                await wait(until: { viewModel.photos.allSatisfy { $0.status == .success } }, timeout: 60)
            }
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            if scene != "queue-new", isPad {
                let index = scene == "detail" ? 1 : 0
                if viewModel.photos.indices.contains(index) { focus(viewModel.photos[index]) }
            } else if scene == "detail", let first = viewModel.photos.first {
                openDetail(first)
            }
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        FileManager.default.createFile(atPath: marker.path, contents: Data("1".utf8))
    }

    private static func wait(until condition: () -> Bool, timeout: Double) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
}
#endif
