import Foundation

enum AppConfig {
    static var supabaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
    }
    static var supabaseAnonKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }
    static var reportToken: String {
        Bundle.main.object(forInfoDictionaryKey: "REPORT_TOKEN") as? String ?? ""
    }
    private static let userIDKey = "com.pollsns.user_id"

    static var currentUserID: UUID {
        if let existing = KeychainHelper.load(key: userIDKey),
           let id = UUID(uuidString: existing) {
            return id
        }
        let newID = UUID()
        KeychainHelper.save(key: userIDKey, value: newID.uuidString)
        return newID
    }

    /// Supabase の user.id(UUID) を Keychain に保存する
    static func setCurrentUserID(_ id: UUID) {
        KeychainHelper.save(key: userIDKey, value: id.uuidString)
    }

    /// 保存済みの user.id を削除（サインアウト時に使用）
    static func resetCurrentUserID() {
        KeychainHelper.delete(key: userIDKey)
    }
}

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
