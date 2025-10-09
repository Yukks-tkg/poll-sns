import Foundation

struct PollOption: Identifiable, Decodable, Hashable {
    let id: UUID
    let poll_id: UUID
    let idx: Int?
    let label: String
    let image_url: String?

    var displayText: String {
        label
    }
}
