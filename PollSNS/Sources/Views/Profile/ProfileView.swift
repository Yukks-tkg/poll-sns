import SwiftUI

struct ProfileView: View {
    @State private var selectedSegment = 0
    @State private var isSettingsPresented = false
    @State private var profile: PollAPI.UserProfile?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isLoadingProfile = false
    @State private var hasAttemptedLoad = false

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
        // --- NavigationBar ---
        .navigationTitle("プロフィール")
        .navigationBarTitleDisplayMode(.large)
        // iOS17 以降で largeTitle が消えるのを避けるため automatic に戻す
        .toolbarBackground(.automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isSettingsPresented = true }) {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet(
                onClose: { isSettingsPresented = false },
                onProfileEdited: { Task { await loadProfile() } }
            )
        }
        .task {
            if !hasAttemptedLoad { await loadProfile() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await loadProfile() }
        }
    }

    var profileCard: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 140)
            } else if let message = errorMessage {
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
                            isSettingsPresented = true
                        } label: {
                            Label("プロフィールを設定", systemImage: "gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 140)
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

        return details.joined(separator: "・")
    }

    private func genderLabel(for code: String) -> String {
        switch code {
        case "male": return "男性"
        case "female": return "女性"
        case "other": return "その他"
        case "prefer_not_to_say": return "回答しない"
        default:
            // 既に日本語が入っている / 将来拡張のためフォールバック
            return code
        }
    }

    private func loadProfile() async {
        if isLoadingProfile { print("PROFILE: already loading, skip"); return }
        await MainActor.run {
            isLoading = true
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
            }
            print("PROFILE: fetch error => \(error)")
        }
    }
}


struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
