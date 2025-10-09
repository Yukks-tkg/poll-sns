import Foundation

struct VoteResult: Codable, Identifiable {
    let option_id: UUID
    let count: Int

    var id: UUID { option_id }
}
