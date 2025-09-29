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
    @State private var votedSet: Set<UUID> = []          // 自分が投票済みの pollID
    @State private var myChoiceMap: [UUID: String] = [:] // pollID -> 自分の選択ラベル

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
                        PollRow(
                            poll: p,
                            isVoted: votedSet.contains(p.id),
                            myChoiceLabel: myChoiceMap[p.id]
                        )
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .task(id: ownerID) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .pollDidVote)) { note in
            if let pid = note.userInfo?[AppNotificationKey.pollID] as? UUID {
                votedSet.insert(pid)
                // ラベルは次回ロードで補完（必要ならここで再取得も可）
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            polls = try await PollAPI.fetchMyPolls(ownerID: ownerID)
            await loadVoteDecorations()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func loadVoteDecorations() async {
        let ids = polls.map(\.id)
        guard !ids.isEmpty else {
            await MainActor.run {
                votedSet = []
                myChoiceMap = [:]
            }
            return
        }
        do {
            let detail = try await PollAPI.fetchUserVoteDetailMap(pollIDs: ids, userID: AppConfig.devUserID)
            await MainActor.run {
                // API は「投票がある poll だけ」を返す想定なので、keys をそのまま投票済み集合にする
                votedSet = Set(detail.keys)
                myChoiceMap = detail.reduce(into: [:]) { dict, elem in
                    if let label = elem.value.1 {
                        dict[elem.key] = label
                    }
                }
            }
        } catch {
            // 失敗時は無視（表示なしでOK）
        }
    }
}

// プレビュー（任意）
#Preview {
    MyPostsListView(ownerID: AppConfig.devUserID)
}
