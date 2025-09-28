import SwiftUI

// MARK: - Models

enum Gender: String, CaseIterable, Identifiable {
    case male = "男性"
    case female = "女性"
    case other = "その他"
    var id: String { rawValue }
}

enum Occupation: String, CaseIterable, Identifiable {
    case student = "学生"
    case companyEmployee = "会社員"
    case selfEmployedFreelance = "個人事業・フリーランス"
    case partTime = "パート・アルバイト"
    case homemaker = "専業主婦／主夫"
    case unemployed = "無職"
    case other = "その他"
    var id: String { rawValue }
}

/// 都道府県（未選択・海外を含む）
enum Prefecture: String, CaseIterable, Identifiable {
    case unset = "未選択"
    case 北海道, 青森県, 岩手県, 宮城県, 秋田県, 山形県, 福島県
    case 茨城県, 栃木県, 群馬県, 埼玉県, 千葉県, 東京都, 神奈川県
    case 新潟県, 富山県, 石川県, 福井県, 山梨県, 長野県
    case 岐阜県, 静岡県, 愛知県, 三重県
    case 滋賀県, 京都府, 大阪府, 兵庫県, 奈良県, 和歌山県
    case 鳥取県, 島根県, 岡山県, 広島県, 山口県
    case 徳島県, 香川県, 愛媛県, 高知県
    case 福岡県, 佐賀県, 長崎県, 熊本県, 大分県, 宮崎県, 鹿児島県
    case 沖縄県
    case overseas = "海外"
    var id: String { rawValue }
}

// MARK: - Helpers

private extension String {
    /// 絵文字を含むかどうか（簡易判定）
    var containsEmoji: Bool {
        return unicodeScalars.contains { $0.properties.isEmoji && ($0.value > 0x238C) }
    }
}

/// バリデーション設定
struct ProfileValidation {
    static let nicknameMin = 1
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

// MARK: - Occupation (UI display ↔ code)
struct OccupationItem { let code: String; let label: String }
private let occupationItems: [OccupationItem] = [
    .init(code: "student",            label: "学生"),
    .init(code: "employee_fulltime",  label: "会社員（正社員）"),
    .init(code: "employee_contract",  label: "会社員（契約・派遣）"),
    .init(code: "part_time",          label: "パート・アルバイト"),
    .init(code: "freelancer",         label: "フリーランス"),
    .init(code: "self_employed",      label: "自営業"),
    .init(code: "public_servant",     label: "公務員"),
    .init(code: "homemaker",          label: "専業主婦／主夫"),
    .init(code: "unemployed",         label: "無職"),
    .init(code: "other",              label: "その他"),
    .init(code: "prefer_not_to_say",  label: "回答しない")
]

// MARK: - View

struct ProfileEditView: View {
    let userID: UUID
    let initialProfile: PollAPI.UserProfile?
    var onSaved: (() -> Void)? = nil

    // 入力状態
    @State private var selectedAvatar: String = "👶"
    @State private var nickname: String = ""
    @State private var gender: Gender = .other
    @State private var age: Int = 20
    @State private var prefecture: Prefecture = .unset
    @State private var occupationCode: String? = nil
    @State private var didPreload = false

    // 画面制御
    @Environment(\.dismiss) private var dismiss

    private let avatarCandidates: [String] = [
        // Animals
        "🐶","🐱","🐼","🦊","🐻","🦁","🐵","🐧","🐸","🦄",
        // Foods
        "🍔","🍣","🍕","🍎","🍩","🍜","🍫","☕️",
        // Faces (指定の3種含む)
        "👶","👧","🧒"
    ]

    private var nicknameError: String? {
        ProfileValidation.validateNickname(nickname)
    }

    private var canSave: Bool {
        nicknameError == nil && age >= 13 && age <= 99
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
                TextField("1〜20文字（絵文字は不可）", text: $nickname)
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled(true)
            }

            Section(header: Text("性別")) {
                Picker("性別", selection: $gender) {
                    ForEach(Gender.allCases) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text("年齢")) {
                Picker("年齢", selection: $age) {
                    ForEach(13...99, id: \.self) { v in
                        Text("\(v)歳").tag(v)
                    }
                }
            }

            Section(header: Text("都道府県")) {
                Picker("都道府県", selection: $prefecture) {
                    ForEach(Prefecture.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
            }

            Section(header: Text("職業")) {
                Picker("職業", selection: $occupationCode) {
                    Text("未選択").tag(nil as String?)
                    ForEach(occupationItems, id: \.code) { item in
                        Text(item.label).tag(item.code as String?)
                    }
                }
            }
        }
        .navigationTitle("プロフィール編集")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
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

    private func save() {
        let input = PollAPI.ProfileInput(
            display_name: nickname,
            gender: gender.rawValue,
            age: age,
            prefecture: prefecture == .unset ? nil : prefecture.rawValue,
            occupation: occupationCode,
            icon_emoji: selectedAvatar
        )
        Task {
            do {
                _ = try await PollAPI.upsertProfile(userID: userID, input: input)
                onSaved?()
                dismiss()
            } catch {
                print("Failed to save profile:", error)
            }
        }
    }

    private func preload() async {
        // 1) Use initialProfile if provided (faster)
        if let p = initialProfile {
            await MainActor.run { apply(profile: p) }
            return
        }
        // 2) Otherwise fetch from server once
        do {
            if let p = try await PollAPI.fetchProfile(userID: userID) {
                await MainActor.run { apply(profile: p) }
            }
        } catch {
            print("EDIT preload error:", error)
        }
    }

    private func apply(profile p: PollAPI.UserProfile) {
        if let emoji = p.avatar_value, !emoji.isEmpty { selectedAvatar = emoji }
        nickname = p.username
        if let a = p.age { age = a }
        prefecture = mapPrefecture(from: p.prefecture_code)
        occupationCode = p.occupation
    }

    private func mapPrefecture(from raw: String?) -> Prefecture {
        guard let s0 = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s0.isEmpty else { return .unset }
        // If full Japanese name (e.g. "東京都") already, accept as-is
        if let p = Prefecture(rawValue: s0) { return p }
        // If numeric code 1..47, map to name → enum
        if let n = Int(s0), (1...47).contains(n) {
            let key = String(format: "%02d", n)
            if let name = codeToPrefName[key], let p = Prefecture(rawValue: name) { return p }
        }
        return .unset
    }

    private var codeToPrefName: [String:String] {[
        "01":"北海道","02":"青森県","03":"岩手県","04":"宮城県","05":"秋田県","06":"山形県","07":"福島県",
        "08":"茨城県","09":"栃木県","10":"群馬県","11":"埼玉県","12":"千葉県","13":"東京都","14":"神奈川県",
        "15":"新潟県","16":"富山県","17":"石川県","18":"福井県","19":"山梨県","20":"長野県","21":"岐阜県",
        "22":"静岡県","23":"愛知県","24":"三重県","25":"滋賀県","26":"京都府","27":"大阪府","28":"兵庫県",
        "29":"奈良県","30":"和歌山県","31":"鳥取県","32":"島根県","33":"岡山県","34":"広島県","35":"山口県",
        "36":"徳島県","37":"香川県","38":"愛媛県","39":"高知県","40":"福岡県","41":"佐賀県","42":"長崎県",
        "43":"熊本県","44":"大分県","45":"宮崎県","46":"鹿児島県","47":"沖縄県"
    ]}
}

// MARK: - Preview
#Preview {
    NavigationStack {
        ProfileEditView(userID: UUID(), initialProfile: nil)
    }
}
