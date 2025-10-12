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
    @State private var signingOut = false

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
                    .toolbar {
                        // 開発用：サインアウト
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                Task { await signOutAndReauth() }
                            } label: {
                                if signingOut {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                }
                            }
                            .accessibilityLabel("サインアウト（開発用）")
                        }
                    }
            }
            .tabItem {
                Label("プロフィール", systemImage: "person.crop.circle")
            }
            .tag(Tab.profile)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTimeline)) { _ in
            selected = .timeline
        }
        // 起動時：まず匿名サインイン（未ログイン時のみ）→ その後プロフィール有無チェック
        .task {
            if let uid = await SupabaseManager.shared.ensureSignedInAndCacheUserID() {
                // ログインできたら profiles に行を自動作成（無ければ）
                try? await PollAPI.ensureProfileExists(userID: uid)
            }
            await checkProfileIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                if let uid = await SupabaseManager.shared.ensureSignedInAndCacheUserID() {
                    // 復帰時も安全側で自動作成（初回やセッション切れ時に有効）
                    try? await PollAPI.ensureProfileExists(userID: uid)
                }
                await checkProfileIfNeeded()
            }
        }
        // 未設定ならフルスクリーンで編集を強制表示
        .fullScreenCover(isPresented: $mustSetupProfile) {
            NavigationStack {
                ProfileEditView(userID: AppConfig.currentUserID, initialProfile: nil) {
                    // 保存完了時に再チェック（成功していれば閉じる）
                    Task { await checkProfileIfNeeded() }
                }
            }
            .interactiveDismissDisabled(true) // スワイプで閉じられないように
        }
    }

    @MainActor
    private func setMustSetup(_ value: Bool) {
        mustSetupProfile = value
    }

    private func checkProfileIfNeeded() async {
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

    // MARK: - Sign-out flow (開発用)
    private func signOutAndReauth() async {
        await MainActor.run { signingOut = true }
        defer { Task { await MainActor.run { signingOut = false } } }

        // 1) Supabaseセッションを無効化
        await SupabaseManager.shared.signOut()

        // 2) ローカルの user.id を削除
        AppConfig.resetCurrentUserID()

        // 3) 匿名サインインやり直し → user.id を保存
        guard let uid = await SupabaseManager.shared.ensureSignedInAndCacheUserID() else {
            // 匿名ログイン失敗時は安全側でプロフィール編集を促す
            await MainActor.run { setMustSetup(true) }
            return
        }

        // 4) プロフィール行を自動作成（無ければ）
        try? await PollAPI.ensureProfileExists(userID: uid)

        // 5) プロフィール状態を再チェック
        await checkProfileIfNeeded()

        // 6) タイムラインなどの表示を最新化（タブをタイムラインに戻す等は任意）
        await MainActor.run {
            selected = .timeline
            NotificationCenter.default.post(name: .switchToTimeline, object: nil)
        }
    }
}
