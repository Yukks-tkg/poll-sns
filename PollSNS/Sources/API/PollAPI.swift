
import Foundation

// MARK: - Shared JSON decoder (ISO8601 dates; allow fractional seconds)
extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)

            // フォーマッタ（小数点あり）
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // フォーマッタ（小数点なし）
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]

            if let dt = frac.date(from: s) ?? plain.date(from: s) {
                return dt
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO8601 date (with/without fractional seconds). got=\(s)"
            )
        }
        return d
    }
}

enum PollAPI {
    // MARK: - Profiles model
    struct UserProfile: Codable {
        let user_id: UUID
        let username: String
        let age: Int?
        let prefecture_code: String?
        let country_code: String?
        let occupation: String?
        let avatar_type: String?
        let avatar_value: String?
        let avatar_color: String?
        let updated_at: Date?
        let created_at: Date?
    }

    // DBのCHECK制約に合わせた許可コード
    private static let allowedOccupation: Set<String> = [
        "student",
        "employee_fulltime",
        "employee_contract",
        "part_time",
        "freelancer",
        "self_employed",
        "public_servant",
        "homemaker",
        "unemployed",
        "other",
        "prefer_not_to_say"
    ]

    // MARK: - Profiles API
    /// 更新用の入力（nil は送らない）
    struct ProfileInput: Encodable {
        var display_name: String?
        var gender: String?
        var age: Int?
        var prefecture: String?
        var occupation: String?
        var icon_emoji: String?
    }

