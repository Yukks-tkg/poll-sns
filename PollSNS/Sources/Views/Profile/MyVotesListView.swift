
import SwiftUI
import Combine

struct MyVotesListView: View {
    let userID: UUID
    @State private var polls: [Poll] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            if let err = error {
                Section {
                    VStack(alignment: .center, spacing: 8) {
                        Text("読み込みに失敗しました").font(.headline)
                        Text(err).font(.caption).foregroundStyle(.secondary)
                        Button("再読み込み") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                }
            } else if loading && polls.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("読み込み中…")
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            } else if polls.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Text("まだ投票したアンケートはありません")
                            .foregroundStyle(.secondary)
                        Text("気になる投稿から投票してみましょう")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                }
            } else {
                Section {
                    ForEach(polls) { p in
                        NavigationLink {
                            PollDetailView(poll: p)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.question)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    Text(p.category)
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color(.systemGray6))
                                        .clipShape(Capsule())
                                    if let t = p.createdAtFormatted {
                                        Text(t)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await load() }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .pollDidVote)) { _ in
            Task { await load() }
        }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            polls = try await PollAPI.fetchPollsVotedBy(userID: userID)
        } catch {
            self.error = error.localizedDescription
            self.polls = []
        }
    }
}

// プレビュー（任意）
#Preview {
    MyVotesListView(userID: AppConfig.devUserID)
}
