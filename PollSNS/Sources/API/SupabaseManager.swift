import Supabase
import Foundation

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: AppConfig.supabaseURL)!,
            supabaseKey: AppConfig.supabaseAnonKey
        )
    }

    // 匿名ログイン
    func signInAnonymously() async throws -> User {
        let result = try await client.auth.signInAnonymously()
        return result.user
    }

    func currentUser() -> User? {
        client.auth.currentUser
    }
}

extension SupabaseManager {
    /// 未ログインなら匿名サインインし、取得した UID を Keychain に保存する
    /// すでにログイン済みなら、その UID を保存して返す
    @discardableResult
    func ensureSignedInAndCacheUserID() async -> UUID? {
        do {
            if let user = client.auth.currentUser {
                // 既存セッションを再利用
                AppConfig.setCurrentUserID(user.id)
                return user.id
            } else {
                // 匿名サインインを実行
                let user = try await signInAnonymously()
                AppConfig.setCurrentUserID(user.id)
                return user.id
            }
        } catch {
            print("❌ Anonymous sign-in failed:", error)
            return nil
        }
    }
}
