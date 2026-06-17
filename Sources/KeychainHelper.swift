import Foundation
import Security

final class KeychainHelper: Sendable {
    static let shared = KeychainHelper()
    private init() {}
    
    func save(password: String, for service: String) {
        guard let data = password.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        // Delete any existing item first to prevent duplicate errors
        SecItemDelete(query as CFDictionary)
        
        // Build addition query
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            // Keychain write failed (likely sandbox/sideload entitlement restriction)
            // Save in UserDefaults fallback
            UserDefaults.standard.set(password, forKey: "fallback_keychain_" + service)
        } else {
            // Successfully saved in Keychain, delete fallback if present
            UserDefaults.standard.removeObject(forKey: "fallback_keychain_" + service)
        }
    }
    
    func read(for service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        // Fallback to UserDefaults if Keychain fails or has no value
        return UserDefaults.standard.string(forKey: "fallback_keychain_" + service)
    }
    
    func delete(for service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "fallback_keychain_" + service)
    }
}
