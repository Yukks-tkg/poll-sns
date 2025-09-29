//
//  ProfileView.swift
//  PollSNS
//
//  Created by 高木祐輝 on 2025/09/26.
//

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
        // NOTE: Large titleが確実に出るよう、最上位は ScrollView ではなく
        // VStack + 下層の List をスクロールコンテナにします。
        VStack(spacing: 0) {
            // ヘッダー（固定表示）
            profileCard
                .frame(height: 200)

            // セグメント
            Picker("", selection: $selectedSegment) {
                Text("自分の投稿").tag(0)
                Text("自分の投票").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.bottom, 8)

            // コンテンツ（各自がスクロールコンテナ）
            if selectedSegment == 0 {
                // 自分の投稿一覧（List が自身でスクロールを管理）
                MyPostsListView(ownerID: AppConfig.devUserID)
                    .listStyle(.plain)
            } else {
                // 自分の投票一覧（List が自身でスクロールを管理）
                MyVotesListView(userID: AppConfig.devUserID)
                    .listStyle(.plain)
            }
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
                        .padding(.bottom, 8)
                    Text(profile?.username ?? "未設定")
                        .font(.title2)
                        .fontWeight(.bold)
                    if let _ = profile {
                        Text(profileDetailString())
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text("プロフィールが未設定です")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
        if let age = profile.age {
            details.append("\(age)歳")
        }
        if let prefCode = profile.prefecture_code, !prefCode.isEmpty {
            details.append(prefectureName(for: prefCode))
        }
        if let occ = profile.occupation, !occ.isEmpty {
            details.append(occupationLabel(for: occ))
        }
        return details.joined(separator: "・")
    }

    private func prefectureName(for raw: String) -> String {
        // Map with zero-padded keys (01..47)
        let prefectures: [String: String] = [
            "01": "北海道", "02": "青森県", "03": "岩手県", "04": "宮城県", "05": "秋田県",
            "06": "山形県", "07": "福島県", "08": "茨城県", "09": "栃木県", "10": "群馬県",
            "11": "埼玉県", "12": "千葉県", "13": "東京都", "14": "神奈川県", "15": "新潟県",
            "16": "富山県", "17": "石川県", "18": "福井県", "19": "山梨県", "20": "長野県",
            "21": "岐阜県", "22": "静岡県", "23": "愛知県", "24": "三重県", "25": "滋賀県",
            "26": "京都府", "27": "大阪府", "28": "兵庫県", "29": "奈良県", "30": "和歌山県",
            "31": "鳥取県", "32": "島根県", "33": "岡山県", "34": "広島県", "35": "山口県",
            "36": "徳島県", "37": "香川県", "38": "愛媛県", "39": "高知県", "40": "福岡県",
            "41": "佐賀県", "42": "長崎県", "43": "熊本県", "44": "大分県", "45": "宮崎県",
            "46": "鹿児島県", "47": "沖縄県"
        ]

        // If the DB already stores a full prefecture name (e.g. "東京都"), use it as-is
        if prefectures.values.contains(raw) || raw.hasSuffix("都") || raw.hasSuffix("道") || raw.hasSuffix("府") || raw.hasSuffix("県") {
            return raw
        }

        // Accept either "01".."47" or "1".."47"
        if let n = Int(raw), (1...47).contains(n) {
            let key = String(format: "%02d", n)
            return prefectures[key] ?? "未設定"
        }
        return prefectures[raw] ?? "未設定"
    }

    private func occupationLabel(for code: String) -> String {
        switch code {
        case "student": return "学生"
        case "employee_fulltime": return "会社員"
        case "employee_contract": return "契約社員"
        case "part_time": return "パート・アルバイト"
        case "freelancer", "self_employed": return "個人事業"
        case "public_servant": return "公務員"
        case "homemaker": return "専業主婦/主夫"
        case "unemployed": return "無職"
        case "other": return "その他"
        case "prefer_not_to_say": return "回答しない"
        default: return code
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
            print("PROFILE: fetch start for user=\(AppConfig.devUserID.uuidString)")
            let result = try await PollAPI.fetchProfile(userID: AppConfig.devUserID)
            await MainActor.run {
                self.profile = result
                self.errorMessage = nil
                self.hasAttemptedLoad = true
            }
            if let p = result {
                print("PROFILE: fetch ok username=\(p.username) age=\(p.age?.description ?? "nil") pref=\(p.prefecture_code ?? "nil") occ=\(p.occupation ?? "nil")")
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
