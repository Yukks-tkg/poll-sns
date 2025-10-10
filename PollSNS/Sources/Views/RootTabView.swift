import SwiftUI

extension Notification.Name {
    static let pollCreated = Notification.Name("pollCreated")
}

private enum Tab: Int { case timeline = 0, create, profile }

struct RootTabView: View {
    @State private var selected: Tab = .timeline
    // 初回プロフィール強制表示フラグ
    @State private var mustSetupProfile: Bool = false
    @State private var isCheckingProfile = false

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
        // 起動時・表示時にプロフィール有無をチェック
        .task {
            await checkProfileIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await checkProfileIfNeeded() }
        }
        // 未設定ならフルスクリーンで編集を強制表示
        .fullScreenCover(isPresented: $mustSetupProfile) {
            NavigationStack {
                ProfileEditView(userID: AppConfig.currentUserID, initialProfile: nil) {
                    // 保存完了時に再チェック（成功していれば閉じる）
                    Task { await checkProfileIfNeeded(force: true) }
                }
            }
            .interactiveDismissDisabled(true) // スワイプで閉じられないように
        }
    }

    @MainActor
    private func setMustSetup(_ value: Bool) {
        mustSetupProfile = value
    }

    private func checkProfileIfNeeded(force: Bool = false) async {
        if isCheckingProfile { return }
        isCheckingProfile = true
        defer { isCheckingProfile = false }
        do {
            // サーバーにプロフィールが無ければ未設定扱い
            let profile = try await PollAPI.fetchProfile(userID: AppConfig.currentUserID)
            await MainActor.run {
                // プロフィール行が存在し、username が空でないなら設定済みとみなす
                let isConfigured: Bool = {
                    guard let p = profile else { return false }
                    return !p.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }()
                setMustSetup(!isConfigured)
            }
        } catch {
            // 通信失敗時は安全側でモーダルを出す（ユーザーが保存すれば upsert で作成される）
            await MainActor.run { setMustSetup(true) }
        }
    }
}
