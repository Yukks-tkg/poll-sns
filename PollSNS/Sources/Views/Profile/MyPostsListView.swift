import SwiftUI
import Combine

struct MyPostsListView: View {
    let ownerID: UUID
    @State private var polls: [Poll] = []
    @State private var error: String?
    @State private var loading = false
    
    private func displayCategory(_ key: String) -> String {
        let map: [String: String] = [
            "all": "すべて",
            "food": "🍔 ごはん",
            "fashion": "👗 ファッション",
            "health": "🏃 健康",
            "hobby": "🎮 趣味",
            "travel": "✈️ 旅行",
            "relationship": "💬 人間関係",
            "school_work": "🏫 仕事/学校",
            "daily": "🧺 日常",
            "pets": "🐾 ペット",
            "other": "🌀 その他"
        ]
        return map[key] ?? key
    }

    var body: some View {
        List {
            if let err = error {
                Section {
                    VStack(spacing: 8) {
                        Text("読み込みに失敗しました")
                            .font(.headline)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("再読み込み") {
                            Task { await load() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
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
                    VStack(spacing: 12) {
                        Text("まだ投稿したアンケートはありません")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("下の投稿ボタンから作成してみましょう")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
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
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    Text(displayCategory(p.category))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
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
        .refreshable {
            // If an initial/ongoing load is in progress, wait until it finishes
            while loading {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            await load()
        }
        .task(id: ownerID) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .pollDidDelete).receive(on: RunLoop.main)) { note in
            let extractedID: UUID? = {
                if let any = note.userInfo?["pollID"] {
                    if let u = any as? UUID { return u }
                    if let s = any as? String { return UUID(uuidString: s) }
                }
                return nil
            }()
            guard let id = extractedID else { return }
            withAnimation {
                polls.removeAll { $0.id == id }
            }
        }
    }

    @MainActor
    private func load() async {
        if loading { return }
        loading = true
        defer { loading = false }
        do {
            polls = try await PollAPI.fetchMyPolls(ownerID: ownerID)
            error = nil
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            self.error = "読み込みに失敗しました"
            self.polls = []
        }
    }
}

#Preview {
    MyPostsListView(ownerID: AppConfig.currentUserID)
}
