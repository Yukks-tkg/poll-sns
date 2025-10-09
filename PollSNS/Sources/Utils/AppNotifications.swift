import Foundation

extension Notification.Name {

    static let pollDidVote = Notification.Name("pollDidVote")
}

enum AppNotificationKey {
    static let pollID = "pollID"
    static let optionID = "optionID"
    static let userID = "userID"
}
