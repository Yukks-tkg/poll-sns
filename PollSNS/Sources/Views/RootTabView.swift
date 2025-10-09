import SwiftUI

extension Notification.Name {
    static let pollCreated = Notification.Name("pollCreated")
}

private enum Tab: Int { case timeline = 0, create, profile }

struct RootTabView: View {
    @State private var selected: Tab = .timeline

    var body: some View {
        TabView(selection: $selected) {

            NavigationStack {
                PollTimelineView()
            }
            .tabItem {
                Label("タイムライン", systemImage: "list.bullet")
            }
            .tag(Tab.timeline)

            NavigationStack {
                NewPollView { _ in
                    selected = .timeline
                    NotificationCenter.default.post(name: .pollCreated, object: nil)
                }
            }
            .tabItem {
                Label("作成", systemImage: "plus.circle")
            }
            .tag(Tab.create)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("プロフィール", systemImage: "person.crop.circle")
            }
            .tag(Tab.profile)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTimeline)) { _ in
            selected = .timeline
        }
    }
}
