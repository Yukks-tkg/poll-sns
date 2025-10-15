import SwiftUI
import SafariServices

struct SettingsSheet: View {
    var onClose: (() -> Void)?
    // 変更: 保存後の最新プロフィールを渡す
    var onProfileEdited: ((PollAPI.UserProfile) -> Void)?
    var initialProfile: PollAPI.UserProfile? = nil
    @Environment(\.dismiss) private var dismiss

    // NavigationStack のルート管理（安定動作のため Route で遷移）
    private enum Route: Hashable {
        case editProfile
    }
    @State private var path: [Route] = []

    // Notion の公開リンクをアプリ内ブラウザで開く
    @State private var showPrivacy = false
    @State private var showTerms = false
    private let privacyURL = URL(string: "https://immense-engineer-7f8.notion.site/d994d86dac6a4a9eaedf16a918d846e1")!
    private let termsURL = URL(string: "https://immense-engineer-7f8.notion.site/28d0dee3bb09803c9b7ff97fb21e659a")!

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    // Button ではなく NavigationLink を使用（行全体が確実にタップ可能）
                    NavigationLink(value: Route.editProfile) {
                        HStack {
                            Text("プロフィールを編集")
                            Spacer()
                            // 自前の矢印は削除（NavigationLink が自動で表示します）
                        }
                        .frame(maxWidth: .infinity, alignment: .leading) // ヒット領域を広げる
                        .contentShape(Rectangle())
                    }
                }

                Section("ポリシー") {
                    Button {
                        showTerms = true
                    } label: {
                        Label("利用規約", systemImage: "doc.text")
                    }
                    Button {
                        showPrivacy = true
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
            // Route ごとの遷移先
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .editProfile:
                    ProfileEditView(userID: AppConfig.currentUserID, initialProfile: initialProfile) { savedProfile in
                        onProfileEdited?(savedProfile)
                        (onClose ?? { dismiss() })()
                    }
                }
            }
            // NotionリンクをSFSafariViewControllerで表示
            .sheet(isPresented: $showPrivacy) {
                SafariSheet(url: privacyURL)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showTerms) {
                SafariSheet(url: termsURL)
                    .ignoresSafeArea()
            }
        }
    }
}

// SFSafariViewController ラッパー
private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(.accentColor)
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview {
    SettingsSheet()
}
