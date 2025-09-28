import SwiftUI

struct MyVotesListView: View {
    let userID: UUID
    @State private var polls: [Poll] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        Group {
            if loading {
                ProgressView("読み込み中…")
            } else if let err = error {
                VStack(spacing: 8) {
                    Text("読み込みに失敗しました")
                    Text(err).font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            } else if polls.isEmpty {
                Text("まだ投票したアンケートがありません")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(polls) { p in
                    NavigationLink {
                        PollDetailView(poll: p)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.question).font(.body)
                            Text(p.category).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await load() }
        .navigationTitle("")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            polls = try await PollAPI.fetchMyVotedPolls(userID: userID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// プレビュー（任意）
#Preview {
    MyVotesListView(userID: AppConfig.devUserID)
}
