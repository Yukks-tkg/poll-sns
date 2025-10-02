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
                
                Section("ポリシー") {
                    NavigationLink {
                        LegalDocumentView(title: "利用規約", htmlFileName: "terms-ja")
                    } label: {
                        Label("利用規約", systemImage: "doc.text")
                    }

                    NavigationLink {
                        LegalDocumentView(title: "プライバシーポリシー", htmlFileName: "privacy-ja")
                    } label: {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                }

                // 将来の設定項目を追加する場合は以下のセクションを有効化
                // Section("設定") {
                //     Toggle("通知を受け取る", isOn: .constant(true))
                // }
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
