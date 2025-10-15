import SwiftUI

extension Notification.Name {
    static let pollCreated = Notification.Name("pollCreated")
    // どの画面からでも「設定シートを開く」ための通知
    static let showSettings = Notification.Name("showSettings")
}

private enum Tab: Int { case timeline = 0, create, profile }

struct RootTabView: View {
    @State private var selected: Tab = .timeline
    // 初回プロフィール強制表示フラグ
    @State private var mustSetupProfile: Bool = false
    @State private var isCheckingProfile = false
    @State private var signingOut = false
    @State private var showSignedOutToast = false

    // グローバル設定シートの表示フラグ
    @State private var showSettings: Bool = false

    var body: some View {
        ZStack {
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
                                .disabled(signingOut)
                            }
                        }
                }
                .tabItem {
                    Label("プロフィール", systemImage: "person.crop.circle")
                }
                .tag(Tab.profile)
            }

            // サインアウト中はブラー系マテリアルで全画面オーバーレイ
            if signingOut {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    ProgressView()
                    Text("サインアウト中…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 8)
                .transition(.opacity)
            }

            // サインアウト完了トースト
            if showSignedOutToast {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("サインアウトしました")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 6)
                    .padding(.top, 12)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.2), value: showSignedOutToast)
                .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTimeline)) { _ in
            selected = .timeline
        }
        // グローバルに設定シートを提示
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
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
                ProfileEditView(userID: AppConfig.currentUserID, initialProfile: nil) { _ in
                    // 保存完了時に再チェック（成功していれば閉じる）
                    Task { await checkProfileIfNeeded() }
                }
            }
            .interactiveDismissDisabled(true) // スワイプで閉じられないように
        }
        // 設定シート（どのタブ上でも同じ UI で表示）
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                onClose: { showSettings = false },
                onProfileEdited: { _ in
                    // 保存後に必要なら再チェック
                    Task { await checkProfileIfNeeded() }
                }
            )
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
        // 1) 先にオーバーレイを被せてから、アニメーション無しでタイムラインへ切替
        await MainActor.run {
            signingOut = true
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                selected = .timeline
            }
            NotificationCenter.default.post(name: .switchToTimeline, object: nil)
        }

        // 2) Supabaseセッションを無効化
        await SupabaseManager.shared.signOut()

        // 3) ローカルの user.id を削除
        AppConfig.resetCurrentUserID()

        // 4) 匿名サインインやり直し → user.id を保存
        guard let uid = await SupabaseManager.shared.ensureSignedInAndCacheUserID() else {
            // 匿名ログイン失敗時は安全側でプロフィール編集を促す
            await MainActor.run {
                setMustSetup(true)
                // オーバーレイ終了 + 失敗トースト（文言変更したければここで）
                signingOut = false
                showToastTemporarily()
            }
            return
        }

        // 5) プロフィール行を自動作成（無ければ）
        try? await PollAPI.ensureProfileExists(userID: uid)

        // 6) プロフィール状態を再チェック
        await checkProfileIfNeeded()

        // 7) オーバーレイを外し、完了トースト表示
        await MainActor.run {
            signingOut = false
            showToastTemporarily()
        }
    }

    @MainActor
    private func showToastTemporarily() {
        withAnimation { showSignedOutToast = true }
        // 1.2秒後に自動で消す
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation { showSignedOutToast = false }
        }
    }
}

