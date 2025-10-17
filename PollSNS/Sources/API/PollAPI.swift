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
    // MARK: - Supabase Headers Helper
    /// Adds required Supabase headers to a URLRequest (Accept, apikey, Authorization).
    private static func addSupabaseHeaders(to req: inout URLRequest) {
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
    }
    // MARK: - Profiles model
    struct UserProfile: Codable {
        let user_id: UUID
        let username: String
        let gender: String?
        let age: Int?
        let country_code: String?
        let avatar_type: String?
        let avatar_value: String?
        let avatar_color: String?
        let region: String?          // ← 追加
        let updated_at: Date?
        let created_at: Date?
    }


    // MARK: - Reports (reason enum)
    enum ReportReason: String, CaseIterable {
        case spam, hate, nsfw, illegal, privacy, other

        var display: String {
            switch self {
            case .spam: return "スパム・宣伝"
            case .hate: return "差別・中傷"
            case .nsfw: return "不快・アダルト"
            case .illegal: return "違法・危険"
            case .privacy: return "個人情報"
            case .other: return "その他"
            }
        }
    }

    // MARK: - Filtered results (k-anonymity aware via RPC)
    struct PollResultFilters: Encodable {
        var minAge: Int? = nil
        var maxAge: Int? = nil
        var ageBucketWidth: Int = 7              // 5/7/10
        var countryCode: String? = nil           // e.g., "JP"
        var gender: String? = nil              // "male" | "female" | "other" | nil(=all)

        func toRPCBody(pollID: UUID) -> [String: Any] {
            var body: [String: Any] = [
                "p_poll_id": pollID.uuidString,
                "p_age_bucket_width": ageBucketWidth
            ]
            if let v = minAge { body["p_min_age"] = v }
            if let v = maxAge { body["p_max_age"] = v }
            if let v = countryCode { body["p_country_code"] = v }
            if let v = gender { body["p_gender"] = v }
            return body
        }
    }

    struct FilteredVoteRow: Decodable, Identifiable {
        let option_id: UUID
        let option_label: String
        let cnt: Int
        let total: Int

        var id: UUID { option_id }
        var percentage: Int {
            guard total > 0 else { return 0 }
            return Int(round((Double(cnt) / Double(total)) * 100.0))
        }
    }

    static func fetchFilteredResults(pollID: UUID, filters: PollResultFilters) async throws -> [FilteredVoteRow] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/rpc/poll_results_filtered"
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &req)

        let body = filters.toRPCBody(pollID: pollID)
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder.iso8601.decode([FilteredVoteRow].self, from: data)
    }

    // MARK: - Profiles API
    /// 更新用の入力（nil は送らない）
    struct ProfileInput: Encodable {
        var display_name: String?
        var gender: String?
        var age: Int?
        var icon_emoji: String?
        var region: String?
    }

    /// 指定ユーザーのプロフィールを 1 件取得（無ければ nil）
    static func fetchProfile(userID: UUID) async throws -> UserProfile? {
        guard let base = URL(string: AppConfig.supabaseURL) else { return nil }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/profiles"
        comps.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "user_id,username,gender,age,country_code,avatar_type,avatar_value,avatar_color,region,created_at"),
            URLQueryItem(name: "limit", value: "1")
        ]
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }

        // profiles は配列で返る（0件のときは []）
        do {
            let rows = try JSONDecoder.iso8601.decode([UserProfile].self, from: data)
            return rows.first
        } catch {
            throw error
        }
    }

    /// 投稿者のアバター絵文字だけ欲しいときの軽量ヘルパー
    /// fetchProfile の薄いラッパー（将来スキーマ変更時の影響を局所化）
    static func fetchOwnerEmoji(userID: UUID) async throws -> String? {
        let profile = try await fetchProfile(userID: userID)
        return profile?.avatar_value
    }

    /// 確実に users テーブルに userID を作成（存在しても2xxでOK）
    static func ensureUserExists(userID: UUID) async throws {
        guard let base = URL(string: AppConfig.supabaseURL) else { throw URLError(.badURL) }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/users"
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &req)
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = ["id": userID.uuidString.uppercased()]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
            throw URLError(.badServerResponse)
        }
    }

    /// プロフィールの Upsert（存在すれば更新、無ければ作成）
    /// - Returns: 反映後のプロフィール
    static func upsertProfile(userID: UUID, input: ProfileInput) async throws -> UserProfile {
        guard let base = URL(string: AppConfig.supabaseURL) else { throw URLError(.badURL) }

        // 先に users テーブルに自分の ID を作成（外部キー制約対策）
        try await ensureUserExists(userID: userID)

        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/profiles"
        // プロフィールは user_id を一意キーとして Upsert する
        comps.queryItems = [
            URLQueryItem(name: "on_conflict", value: "user_id")
        ]
        let url = comps.url!

        // DBスキーマに合わせてキー名を変換する
        // - display_name  -> username
        // - icon_emoji    -> avatar_value
        // - country_code  は ProfileInput に無いので送らない（後で必要なら引数追加）
        var body: [String: Any] = ["user_id": userID.uuidString.uppercased()]
        if let v = input.display_name { body["username"] = v }
        if let v = input.icon_emoji { body["avatar_value"] = v }
        if let v = input.age { body["age"] = v }
        // gender を保存（DB 側のチェック制約に合わせて許可値のみ）
        if let v = input.gender, ["male","female","other"].contains(v) {
            body["gender"] = v
        }
        if let v = input.region { body["region"] = v }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &req)
        // 重複時はマージし、反映後の行を返す
        req.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        let rows = try JSONDecoder.iso8601.decode([UserProfile].self, from: data)
        guard let profile = rows.first else { throw URLError(.cannotParseResponse) }
        return profile
    }

    // 最小プロフィール（自動作成用）
    struct MinimalProfile: Codable {
        let user_id: UUID
        let username: String?
        let created_at: Date?
    }

    /// profiles に行がない場合は新規作成（既にあれば何もしない）
    static func ensureProfileExists(userID: UUID) async throws {
        // 既存チェック
        if let _ = try await fetchProfile(userID: userID) { return }

        // 最低限の行を upsert（username は空）
        guard let base = URL(string: AppConfig.supabaseURL) else { throw URLError(.badURL) }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/profiles"
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        addSupabaseHeaders(to: &req)

        let payload = [MinimalProfile(user_id: userID, username: nil, created_at: Date())]
        req.httpBody = try JSONEncoder().encode(payload)

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
    }


    // Helper for gender-filtered aggregation: join votes with profiles(gender)
    private struct RawVoteWithProfile: Decodable {
        let option_id: UUID
        struct ProfileStub: Decodable { let gender: String? }
        let profiles: ProfileStub?
    }

    // MARK: - Results (client-side aggregation)

    // Gender breakdown per option (male/female/other) with optional age range filter
    struct GenderBreakdown: Identifiable {
        let option_id: UUID
        var male: Int
        var female: Int
        var other: Int
        var total: Int { male + female + other }
        var id: UUID { option_id }
    }

    /// 各選択肢ごとの性別内訳（male/female/other）を取得します。
    /// 年齢フィルタ（ageMin/ageMax）が指定された場合は、該当年齢の投票のみを集計します。
    static func fetchGenderBreakdown(for pollID: UUID, ageMin: Int? = nil, ageMax: Int? = nil) async throws -> [GenderBreakdown] {
        // RPC: fetch_gender_breakdown(_poll_id uuid)
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/rpc/fetch_gender_breakdown"
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &req)

        let body: [String: Any] = ["_poll_id": pollID.uuidString]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }

        struct Row: Decodable { let option_id: UUID; let male: Int; let female: Int; let other: Int }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.map { r in
            GenderBreakdown(option_id: r.option_id, male: r.male, female: r.female, other: r.other)
        }
    }

    // Age breakdown per option (10代/20代/30代/40代/50代以上)
    struct AgeBreakdown: Identifiable {
        let option_id: UUID
        var teens: Int
        var twenties: Int
        var thirties: Int
        var forties: Int
        var fiftiesPlus: Int
        var total: Int { teens + twenties + thirties + forties + fiftiesPlus }
        var id: UUID { option_id }
    }

    /// 各選択肢ごとの年代内訳（10/20/30/40/50+）を取得します。
    /// gender を指定した場合は、該当性別のみを集計します（nil なら全体）。
    /// 既存コードへ影響しないように新規 API として追加。
    static func fetchAgeBreakdown(for pollID: UUID, gender: String? = nil) async throws -> [AgeBreakdown] {
        // RPC: fetch_age_breakdown(_poll_id uuid)
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/rpc/fetch_age_breakdown"
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &req)

        let body: [String: Any] = ["_poll_id": pollID.uuidString]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }

        struct Row: Decodable {
            let option_id: UUID
            let teens: Int
            let twenties: Int
            let thirties: Int
            let forties: Int
            let fiftiesplus: Int // 注意: Postgresは小文字
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.map { r in
            AgeBreakdown(option_id: r.option_id,
                         teens: r.teens,
                         twenties: r.twenties,
                         thirties: r.thirties,
                         forties: r.forties,
                         fiftiesPlus: r.fiftiesplus)
        }
    }

    // Region breakdown per option (北海道/東北/関東/中部/近畿/中国/四国/九州・沖縄/海外/無回答)
    struct RegionBreakdown: Codable, Identifiable {
        let option_id: UUID
        var hokkaido: Int
        var tohoku: Int
        var kanto: Int
        var chubu: Int
        var kinki: Int
        var chugoku: Int
        var shikoku: Int
        var kyushu_okinawa: Int
        var overseas: Int
        var no_answer: Int
        var total: Int { hokkaido + tohoku + kanto + chubu + kinki + chugoku + shikoku + kyushu_okinawa + overseas + no_answer }
        var id: UUID { option_id }
    }

    /// 各選択肢ごとの地域内訳（北海道/東北/関東/中部/近畿/中国/四国/九州・沖縄/海外/無回答）を取得します。
    /// RPC `fetch_region_breakdown(_poll_id uuid)` は
    /// (option_id uuid, hokkaido int, tohoku int, kanto int, chubu int, kinki int,
    ///  chugoku int, shikoku int, kyushu_okinawa int, overseas int, no_answer int)
    /// の **横持ち** 形式を返すため、そのまま `RegionBreakdown` としてデコードします。
    /// 互換性のため、旧形式（region/votes の縦持ち）もフォールバックで対応します。
    static func fetchRegionBreakdown(for pollID: UUID) async throws -> [RegionBreakdown] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/rpc/fetch_region_breakdown"
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &req)

        let body: [String: Any] = ["_poll_id": pollID.uuidString]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }

        // 1) 新RPC（横持ち, snake_case）: そのまま RegionBreakdown としてデコード
        do {
            let list = try JSONDecoder().decode([RegionBreakdown].self, from: data)
            return list
        } catch {
            // 続行（フォールバックへ）
        }

        // 2) 横持ちだけど camelCase or NULL が混じる場合の寛容デコード
        //    - keyDecodingStrategy = .convertFromSnakeCase を使い、
        //      プロパティは camelCase（optionId, kyushuOkinawa, noAnswer 等）で定義
        //    - Int? で受けて nil は 0 に丸める
        struct LooseRow: Decodable {
            let optionId: UUID
            let hokkaido: Int?
            let tohoku: Int?
            let kanto: Int?
            let chubu: Int?
            let kinki: Int?
            let chugoku: Int?
            let shikoku: Int?
            let kyushuOkinawa: Int?   // kyushu_okinawa / kyushuOkinawa 両対応
            let overseas: Int?
            let noAnswer: Int?
        }
        do {
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            let rows = try dec.decode([LooseRow].self, from: data)
            return rows.map { r in
                RegionBreakdown(
                    option_id: r.optionId,
                    hokkaido: r.hokkaido ?? 0,
                    tohoku: r.tohoku ?? 0,
                    kanto: r.kanto ?? 0,
                    chubu: r.chubu ?? 0,
                    kinki: r.kinki ?? 0,
                    chugoku: r.chugoku ?? 0,
                    shikoku: r.shikoku ?? 0,
                    kyushu_okinawa: r.kyushuOkinawa ?? 0,
                    overseas: r.overseas ?? 0,
                    no_answer: r.noAnswer ?? 0
                )
            }
        } catch {
            // 続行（旧形式フォールバックへ）
        }

        // 3) 旧RPC（縦持ち）: option_id / region / votes を集約して RegionBreakdown に作り直す
        struct OldRow: Decodable { let option_id: UUID; let region: String; let votes: Int }
        let rows = try JSONDecoder().decode([OldRow].self, from: data)
        var map: [UUID: RegionBreakdown] = [:]
        func empty(_ id: UUID) -> RegionBreakdown {
            RegionBreakdown(option_id: id,
                            hokkaido: 0, tohoku: 0, kanto: 0, chubu: 0, kinki: 0,
                            chugoku: 0, shikoku: 0, kyushu_okinawa: 0, overseas: 0, no_answer: 0)
        }
        for r in rows {
            var agg = map[r.option_id] ?? empty(r.option_id)
            switch r.region {
            case "北海道", "hokkaido": agg.hokkaido = r.votes
            case "東北", "tohoku": agg.tohoku = r.votes
            case "関東", "kanto": agg.kanto = r.votes
            case "中部", "chubu": agg.chubu = r.votes
            case "近畿", "関西", "kinki": agg.kinki = r.votes
            case "中国", "chugoku": agg.chugoku = r.votes
            case "四国", "shikoku": agg.shikoku = r.votes
            case "九州・沖縄", "九州沖縄", "kyushu_okinawa", "kyushuOkinawa": agg.kyushu_okinawa = r.votes
            case "海外", "overseas": agg.overseas = r.votes
            case "無回答", "no_answer", "noAnswer", "unknown", "null": agg.no_answer = r.votes
            default: break
            }
            map[r.option_id] = agg
        }
        return Array(map.values)
    }
    static func fetchResults(for pollID: UUID, gender: String? = nil, ageMin: Int? = nil, ageMax: Int? = nil) async throws -> [VoteResult] {
        // If gender or age is specified, join profiles to read gender/age and aggregate client-side
        if (gender != nil) || (ageMin != nil) || (ageMax != nil) {
            let genderParam = gender // capture for inner use
            // Step 1: votes から option_id と user_id を取得
            struct VoteUIDRow: Decodable { let option_id: UUID; let user_id: UUID }
            guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
            var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            comps.path = "/rest/v1/votes"
            comps.queryItems = [
                URLQueryItem(name: "poll_id", value: "eq.\(pollID.uuidString.uppercased())"),
                URLQueryItem(name: "select", value: "option_id,user_id"),
                URLQueryItem(name: "limit", value: "10000")
            ]
            let votesURL = comps.url!
            var votesReq = URLRequest(url: votesURL)
            votesReq.httpMethod = "GET"
            addSupabaseHeaders(to: &votesReq)
            let (vData, vResp) = try await URLSession.shared.data(for: votesReq)
            let vCode = (vResp as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(vCode) else {
                throw URLError(.badServerResponse)
            }
            let voteRows = try JSONDecoder().decode([VoteUIDRow].self, from: vData)
            if voteRows.isEmpty { return [] }

            // Step 2: profiles から対象 user_id の gender/age を取得（URL長対策で分割）
            let userIDs = Array(Set(voteRows.map { $0.user_id }))
            struct ProfileRow: Decodable { let user_id: UUID; let gender: String?; let age: Int? }
            var genderMap: [UUID: String] = [:]
            var ageMap: [UUID: Int] = [:]

            let chunkSize = 200
            for start in stride(from: 0, to: userIDs.count, by: chunkSize) {
                let end = min(start + chunkSize, userIDs.count)
                let chunk = userIDs[start..<end]
                let inList = chunk.map { $0.uuidString.uppercased() }.joined(separator: ",")
                var pComps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
                pComps.path = "/rest/v1/profiles"
                pComps.queryItems = [
                    URLQueryItem(name: "user_id", value: "in.(\(inList))"),
                    URLQueryItem(name: "select", value: "user_id,gender,age"),
                    URLQueryItem(name: "limit", value: "\(chunk.count)")
                ]
                let profURL = pComps.url!
                var profReq = URLRequest(url: profURL)
                profReq.httpMethod = "GET"
                addSupabaseHeaders(to: &profReq)
                let (pData, pResp) = try await URLSession.shared.data(for: profReq)
                let pCode = (pResp as? HTTPURLResponse)?.statusCode ?? -1
                guard (200...299).contains(pCode) else {
                    throw URLError(.badServerResponse)
                }
                let profiles = try JSONDecoder().decode([ProfileRow].self, from: pData)
                for prof in profiles {
                    if let g = prof.gender { genderMap[prof.user_id] = g }
                    if let a = prof.age { ageMap[prof.user_id] = a }
                }
            }

            // Step 3: 指定 gender/age のみ集計
            var counter: [UUID: Int] = [:]
            for r in voteRows {
                // Gender filter
                if let gNeeded = genderParam {
                    guard genderMap[r.user_id] == gNeeded else { continue }
                }
                // Age filters
                if let minA = ageMin {
                    guard let a = ageMap[r.user_id], a >= minA else { continue }
                }
                if let maxA = ageMax {
                    guard let a = ageMap[r.user_id], a <= maxA else { continue }
                }
                counter[r.option_id, default: 0] += 1
            }
            return counter.map { VoteResult(option_id: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
        }

        // gender が無い場合は、従来通り option_id だけを取得して端末で集計
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

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder().decode([VoteRow].self, from: data)
        var counter: [UUID: Int] = [:]
        for r in rows { counter[r.option_id, default: 0] += 1 }
        return counter.map { VoteResult(option_id: $0.key, count: $0.value) }
    }

    // MARK: - Filtered results (client-side fallback for filter UI)
    /// フィルタUI用の簡易フィルタ。現状はクライアント側集計のため
    /// サーバーへのクエリ条件には使っていません（将来 RPC 版へ切替予定）。
    struct ResultFilter: Encodable {
        var minAge: Int? = nil
        var maxAge: Int? = nil
        var countryCode: String? = nil     // 例: "JP"
    }

    /// フィルタ指定つきの結果取得（UI のための薄いラッパー）。
    /// いまは既存の `fetchResults(for:)` を呼んで合計票数を同時に返すだけ。
    /// 将来、サーバー側集計（RPC）に切り替える際は、ここで `filters` を使って
    /// `fetchFilteredResults(pollID:filters:)` を呼ぶように差し替えます。
    static func fetchResults(pollID: UUID, filter: ResultFilter?) async throws -> (rows: [VoteResult], total: Int) {
        let rows = try await fetchResults(for: pollID, gender: nil)
        let total = rows.reduce(0) { $0 + $1.count }
        return (rows, total)
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
        addSupabaseHeaders(to: &req)

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

    // MARK: - Votes (user voted set / map with option label)
    /// 指定の pollIDs のうち、ユーザーが投票済みの poll_id セットを取得します（バッジ用途）。
    static func fetchUserVoted(pollIDs: [UUID], userID: UUID) async throws -> Set<UUID> {
        guard !pollIDs.isEmpty else { return [] }
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/votes"
        // poll_id in (...) & user_id = ...
        let idsString = pollIDs.map { $0.uuidString.uppercased() }.joined(separator: ",")
        comps.queryItems = [
            URLQueryItem(name: "poll_id", value: "in.(\(idsString))"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "poll_id"),
            URLQueryItem(name: "limit", value: "10000")
        ]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        struct Row: Decodable { let poll_id: UUID }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let rows = try JSONDecoder.iso8601.decode([Row].self, from: data)
        return Set(rows.map(\.poll_id))
    }

    /// ユーザーが選んだ option のラベルまで含めて取得（一覧で「あなたの選択：◯◯」と出す用途）
    /// 返り値: pollID -> (optionID, optionLabel?)
    static func fetchUserVoteDetailMap(pollIDs: [UUID], userID: UUID) async throws -> [UUID: (UUID, String?)] {
        guard !pollIDs.isEmpty else { return [:] }
        guard let base = URL(string: AppConfig.supabaseURL) else { return [:] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/votes"
        let idsString = pollIDs.map { $0.uuidString.uppercased() }.joined(separator: ",")
        // 外部キーで poll_options を紐づけて label を取得（PostgREST のリレーション記法）
        comps.queryItems = [
            URLQueryItem(name: "poll_id", value: "in.(\(idsString))"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "poll_id,option_id,option:poll_options(label,id)"),
            URLQueryItem(name: "limit", value: "10000")
        ]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        struct Row: Decodable {
            let poll_id: UUID
            let option_id: UUID
            struct Opt: Decodable { let label: String?; let id: UUID? }
            let option: Opt?
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let rows = try JSONDecoder.iso8601.decode([Row].self, from: data)
        var map: [UUID: (UUID, String?)] = [:]
        for r in rows { map[r.poll_id] = (r.option_id, r.option?.label) }
        return map
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
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
            throw URLError(.badServerResponse)
        }
        
        let polls = try JSONDecoder().decode([Poll].self, from: data)
        return polls
    }

    /// Poll を1件だけ取得（deleted_at is null のみ対象）
    static func fetchPollDetail(id: UUID) async throws -> Poll? {
        guard let base = URL(string: AppConfig.supabaseURL) else { return nil }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        comps.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id,description"),
            URLQueryItem(name: "deleted_at", value: "is.null"),
            URLQueryItem(name: "limit", value: "1")
        ]
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }

        let rows = try JSONDecoder().decode([Poll].self, from: data)
        return rows.first
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
            URLQueryItem(name: "limit", value: "1000")
        ]

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([PollOption].self, from: data)
    }

    // MARK: - Post a poll
    /// 質問・カテゴリ・選択肢（文字列配列）で Poll を作成
    /// 成功時は作成された Poll の id を返す
    static func createPoll(question: String,
                           category: String,
                           options: [String],
                           description: String? = nil) async throws -> UUID {
        // 1) polls を1行作成（return=representation で id を貰う）
        guard let base = URL(string: AppConfig.supabaseURL) else { throw URLError(.badURL) }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        let urlPoll = comps.url!

        var reqPoll = URLRequest(url: urlPoll)
        reqPoll.httpMethod = "POST"
        reqPoll.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &reqPoll)
        // 作成後の行を返してもらう
        reqPoll.setValue("return=representation", forHTTPHeaderField: "Prefer")

        var pollPayload: [String: Any] = [
            "question": question,
            "category": category,
            // 端末ごとの currentUserID を利用（本番は Supabase Auth の JWT から付与）
            "owner_id": AppConfig.currentUserID.uuidString.uppercased(),
            // タイムラインで誰でも見えるように公開
            "is_public": true
        ]
        if let d = description, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pollPayload["description"] = d
        }
        reqPoll.httpBody = try JSONSerialization.data(withJSONObject: pollPayload)

        let (pData, pResp) = try await URLSession.shared.data(for: reqPoll)
        let pCode = (pResp as? HTTPURLResponse)?.statusCode ?? -1
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
            addSupabaseHeaders(to: &reqOpts)
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

            let (_, oResp) = try await URLSession.shared.data(for: reqOpts)
            let oCode = (oResp as? HTTPURLResponse)?.statusCode ?? -1
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
        addSupabaseHeaders(to: &req)

        let (_, resp) = try await URLSession.shared.data(for: req)
        _ = (resp as? HTTPURLResponse)?.statusCode ?? -1
    }

    // MARK: - Soft delete (set deleted_at)
    /// 自分の投稿をソフト削除（deleted_at を現在時刻でセット）
    static func softDeleteOwnPoll(pollID: UUID) async throws {
        guard let base = URL(string: AppConfig.supabaseURL) else { throw URLError(.badURL) }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        comps.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(pollID.uuidString.uppercased())")
        ]
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &req)

        // クライアント時刻で十分。サーバー時刻にしたい場合は RPC を用意して now() を使う。
        let iso = ISO8601DateFormatter()
        let body: [String: Any] = ["deleted_at": iso.string(from: Date())]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Vote (RPC: submit_vote)
    static func submitVote(pollID: UUID, optionID: UUID, userID: UUID) async throws {
        guard let base = URL(string: AppConfig.supabaseURL) else { return }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/rpc/submit_vote"
        let url = comps.url!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &req)

        let body: [String: Any] = [
            "_poll_id": pollID.uuidString.uppercased(),
            "_option_id": optionID.uuidString.uppercased(),
            "_user_id": userID.uuidString.uppercased()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
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
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id,description"),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "deleted_at", value: "is.null")
        ]
        if let cat = category, !cat.isEmpty {
            items.append(URLQueryItem(name: "category", value: "eq.\(cat)"))
        }
        comps.queryItems = items

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }

        return try JSONDecoder().decode([Poll].self, from: data)
    }

    // MARK: - Popular polls (like_count.desc, then created_at.desc)
    static func fetchPollsPopular(limit: Int = 20,
                                  category: String? = nil) async throws -> [Poll] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls_popular"

        var items: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id,like_count,description"),
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
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([Poll].self, from: data)
    }

    // MARK: - Reports
    /// 通報を送信（Edge Function経由）
    static func submitReport(
        pollID: UUID,
        reporterUserID: UUID,
        reason: ReportReason,
        detail: String? = nil
    ) async throws {
        // Send to Supabase Edge Function (submit-report)
        guard let base = URL(string: AppConfig.supabaseURL) else { throw URLError(.badURL) }
        let url = base.appendingPathComponent("/functions/v1/submit-report")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Required headers for Functions gateway and our shared secret
        req.setValue(AppConfig.reportToken, forHTTPHeaderField: "X-Report-Token")
        addSupabaseHeaders(to: &req)

        // Function expects a single JSON object, not an array
        let body: [String: Any] = [
            "poll_id": pollID.uuidString.uppercased(),
            "reporter_user_id": reporterUserID.uuidString.uppercased(),
            "reason_code": reason.rawValue,
            "reason_text": detail ?? NSNull()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1

        switch code {
        case 200, 201:
            return
        default:
            throw URLError(.badServerResponse)
        }
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

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addSupabaseHeaders(to: &req)
        // 重複時も 2xx にする + レスポンス最小化
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")

        let payload: [String: String] = [
            "poll_id": pollID.uuidString.uppercased(),
            "user_id": userID.uuidString.uppercased()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
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

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        addSupabaseHeaders(to: &req)

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
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

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }

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
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }

        struct Row: Decodable { let poll_id: UUID }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return Set(rows.map(\.poll_id))
    }
    // MARK: - My content helpers
    // --- Voted polls helpers (IDs -> Polls) ---
    /// そのユーザーが投票した poll_id 一覧を取得（重複除外）
    static func fetchVotedPollIDs(userID: UUID, limit: Int = 200) async throws -> [UUID] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/votes"
        comps.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "poll_id"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct Row: Decodable { let poll_id: UUID }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        var set = Set<UUID>()
        var uniq: [UUID] = []
        for r in rows {
            if !set.contains(r.poll_id) { set.insert(r.poll_id); uniq.append(r.poll_id) }
        }
        return uniq
    }

    /// poll_id 群で Poll をまとめて取得（最新順）
    static func fetchPollsByIDs(_ ids: [UUID]) async throws -> [Poll] {
        if ids.isEmpty { return [] }
        let idList = ids.map { $0.uuidString.uppercased() }.joined(separator: ",")
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        comps.queryItems = [
            URLQueryItem(name: "id", value: "in.(\(idList))"),
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id,description"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "\(ids.count)"),
            URLQueryItem(name: "deleted_at", value: "is.null")
        ]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Poll].self, from: data)
    }

    /// ユーザーの「投票したPoll一覧」を一発で取得（ラッパー）
    static func fetchPollsVotedBy(userID: UUID) async throws -> [Poll] {
        let ids = try await fetchVotedPollIDs(userID: userID)
        return try await fetchPollsByIDs(ids)
    }
    /// 自分が作成した Poll 一覧を取得（最新順）
    static func fetchMyPosts(ownerID: UUID,
                             limit: Int = 50,
                             order: String = "created_at.desc") async throws -> [Poll] {
        guard let base = URL(string: AppConfig.supabaseURL) else { return [] }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/rest/v1/polls"
        comps.queryItems = [
            URLQueryItem(name: "owner_id", value: "eq.\(ownerID.uuidString.uppercased())"),
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id,description"),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "deleted_at", value: "is.null")
        ]

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

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
        addSupabaseHeaders(to: &reqIDs)

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
            URLQueryItem(name: "select", value: "id,question,category,created_at,owner_id,description"),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "deleted_at", value: "is.null")
        ]

        let url = comps.url!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addSupabaseHeaders(to: &req)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([Poll].self, from: data)
    }
}
