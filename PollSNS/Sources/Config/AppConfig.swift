// Sources/Config/AppConfig.swift
import Foundation

enum AppConfig {
    static var supabaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
    }
    static var supabaseAnonKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }
}
