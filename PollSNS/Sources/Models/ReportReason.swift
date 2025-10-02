import Foundation

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
