import UIKit

/// Централизованный потокобезопасный менеджер фоновых задач iOS
@MainActor
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private var activeTasks: [String: UIBackgroundTaskIdentifier] = [:]
    
    private init() {}
    
    /// Начинает системную фоновую задачу с защитой от дублирования
    @discardableResult
    func beginTask(named name: String) -> UIBackgroundTaskIdentifier {
        endTask(named: name)
        
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.endTask(named: name)
            }
        }
        activeTasks[name] = taskId
        return taskId
    }
    
    /// Завершает системную фоновую задачу
    func endTask(named name: String) {
        if let taskId = activeTasks.removeValue(forKey: name), taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }
}
