// Sources/Common/AppNotifications.swift（新規推奨）
import Foundation

extension Notification.Name {
    static let pollDidSoftDelete = Notification.Name("pollDidSoftDelete")
}

enum AppNotificationKey {
    static let pollID = "pollID"
    static let optionID = "optionID"
    static let userID = "userID"
}
