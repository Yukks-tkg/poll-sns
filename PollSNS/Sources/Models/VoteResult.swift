//
//  VoteResult.swift
//  PollSNS
//
//  Created by 高木祐輝 on 2025/09/20.
//



import Foundation

struct VoteResult: Codable, Identifiable {
    let option_id: UUID
    let count: Int

    var id: UUID { option_id }
}
