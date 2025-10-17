import SwiftUI

enum Gender: String, CaseIterable, Identifiable {
    case male, female, other, no_answer
    var id: String { rawValue }
    var display: String {
        switch self {
        case .male: return "男性"
        case .female: return "女性"
        case .other: return "その他"
        case .no_answer: return "無回答"
        }
    }
}

private extension String {
    var containsEmoji: Bool {
        return unicodeScalars.contains { $0.properties.isEmoji && ($0.value > 0x238C) }
    }
}

struct ProfileValidation {
    static let nicknameMin = 2
    static let nicknameMax = 20
    static func validateNickname(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "ニックネームを入力してください" }
        if trimmed.containsEmoji { return "ニックネームに絵文字は使えません" }
        if trimmed.count < nicknameMin { return "ニックネームは最低\(nicknameMin)文字です" }
        if trimmed.count > nicknameMax { return "ニックネームは最大\(nicknameMax)文字です" }
        return nil
    }
}

struct ProfileEditView: View {
    let userID: UUID
    let initialProfile: PollAPI.UserProfile?
    var onSaved: ((PollAPI.UserProfile) -> Void)? = nil

    @State private var selectedAvatar: String = "👶"
    @State private var nickname: String = ""
    @State private var gender: Gender? = nil
    @State private var age: Int? = nil
    @State private var region: String? = nil
    @State private var ageGroup: String? = nil   // 追加: 年代（"10代" 等）

    @State private var didPreload = false

    // 初回セットアップ時だけ一度表示するモーダル制御
    @State private var showIntroModal = false
    @State private var didShowIntro = false

    @Environment(\.dismiss) private var dismiss

    private let avatarCandidates: [String] = [
        "🐶","🐱","🐼","🦊","🐻","🦁","🐵","🐧","🐸","🦄",
        "🍔","🍣","🍕","🍎","🍩","🍜","🍫","☕️",
        "👶","👧","🧒"
    ]

    // 「無回答」を追加（未設定は Picker の "未設定" で表現）
    private let regions = [
        "北海道", "東北", "関東", "中部", "近畿",
        "中国", "四国", "九州・沖縄", "海外", "無回答"
    ]

    // 年代の選択肢（無回答含む）
    private let ageGroups = [
        "10代", "20代", "30代", "40代", "50代以上", "無回答"
    ]

    private var nicknameError: String? {
        ProfileValidation.validateNickname(nickname)
    }

    private var canSave: Bool {
        nicknameError == nil
        && gender != nil
        && age != nil
        && region != nil
        && ageGroup != nil
        && (age ?? 0) >= 13
        && (age ?? 0) <= 99
    }

    private var isInitialSetup: Bool {
        return initialProfile == nil
    }

