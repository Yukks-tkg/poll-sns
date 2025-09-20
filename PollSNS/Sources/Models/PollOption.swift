// Sources/Models/PollOption.swift
import Foundation

/// 投票の選択肢
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
