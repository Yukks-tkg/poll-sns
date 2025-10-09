import SwiftUI

enum Gender: String, CaseIterable, Identifiable {
    case male, female, other
    var id: String { rawValue }
    var display: String {
        switch self {
        case .male: return "男性"
        case .female: return "女性"
        case .other: return "その他"
        }
    }
}

private extension String {
    var containsEmoji: Bool {
        return unicodeScalars.contains { $0.properties.isEmoji && ($0.value > 0x238C) }
    }
}

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

struct ProfileEditView: View {
    let userID: UUID
    let initialProfile: PollAPI.UserProfile?
    var onSaved: (() -> Void)? = nil

    @State private var selectedAvatar: String = "👶"
    @State private var nickname: String = ""
    @State private var gender: Gender = .other
    @State private var age: Int = 20
    @State private var didPreload = false

    @Environment(\.dismiss) private var dismiss

    private let avatarCandidates: [String] = [

        "🐶","🐱","🐼","🦊","🐻","🦁","🐵","🐧","🐸","🦄",

        "🍔","🍣","🍕","🍎","🍩","🍜","🍫","☕️",

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
                        Text(g.display).tag(g)
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
        }
        .navigationTitle("プロフィール編集")
        .navigationBarBackButtonHidden(true)
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

        if let p = initialProfile {
            await MainActor.run { apply(profile: p) }
            return
        }

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
        if let g = p.gender, let choice = Gender(rawValue: g) { gender = choice } else { gender = .other }
    }
}

#Preview {
    NavigationStack {
        ProfileEditView(userID: UUID(), initialProfile: nil)
    }
}
