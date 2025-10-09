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
                        ProfileEditView(userID: AppConfig.currentUserID, initialProfile: initialProfile) {
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

#Preview {
    SettingsSheet()
}
