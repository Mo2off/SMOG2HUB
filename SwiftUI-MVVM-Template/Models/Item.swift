import Foundation
import Security

/// The execution state of a background service.
enum ServiceStatus: String, Codable {
    case running
    case stopped
    case transitioning
    case error
    
    var displayName: String {
        switch self {
        case .running: return "ACTIF"
        case .stopped: return "ARRÊTÉ"
        case .transitioning: return "EN COURS"
        case .error: return "ERREUR"
        }
    }
}

/// Dynamic metrics data point gathered at a specific time.
struct ServiceMetrics: Identifiable, Codable {
    var id: String { timestamp.description }
    let timestamp: Date
    let cpuPercent: Double
    let ramMB: Double
}

/// Data model representing a target process configuration.
struct ServiceItem: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let port: Int
    var status: ServiceStatus
    var cpuUsage: Double
    var ramUsageMB: Double
    var uptimeSeconds: Int
    var metricsHistory: [ServiceMetrics]
}

/// Physical layer encryption bindings to secure credentials via iOS Keychain.
class KeychainHelper {
    static let shared = KeychainHelper()
    
    private init() {}
    
    func save(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
