import Foundation

struct Poll: Identifiable, Decodable {
    let id: UUID
    let question: String
    let category: String
    let owner_id: UUID?
    let created_at: String?
    let like_count: Int?
    // 新規: 任意の説明
    let description: String?
}

extension Poll {
    var createdAtFormatted: String? {
        guard let createdAtString = created_at else { return nil }
        let isoFormatterWithFractional = ISO8601DateFormatter()
        isoFormatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatter = ISO8601DateFormatter()
        var date: Date? = isoFormatterWithFractional.date(from: createdAtString)
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