    var body: some View {
        Form {
            Section(header: Text("アイコン")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("選択中: \(selectedAvatar)")
                        .font(.title)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 32, maximum: 60), spacing: 8), count: 6), spacing: 8) {
                        ForEach(avatarCandidates, id: \.self) { emoji in
                            Button {
                                selectedAvatar = emoji
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedAvatar == emoji ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selectedAvatar == emoji ? 2 : 1)
                                        .frame(height: 44)
                                    Text(emoji).font(.title2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section(header: Text("ニックネーム"), footer: nicknameFooter) {
                TextField("2〜20文字（本名・絵文字は不可）", text: $nickname)
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled(true)
            }

            Section(header: Text("性別"), footer: genderFooter) {
                Picker("性別", selection: $gender) {
                    Text("未設定").tag(Gender?.none)
                    ForEach(Gender.allCases) { g in
                        Text(g.display).tag(Gender?.some(g))
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text("年齢"), footer: ageFooter) {
                Picker("年齢", selection: Binding(
                    get: { age ?? -1 },
                    set: { newValue in age = (newValue == -1 ? nil : newValue) }
                )) {
                    Text("未設定").tag(-1)
                    ForEach(13...99, id: \.self) { v in
                        Text("\(v)歳").tag(v)
                    }
                }
            }

            Section(header: Text("地域"), footer: regionFooter) {
                Picker("地域", selection: Binding(
                    get: { region ?? "" },
                    set: { region = $0.isEmpty ? nil : $0 }
                )) {
                    Text("未設定").tag("")
                    ForEach(regions, id: \.self) { r in
                        Text(r).tag(r)
                    }
                }
            }

            // 追加: 年代（地域と同じ構成）
            Section(header: Text("年代"), footer: ageGroupFooter) {
                Picker("年代", selection: Binding(
                    get: { ageGroup ?? "" },
                    set: { ageGroup = $0.isEmpty ? nil : $0 }
                )) {
                    Text("未設定").tag("")
                    ForEach(ageGroups, id: \.self) { g in
                        Text(g).tag(g)
                    }
                }
            }
        }
        .navigationTitle("プロフィール編集")
        .navigationBarBackButtonHidden(isInitialSetup)
        .toolbar {
            if !isInitialSetup {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(!canSave)
            }
        }
        .task {
            if !didPreload {
                await preload()
                didPreload = true
            }
            // 初回セットアップ時のみ、一度だけモーダルを表示
            if isInitialSetup && !didShowIntro {
                showIntroModal = true
                didShowIntro = true
            }
        }
        .sheet(isPresented: $showIntroModal) {
            VStack(spacing: 16) {
                Text("プロフィール設定のお願い")
                    .font(.title2).bold()
                VStack(alignment: .leading, spacing: 8) {
                    Text("アンケート結果の正確性を高めるため、プロフィールの内容はできるだけ正確にご入力ください。")
                    Text("・ニックネーム（本名・絵文字不可）")
                    Text("・性別")
                    Text("・年齢（13〜99歳）")
                    Text("・地域")
                    Text("・年代")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.secondary)

                Spacer(minLength: 8)

                Button {
                    showIntroModal = false
                } label: {
                    Text("はじめる")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .presentationDetents([.fraction(0.45), .medium])
            .interactiveDismissDisabled(true)
        }
    }

    @ViewBuilder
    private var nicknameFooter: some View {
        let length = nickname.count
        HStack {
            if let err = nicknameError { Text(err).foregroundColor(.red) }
            Spacer()
            Text("\(length)/\(ProfileValidation.nicknameMax)")
                .foregroundColor(length > ProfileValidation.nicknameMax ? .red : .secondary)
        }
        .font(.footnote)
    }

    @ViewBuilder
    private var genderFooter: some View {
        if gender == nil {
            Text("性別を選択してください").foregroundColor(.red).font(.footnote)
        }
    }

    @ViewBuilder
    private var ageFooter: some View {
        if age == nil {
            Text("年齢を選択してください").foregroundColor(.red).font(.footnote)
        }
    }

    @ViewBuilder
    private var regionFooter: some View {
        if region == nil {
            Text("地域を選択してください").foregroundColor(.red).font(.footnote)
        }
    }

    @ViewBuilder
    private var ageGroupFooter: some View {
        if ageGroup == nil {
            Text("年代を選択してください").foregroundColor(.red).font(.footnote)
        }
    }

    private func save() {
        guard let g = gender, let a = age, let r = region, let ag = ageGroup else { return }
        let input = PollAPI.ProfileInput(
            display_name: nickname,
            gender: g.rawValue,
            age: a,
            icon_emoji: selectedAvatar,
            region: r,
            age_group: ag
        )
        Task {
            do {
                let saved = try await PollAPI.upsertProfile(userID: userID, input: input)
                // 追加: プロフィール更新の通知を送る（ProfileView が自動更新できるように）
                NotificationCenter.default.post(
                    name: .profileDidUpdate,
                    object: nil,
                    userInfo: [AppNotificationKey.userID: userID]
                )
                // UI 更新はメインスレッドで
                await MainActor.run {
                    onSaved?(saved)
                    dismiss()
                }
            } catch {
                print("Failed to save profile:", error)
            }
        }
    }

    private func preload() async {
        if let p = initialProfile {
            await MainActor.run { apply(profile: p) }
            return
        }

        do {
            if let p = try await PollAPI.fetchProfile(userID: userID) {
                await MainActor.run { apply(profile: p) }
            } else {
                // 既存プロフィールが無い場合は、必須項目は未設定(nil)のまま
            }
        } catch {
            print("EDIT preload error:", error)
        }
    }

    private func apply(profile p: PollAPI.UserProfile) {
        if let emoji = p.avatar_value, !emoji.isEmpty { selectedAvatar = emoji }
        nickname = p.username
        if let a = p.age { age = a } else { age = nil }
        if let g = p.gender, let choice = Gender(rawValue: g) { gender = choice } else { gender = nil }
        if let r = p.region, !r.isEmpty { region = r } else { region = nil }
        if let ag = p.age_group, !ag.isEmpty { ageGroup = ag } else { ageGroup = nil }
    }
}

#Preview {
    NavigationStack {
        ProfileEditView(userID: UUID(), initialProfile: nil)
    }
}
