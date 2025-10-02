//
//  MyPostsListView.swift
//  PollSNS
//
//  Created by 高木祐輼 on 2025/09/26.
//

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
        Group {
            if loading {
                ProgressView("読み込み中…")
            } else if let err = error {
                VStack(spacing: 8) {
                    Text("読み込みに失敗しました")
                    Text(err).font(.caption).foregroundStyle(.secondary)
                    Button("再読み込み") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                }
                .padding()
            } else if polls.isEmpty {
                VStack {
                    Text("まだ投稿がありません")
                        .foregroundStyle(.secondary)
                        .padding()
                    Button("再読み込み") { Task { await load() } }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                }
            } else {
                List(polls) { p in
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
                .listStyle(.plain)
                .refreshable { await load() }
            }
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

    private func load() async {
        // 二重起動を避ける（.task と .refreshable が同時に動くケース対策）
        if loading { return }
        loading = true
        defer { loading = false }
        do {
            // 自分の投稿を取得（ソフト削除済みはAPI側で除外済み）
            polls = try await PollAPI.fetchMyPolls(ownerID: ownerID)
            error = nil
        } catch is CancellationError {
            // Pull to Refresh などでキャンセルされた場合は“正常”として無視
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            await MainActor.run {
                self.error = "読み込みに失敗しました"
            }
        }
    }
}

// プレビュー（任意）
#Preview {
    MyPostsListView(ownerID: AppConfig.devUserID)
}
