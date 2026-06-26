import Foundation
import Network

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")
    
    @Published var isConnected = true
    @Published var connectionType: ConnectionType = .wifi
    
    enum ConnectionType: String {
        case wifi = "Wi-Fi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case unknown = "Unknown"
    }
    
    private init() {
        // Откладываем запуск на следующий цикл главного потока,
        // чтобы гарантировать полную готовность объекта NetworkMonitor в памяти
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.monitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor in
                    self?.isConnected = path.status == .satisfied
                    if path.usesInterfaceType(.wifi) {
                        self?.connectionType = .wifi
                    } else if path.usesInterfaceType(.cellular) {
                        self?.connectionType = .cellular
                    } else if path.usesInterfaceType(.wiredEthernet) {
                        self?.connectionType = .ethernet
                    } else {
                        self?.connectionType = .unknown
                    }
                }
            }
            self.monitor.start(queue: self.queue)
        }
    }
}
