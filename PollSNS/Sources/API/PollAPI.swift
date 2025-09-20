// Sources/API/PollAPI.swift
import Foundation

enum PollAPI {
    static func fetchPolls(limit: Int = 20) async throws -> [Poll] {
        print("URL:", AppConfig.supabaseURL)
        print("KEY present:", !AppConfig.supabaseAnonKey.isEmpty)
        // 1) ベースURL
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        // 2) /rest/v1/polls?select=...&order=created_at.desc&limit=20
        comps.path = "/rest/v1/polls"
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,question,category,created_at"),
            URLQueryItem(name: "order",  value: "created_at.desc"),
            URLQueryItem(name: "limit",  value: String(limit))
        ]
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Supabase必須ヘッダ
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            print("HTTP status:", http.statusCode)
        }
        print("RAW response:", String(data: data, encoding: .utf8) ?? "n/a")
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([Poll].self, from: data)
    }
    static func fetchOptions(for pollID: UUID) async throws -> [PollOption] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/poll_options"
        comps.queryItems = [
            URLQueryItem(name: "poll_id", value: "eq.\(pollID.uuidString)"),
            URLQueryItem(name: "select", value: "*")
        ]
        let url = comps.url!
        print("OPTIONS URL:", url.absoluteString)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("OPTIONS HTTP status:", code)
        print("OPTIONS RAW response:", String(data: data, encoding: .utf8) ?? "<binary>")
        guard (200...299).contains(code) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([PollOption].self, from: data)
    }

    static func submitVote(pollID: UUID, optionID: UUID, userID: UUID) async throws {
        guard let base = URL(string: AppConfig.supabaseURL) else { throw URLError(.badURL) }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/votes"
        comps.queryItems = [
            URLQueryItem(name: "on_conflict", value: "poll_id,user_id")
        ]
        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("resolution=ignore-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        // Only include "poll_id", "option_id", and "user_id" in the request body
        let body: [String: String] = [
            "poll_id": pollID.uuidString,
            "option_id": optionID.uuidString,
            "user_id": userID.uuidString
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("VOTE HTTP status:", code)
        if code < 200 || code >= 300 {
            print("VOTE RAW response:", String(data: data, encoding: .utf8) ?? "<binary>")
        }
        guard (200...299).contains(code) else {
            throw URLError(.badServerResponse)
        }
    }
}
