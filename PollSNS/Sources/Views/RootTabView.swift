import SwiftUI

// 作成完了の通知（タイムライン側でリロードに使う）
extension Notification.Name {
    static let pollCreated = Notification.Name("pollCreated")
}

struct RootTabView: View {
    @State private var selected = 0   // 0: タイムライン, 1: 作成

    var body: some View {
        TabView(selection: $selected) {

            // タブ1：タイムライン
            NavigationStack {
                PollTimelineView()
            }
            .tabItem {
                Label("タイムライン", systemImage: "list.bullet")
            }
            .tag(0)

            // タブ2：作成
            NavigationStack {
                NewPollView { _ in
                    // 作成完了 → タイムラインへ切り替え → 再読込通知
                    selected = 0
                    NotificationCenter.default.post(name: .pollCreated, object: nil)
                }
            }
            .tabItem {
                Label("作成", systemImage: "plus.circle")
            }
            .tag(1)
        }
    }
}
