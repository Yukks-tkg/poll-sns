import SwiftUI

struct SettingsSheet: View {
    var onClose: (() -> Void)?
    var onProfileEdited: (() -> Void)?
    var initialProfile: PollAPI.UserProfile? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("プロフィールを編集") {
                        ProfileEditView(userID: AppConfig.devUserID, initialProfile: initialProfile) {
                            // 保存完了時のコールバック
                            onProfileEdited?()
                            (onClose ?? { dismiss() })()
                        }
                    }
                }

                // 将来の設定項目を追加する場合は以下のセクションを有効化
                // Section("設定") {
                //     Toggle("通知を受け取る", isOn: .constant(true))
                // }

                Section {
                    Button(role: .destructive) {
                        // Auth導入後にログアウト処理を実装
                    } label: {
                        Text("ログアウト")
                    }
                    .disabled(true) // いまは未対応のため無効化
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { (onClose ?? { dismiss() })() }
                }
            }
        }
    }
}

// プレビュー（任意）
#Preview {
    SettingsSheet()
}
