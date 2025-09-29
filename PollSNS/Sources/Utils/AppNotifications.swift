import Foundation

extension Notification.Name {
    /// 投票が完了したとき（詳細画面→一覧に知らせる）
    static let pollDidVote = Notification.Name("pollDidVote")
}

/// 通知に載せるユーザ情報のキー
enum AppNotificationKey {
    static let pollID = "pollID"         // UUID
    static let optionID = "optionID"     // UUID
    static let userID = "userID"         // UUID
}
