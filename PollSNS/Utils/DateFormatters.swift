import Foundation

enum DateFormatters {
    static let absolute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.unitsStyle = .full
        return f
    }()
}

extension Date {
    var relativeDescription: String {
        DateFormatters.relative.localizedString(for: self, relativeTo: Date())
    }
    var absoluteDescription: String {
        DateFormatters.absolute.string(from: self)
    }
}
