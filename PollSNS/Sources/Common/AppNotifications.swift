import Foundation

// アプリ内で用いる Notification 名と userInfo キーの集約
extension Notification.Name {
    /// プロフィールが作成/更新された際に発火される通知
    /// userInfo:
    ///  - AppNotificationKey.userID: UUID
    static let profileDidUpdate = Notification.Name("profileDidUpdate")

    /// 投票完了時に発火される通知
    /// userInfo:
    ///  - AppNotificationKey.pollID: UUID
    ///  - AppNotificationKey.optionID: UUID
    ///  - AppNotificationKey.userID: UUID
    static let pollDidVote = Notification.Name("pollDidVote")
}

// NotificationCenter.userInfo で用いるキーの集約
enum AppNotificationKey {
    static let userID = "userID"
    static let pollID = "pollID"
    static let optionID = "optionID"
}
