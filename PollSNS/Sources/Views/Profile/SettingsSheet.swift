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
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("みんなの投票 v\(v)")
                    }
                    Text("© 2025 Yuki Takagi")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
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
