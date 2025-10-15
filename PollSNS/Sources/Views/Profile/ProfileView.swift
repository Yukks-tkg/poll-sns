import SwiftUI

struct ProfileView: View {
    @State private var selectedSegment = 0
    // ローカルの設定シート表示はやめ、グローバル通知で Root に表示させる
    @State private var profile: PollAPI.UserProfile?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isLoadingProfile = false
    @State private var hasAttemptedLoad = false

    // 追加: フェッチ完了後だけ自動遷移を判定するフラグ
    @State private var didFetchOnce = false
    // 追加: 画面が実際に表示中か（自動挙動は表示中のみ実行）
    @State private var isVisible = false
    // 追加: 初回セットアップの誘導を一度だけにするフラグ
    @State private var promptedSetupOnce = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            profileCard

            Picker("", selection: $selectedSegment) {
                Text("自分の投稿").tag(0)
                Text("自分の投票").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.bottom, 8)

            ZStack {
                MyPostsListView(ownerID: AppConfig.currentUserID)
                    .listStyle(.plain)
                    .opacity(selectedSegment == 0 ? 1 : 0)
                    .allowsHitTesting(selectedSegment == 0)
                    .zIndex(selectedSegment == 0 ? 1 : 0)

                MyVotesListView(userID: AppConfig.currentUserID)
                    .listStyle(.plain)
                    .opacity(selectedSegment == 1 ? 1 : 0)
                    .allowsHitTesting(selectedSegment == 1)
                    .zIndex(selectedSegment == 1 ? 1 : 0)
            }
            .animation(nil, value: selectedSegment)
            .id("ProfileListContainer")
        }
        .navigationTitle("プロフィール")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }) {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
        .task {
            if !hasAttemptedLoad { await loadProfile() }
        }
        // 復帰時の自動リロードは RootTabView 側に寄せるため削除
        // .onChange(of: scenePhase) { newPhase in
        //     if newPhase == .active, isVisible {
        //         Task { await loadProfile() }
        //     }
        // }
        .onChange(of: didFetchOnce) { _ in
            if isVisible { presentEditIfNeeded() }
        }
        .onAppear {
            isVisible = true
            if didFetchOnce { presentEditIfNeeded() }
        }
        .onDisappear {
            isVisible = false
        }
        // ユーザーID変更通知で再読み込み（メインスレッドで受信）
        .onReceive(NotificationCenter.default.publisher(for: AppConfig.userIDDidChange).receive(on: RunLoop.main)) { _ in
            Task { await resetAndReloadForUserChange() }
        }
        // プロフィール更新通知で強制リロード（編集経路を問わず反映）
        .onReceive(NotificationCenter.default.publisher(for: .profileDidUpdate).receive(on: RunLoop.main)) { note in
            let uidAny = note.userInfo?[AppNotificationKey.userID]
            let uidMatches: Bool = {
                if let u = uidAny as? UUID { return u == AppConfig.currentUserID }
                if let s = uidAny as? String, let u = UUID(uuidString: s) { return u == AppConfig.currentUserID }
                return true
            }()
            guard uidMatches else { return }
            Task { await forceReloadAfterProfileUpdate() }
        }
    }

    // 初回ロード中だけ全面スピナー。2回目以降は内容を維持してオーバーレイでスピナーを重ねる。
    var profileCard: some View {
        // 初回の全画面ローディングかどうか
        let isInitialLoading = isLoading && !hasAttemptedLoad && profile == nil

        return Group {
            if isInitialLoading {
                // 初回だけ置き換え（高さは固定）
                ProgressView().frame(maxWidth: .infinity, minHeight: 140)
            } else if let message = errorMessage, profile == nil {
                // データが無くてエラーのときだけエラーカード
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("読み込みに失敗しました")
                        .font(.subheadline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await loadProfile() }
                    } label: {
                        Label("再読み込み", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                // 通常表示（プロフィールあり or 未設定のプレースホルダ）
                ZStack {
                    VStack {
                        Text((profile?.avatar_value).map { String($0) } ?? "🙂")
                            .font(.system(size: 64))
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        Text(profile?.username ?? "未設定")
                            .font(.title2)
                            .fontWeight(.bold)
                        if let _ = profile {
                            Text(profileDetailString())
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .padding(.bottom, 12)
                        } else {
                            Text("プロフィールが未設定です")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 12)
                            Button {
                                NotificationCenter.default.post(name: .showSettings, object: nil)
                            } label: {
                                Label("プロフィールを設定", systemImage: "gearshape")
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)

                    // 2回目以降のリフレッシュ時はオーバーレイでスピナーを重ねる（内容は維持）
                    if isLoadingProfile && (hasAttemptedLoad || profile != nil) {
                        ZStack {
                            Color.black.opacity(0.05)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            ProgressView()
                                .tint(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 140)
                        .allowsHitTesting(false)
                        // アニメーションを無効化（復帰時のガタつき低減）
                        .animation(.none, value: isLoadingProfile)
                        .transition(.identity)
                    }
                }
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding()
    }

    private func profileDetailString() -> String {
        guard let profile = profile else { return "" }
        var details: [String] = []

        if let g = profile.gender, !g.isEmpty {
            details.append(genderLabel(for: g))
        }

        if let age = profile.age {
            details.append("\(age)歳")
        }

        if let r = profile.region, !r.isEmpty {
            details.append(r)
        }

        return details.joined(separator: "／")
    }

    private func genderLabel(for code: String) -> String {
        switch code {
        case "male": return "男性"
        case "female": return "女性"
        case "other": return "その他"
        case "prefer_not_to_say": return "回答しない"
        default:
            return code
        }
    }

    private func loadProfile() async {
        if isLoadingProfile { print("PROFILE: already loading, skip"); return }
        await MainActor.run {
            // 初回だけ全面置き換えのローディングにする
            isLoading = (profile == nil && !hasAttemptedLoad)
            // 2回目以降はオーバーレイ表示のためのフラグ
            isLoadingProfile = true
            errorMessage = nil
        }
        defer {
            Task { await MainActor.run { isLoading = false; isLoadingProfile = false } }
        }
        do {
            print("PROFILE: fetch start for user=\(AppConfig.currentUserID.uuidString)")
            let result = try await PollAPI.fetchProfile(userID: AppConfig.currentUserID)
            await MainActor.run {
                self.profile = result
                self.errorMessage = nil
                self.hasAttemptedLoad = true
                self.didFetchOnce = true
            }
            if let p = result {
                print("PROFILE: fetch ok username=\(p.username) age=\(p.age?.description ?? "nil")")
            } else {
                print("PROFILE: fetch ok but no profile row for user")
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.hasAttemptedLoad = true
                self.didFetchOnce = true
            }
            print("PROFILE: fetch error => \(error)")
        }
    }

    private func presentEditIfNeeded() {
        guard didFetchOnce else { return }
        guard isVisible else { return }
        guard !promptedSetupOnce else { return }

        if let p = profile {
            let needsSetup = p.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if needsSetup {
                promptedSetupOnce = true
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
        }
    }

    private func resetAndReloadForUserChange() async {
        await MainActor.run {
            self.profile = nil
            self.errorMessage = nil
            self.isLoading = false
            self.isLoadingProfile = false
            self.hasAttemptedLoad = false
            self.didFetchOnce = false
            self.promptedSetupOnce = false
        }
        await loadProfile()
    }

    // プロフィール更新（保存完了）通知を受けたときの強制リロード
    private func forceReloadAfterProfileUpdate() async {
        await MainActor.run {
            self.profile = nil
            self.errorMessage = nil
            self.isLoading = false
            self.isLoadingProfile = false
            self.hasAttemptedLoad = false
            self.didFetchOnce = false
            self.promptedSetupOnce = false
        }
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        await loadProfile()
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
