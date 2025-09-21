import Foundation

struct Poll: Identifiable, Decodable {
    let id: UUID           // ← Supabaseの polls.id が UUID ならこれでOK（文字列なら String にする）
    let question: String
    let category: String
    let owner_id: UUID?    // ← 追加：投稿者（存在しないレコードもある想定で Optional）
    let created_at: String?  // とりあえず文字列で受ける（後でDateにする）
    let like_count: Int?     // 人気順ビュー（polls_popular）でのみ返る想定

    // DB列名が同じなら CodingKeys は不要
}

extension Poll {
    var createdAtFormatted: String? {
        guard let createdAtString = created_at else { return nil }
        // Try parsing with fractional seconds first
        let isoFormatterWithFractional = ISO8601DateFormatter()
        isoFormatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatter = ISO8601DateFormatter()
        // Try with fractional seconds
        var date: Date? = isoFormatterWithFractional.date(from: createdAtString)
        // Fallback to regular ISO8601
        if date == nil {
            date = isoFormatter.date(from: createdAtString)
        }
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