    /// 指定ユーザーのプロフィールを 1 件取得（無ければ nil）
    static func fetchProfile(userID: UUID) async throws -> UserProfile? {
        guard let base = URL(string: AppConfig.supabaseURL) else { return nil }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/profiles"
        comps.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "user_id,username,age,prefecture_code,country_code,occupation,avatar_type,avatar_value,avatar_color,created_at"),
            URLQueryItem(name: "limit", value: "1")
        ]
        let url = comps.url!
        print("PROFILE URL:", url.absoluteString)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("PROFILE HTTP:", code)
        guard (200...299).contains(code) else {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            print("PROFILE RAW:", raw)
            throw URLError(.badServerResponse)
        }

        // profiles は配列で返る（0件のときは []）
        do {
            let rows = try JSONDecoder.iso8601.decode([UserProfile].self, from: data)
            return rows.first
        } catch {
            // デコードエラー内容も出力しておく
            print("PROFILE DECODE ERROR:", error.localizedDescription,
                  "| RAW:", String(data: data, encoding: .utf8) ?? "<binary>")
            throw error
        }
    }

    /// プロフィールの Upsert（存在すれば更新、無ければ作成）
    /// - Returns: 反映後のプロフィール
    static func upsertProfile(userID: UUID, input: ProfileInput) async throws -> UserProfile {
        guard let base = URL(string: AppConfig.supabaseURL) else { throw URLError(.badURL) }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/profiles"
        // プロフィールは user_id を一意キーとして Upsert する
        comps.queryItems = [
            URLQueryItem(name: "on_conflict", value: "user_id")
        ]
        let url = comps.url!

        // DB スキーマに合わせてキー名を変換する
        // - display_name  -> username
        // - icon_emoji    -> avatar_value
        // - prefecture    -> prefecture_code
        // - country_code  は ProfileInput に無いので送らない（後で必要なら引数追加）
        var body: [String: Any] = ["user_id": userID.uuidString.uppercased()]
        if let v = input.display_name { body["username"] = v }
        if let v = input.icon_emoji { body["avatar_value"] = v }
        if let v = input.age { body["age"] = v }
        if let v = input.occupation, allowedOccupation.contains(v) {
            body["occupation"] = v
        }
        if let v = input.prefecture { body["prefecture_code"] = v }
        // gender は現在のテーブルに無い想定なので送らない

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        // 重複時はマージし、反映後の行を返す
        req.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            print("UPSERT PROFILE RAW:", raw)
            throw URLError(.badServerResponse)
        }
        let rows = try JSONDecoder.iso8601.decode([UserProfile].self, from: data)
        guard let profile = rows.first else { throw URLError(.cannotParseResponse) }
        return profile
    }

    // JSONDecoder 拡張（未定義なら追加）

    // MARK: - Results (client-side aggregation)
    static func fetchResults(for pollID: UUID) async throws -> [VoteResult] {
        // Client-side aggregation version (no GROUP on server)
        struct VoteRow: Decodable { let option_id: UUID }
        
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/votes"
        comps.queryItems = [
            URLQueryItem(name: "poll_id", value: "eq.\(pollID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "option_id"),
            URLQueryItem(name: "limit", value: "10000")
        ]
        
        let url = comps.url!
        print("RESULTS URL:", url.absoluteString)
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("RESULTS HTTP status:", code)
        if !(200...299).contains(code) {
            print("RESULTS RAW response:", String(data: data, encoding: .utf8) ?? "<binary>")
            throw URLError(.badServerResponse)
        }
        
        let rows = try JSONDecoder().decode([VoteRow].self, from: data)
        var counter: [UUID: Int] = [:]
        for r in rows { counter[r.option_id, default: 0] += 1 }
        return counter.map { VoteResult(option_id: $0.key, count: $0.value) }
    }

    /// 指定ユーザーがその Poll に投票済みかを判定（1件でもあれば true）
    static func hasVoted(pollID: UUID, userID: UUID) async throws -> Bool {
        guard let base = URL(string: AppConfig.supabaseURL) else { return false }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/votes"
        comps.queryItems = [
            URLQueryItem(name: "poll_id", value: "eq.\(pollID.uuidString.uppercased())"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "limit", value: "1")
        ]

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
            // 失敗時は false を返すより、上層で扱いたいのでエラー化
            throw URLError(.badServerResponse)
        }
        struct Row: Decodable { let id: UUID }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return !rows.isEmpty
    }

    /// Backward-compatible alias
    /// hasUserVoted: preferred name for clarity in call sites
    static func hasUserVoted(pollID: UUID, userID: UUID) async throws -> Bool {
        return try await hasVoted(pollID: pollID, userID: userID)
    }

    // MARK: - Polls
    static func fetchAllPolls(limit: Int = 20) async throws -> [Poll] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        comps.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        let url = comps.url!
        print("POLLS URL:", url.absoluteString)
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("POLLS HTTP status:", code)
        if !(200...299).contains(code) {
            print("POLLS RAW response:", String(data: data, encoding: .utf8) ?? "<binary>")
            throw URLError(.badServerResponse)
        }
        
        let polls = try JSONDecoder().decode([Poll].self, from: data)
        return polls
    }

    // MARK: - Options
    /// 選択肢一覧を取得
    static func fetchOptions(for pollID: UUID) async throws -> [PollOption] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/poll_options"
        comps.queryItems = [
            URLQueryItem(name: "poll_id", value: "eq.\(pollID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "*"),
            // 並び順を idx で管理しているなら以下を有効化
            // URLQueryItem(name: "order", value: "idx.asc"),
            URLQueryItem(name: "limit", value: "1000")
        ]

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("OPTIONS HTTP status:", code)
        if !(200...299).contains(code) {
            print("OPTIONS RAW response:", String(data: data, encoding: .utf8) ?? "<binary>")
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([PollOption].self, from: data)
    }

    // MARK: - Post a poll
    /// 質問・カテゴリ・選択肢（文字列配列）で Poll を作成
    /// 成功時は作成された Poll の id を返す
    static func createPoll(question: String,
                           category: String,
                           options: [String]) async throws -> UUID {
        // 1) polls を1行作成（return=representation で id を貰う）
        guard let base = URL(string: AppConfig.supabaseURL) else { throw URLError(.badURL) }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        let urlPoll = comps.url!

        var reqPoll = URLRequest(url: urlPoll)
        reqPoll.httpMethod = "POST"
        reqPoll.setValue("application/json", forHTTPHeaderField: "Content-Type")
        reqPoll.setValue("application/json", forHTTPHeaderField: "Accept")
        reqPoll.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        reqPoll.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        // 作成後の行を返してもらう
        reqPoll.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let pollPayload: [String: Any] = [
            "question": question,
            "category": category,
            // 開発中は固定ユーザーで作成（本番は Supabase Auth の JWT から付与）
            "owner_id": AppConfig.devUserID.uuidString.uppercased(),
            // タイムラインで誰でも見えるように公開
            "is_public": true
        ]
        reqPoll.httpBody = try JSONSerialization.data(withJSONObject: pollPayload)

        print("POST /polls", pollPayload)
        let (pData, pResp) = try await URLSession.shared.data(for: reqPoll)
        let pCode = (pResp as? HTTPURLResponse)?.statusCode ?? -1
        print("POST polls HTTP:", pCode, "RAW:", String(data: pData, encoding: .utf8) ?? "<binary>")
        guard (200...299).contains(pCode) else { throw URLError(.badServerResponse) }

        // 返却は配列（行配列）なので decode
        struct CreatedPoll: Decodable { let id: UUID }
        let createdPolls = try JSONDecoder().decode([CreatedPoll].self, from: pData)
        guard let pollID = createdPolls.first?.id else { throw URLError(.cannotParseResponse) }

        // 2) poll_options を一括作成
        if !options.isEmpty {
            var compsOpt = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            compsOpt.path = "/rest/v1/poll_options"
            let urlOpts = compsOpt.url!

            var reqOpts = URLRequest(url: urlOpts)
            reqOpts.httpMethod = "POST"
            reqOpts.setValue("application/json", forHTTPHeaderField: "Content-Type")
            reqOpts.setValue("application/json", forHTTPHeaderField: "Accept")
            reqOpts.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            reqOpts.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            // 作成後のレスポンスは不要
            reqOpts.setValue("return=minimal", forHTTPHeaderField: "Prefer")

            // idx をふって一括POST
            let optRows: [[String: Any]] = options.enumerated().map { (i, label) in
                [
                    "poll_id": pollID.uuidString.uppercased(),
                    "idx": i + 1,         // 並び順を idx で管理する想定
                    "label": label
                ]
            }
            reqOpts.httpBody = try JSONSerialization.data(withJSONObject: optRows)

            print("POST /poll_options", optRows)
            let (oData, oResp) = try await URLSession.shared.data(for: reqOpts)
            let oCode = (oResp as? HTTPURLResponse)?.statusCode ?? -1
            print("POST options HTTP:", oCode, "RAW:", String(data: oData, encoding: .utf8) ?? "<binary>")
            guard (200...299).contains(oCode) else {
                // 失敗時に polls 側を消すロールバックを試みる（任意）
                Task { try? await deletePoll(pollID: pollID) }
                throw URLError(.badServerResponse)
            }
        }

        return pollID
    }

    /// （任意）ロールバック用の削除
    static func deletePoll(pollID: UUID) async throws {
        guard let base = URL(string: AppConfig.supabaseURL) else { return }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        comps.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(pollID.uuidString.uppercased())")
        ]
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("DELETE poll HTTP:", code)
    }

    // MARK: - Vote (Upsert: duplicate -> 2xx)
    static func submitVote(pollID: UUID, optionID: UUID, userID: UUID) async throws {
        guard let base = URL(string: AppConfig.supabaseURL) else { return }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/votes"
        // ★ 既存投票（poll_id,user_id）があっても 2xx を返すための Upsert 指定
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
        // ★ 重複時はマージ扱い（409を返さず 2xx にする）＋最小レスポンス
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")

        let payload: [String: String] = [
            "poll_id":   pollID.uuidString,
            "user_id":   userID.uuidString,
            "option_id": optionID.uuidString
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Debug logs
        print("VOTE URL:", url.absoluteString)
        print("VOTE body:", payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("VOTE HTTP status:", code)

        if !(200...299).contains(code) {
            // 2xx 以外は内容を出して失敗
            print("VOTE RAW response:", String(data: data, encoding: .utf8) ?? "<binary>")
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Compatibility / Enhanced fetch
    /// Polls を取得（デフォルト: 最新順）。category を指定すると eq.<key> で絞り込み。
    /// 既存呼び出しは `limit` だけでも動作します（order/category はデフォルト）。
    static func fetchPolls(limit: Int = 20,
                           order: String = "created_at.desc",
                           category: String? = nil) async throws -> [Poll] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"

        var items: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id"),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let cat = category, !cat.isEmpty {
            items.append(URLQueryItem(name: "category", value: "eq.\(cat)"))
        }
        comps.queryItems = items

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("POLLS HTTP status:", code, "URL:", url.absoluteString)
        guard (200...299).contains(code) else {
            print("POLLS RAW response:", String(data: data, encoding: .utf8) ?? "<binary>")
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([Poll].self, from: data)
    }

    // MARK: - Popular polls (like_count.desc, then created_at.desc)
    static func fetchPollsPopular(limit: Int = 20,
                                  category: String? = nil) async throws -> [Poll] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls_popular"

        var items: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id,like_count"),
            URLQueryItem(name: "order", value: "like_count.desc,created_at.desc"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let cat = category, !cat.isEmpty {
            items.append(URLQueryItem(name: "category", value: "eq.\(cat)"))
        }
        comps.queryItems = items

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("POLLS(POPULAR) HTTP status:", code, "URL:", url.absoluteString)
        guard (200...299).contains(code) else {
            print("POLLS(POPULAR) RAW:", String(data: data, encoding: .utf8) ?? "<binary>")
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Poll].self, from: data)
    }

    // MARK: - Likes
    /// いいね（重複は成功扱いにする）
    static func like(pollID: UUID, userID: UUID) async throws {
        guard let base = URL(string: AppConfig.supabaseURL) else { return }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/likes"
        // 既に (poll_id, user_id) が存在していても 2xx にする
        comps.queryItems = [
            URLQueryItem(name: "on_conflict", value: "poll_id,user_id")
        ]
        let url = comps.url!
        print("LIKE URL:", url.absoluteString)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        // 重複時も 2xx にする + レスポンス最小化
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")

        let payload: [String: String] = [
            "poll_id": pollID.uuidString.uppercased(),
            "user_id": userID.uuidString.uppercased()
        ]
        print("LIKE BODY:", payload)
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("LIKE HTTP:", code)
        if !(200...299).contains(code) {
            let dataStr = String(data: data, encoding: .utf8) ?? "<binary>"
            print("LIKE RAW:", dataStr)
            throw URLError(.badServerResponse)
        }
    }

    /// いいね解除
    static func unlike(pollID: UUID, userID: UUID) async throws {
        guard let base = URL(string: AppConfig.supabaseURL) else { return }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/likes"
        comps.queryItems = [
            URLQueryItem(name: "poll_id", value: "eq.\(pollID.uuidString.uppercased())"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.uppercased())")
        ]
        let url = comps.url!
        print("UNLIKE URL:", url.absoluteString)

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("UNLIKE HTTP:", code)
        if !(200...299).contains(code) {
            let dataStr = String(data: data, encoding: .utf8) ?? "<binary>"
            print("UNLIKE RAW:", dataStr)
            throw URLError(.badServerResponse)
        }
    }

    /// 複数ポストのいいね数を取得
    static func fetchLikeCounts(pollIDs: [UUID]) async throws -> [UUID: Int] {
        // クライアント集計版: サーバーからは poll_id のみ取得して端末でカウント
        guard !pollIDs.isEmpty else { return [:] }
        guard let base = URL(string: AppConfig.supabaseURL) else { return [:] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/likes"

        // in.(UUID,UUID,...) 形式に整形（大文字UUID）
        let inList = pollIDs.map { $0.uuidString.uppercased() }.joined(separator: ",")
        comps.queryItems = [
            URLQueryItem(name: "poll_id", value: "in.(\(inList))"),
            URLQueryItem(name: "select", value: "poll_id"),
            URLQueryItem(name: "limit", value: "10000")
        ]

        let url = comps.url!
        print("LIKE COUNTS URL:", url.absoluteString)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("LIKE COUNTS HTTP:", code)
        guard (200...299).contains(code) else {
            print("LIKE COUNTS RAW:", String(data: data, encoding: .utf8) ?? "<binary>")
            throw URLError(.badServerResponse)
        }

        // サーバーからは { poll_id } の配列だけを受け取り、端末でカウント
        struct Row: Decodable { let poll_id: UUID }
        let rows = try JSONDecoder().decode([Row].self, from: data)

        var result: [UUID: Int] = [:]
        for r in rows { result[r.poll_id, default: 0] += 1 }
        return result
    }

    /// 指定ユーザーが like 済みの poll_id セットを取得
    static func fetchUserLiked(pollIDs: [UUID], userID: UUID) async throws -> Set<UUID> {
        guard !pollIDs.isEmpty else { return [] }
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/likes"

        let inList = pollIDs.map { $0.uuidString.uppercased() }.joined(separator: ",")
        comps.queryItems = [
            URLQueryItem(name: "poll_id", value: "in.(\(inList))"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "poll_id"),
            URLQueryItem(name: "limit", value: "10000")
        ]

        let url = comps.url!
        print("USER LIKED URL:", url.absoluteString)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("USER LIKED HTTP:", code)
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }

        struct Row: Decodable { let poll_id: UUID }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return Set(rows.map(\.poll_id))
    }
    // MARK: - My content helpers
    /// 自分が作成した Poll 一覧を取得（最新順）
    static func fetchMyPosts(ownerID: UUID,
                             limit: Int = 50,
                             order: String = "created_at.desc") async throws -> [Poll] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        comps.queryItems = [
            URLQueryItem(name: "owner_id", value: "eq.\(ownerID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id"),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([Poll].self, from: data)
    }

    /// Backward-compat: older call sites used fetchMyPolls
    /// Delegates to fetchMyPosts(ownerID:limit:order:)
    static func fetchMyPolls(ownerID: UUID,
                             limit: Int = 50,
                             order: String = "created_at.desc") async throws -> [Poll] {
        return try await fetchMyPosts(ownerID: ownerID, limit: limit, order: order)
    }

    /// 自分が投票した Poll 一覧を取得（最新順）
    static func fetchMyVoted(userID: UUID,
                             limit: Int = 50,
                             order: String = "created_at.desc") async throws -> [Poll] {
        // Step 1: 自分の vote から poll_id を収集
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var compsIDs = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        compsIDs.path = "/rest/v1/votes"
        compsIDs.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "poll_id"),
            URLQueryItem(name: "limit", value: "10000")
        ]

        var reqIDs = URLRequest(url: compsIDs.url!)
        reqIDs.httpMethod = "GET"
        reqIDs.setValue("application/json", forHTTPHeaderField: "Accept")
        reqIDs.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        reqIDs.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (idData, idResp) = try await URLSession.shared.data(for: reqIDs)
        let idCode = (idResp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(idCode) else { throw URLError(.badServerResponse) }

        struct IDRow: Decodable { let poll_id: UUID }
        let idRows = try JSONDecoder().decode([IDRow].self, from: idData)
        let ids = Array(Set(idRows.map { $0.poll_id })) // distinct
        guard !ids.isEmpty else { return [] }

        // Step 2: poll 本体をまとめて取得
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        let inList = ids.map { $0.uuidString.uppercased() }.joined(separator: ",")
        comps.queryItems = [
            URLQueryItem(name: "id", value: "in.(\(inList))"),
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id"),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([Poll].self, from: data)
    }
}
