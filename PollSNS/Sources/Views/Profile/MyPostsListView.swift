//
//  MyPostsListView.swift
//  PollSNS
//
//  Created by 高木祐輝 on 2025/09/26.
//


import SwiftUI

struct MyPostsListView: View {
    let ownerID: UUID
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
                            Text(p.question).font(.body)
                            Text(p.category).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .task(id: ownerID) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            polls = try await PollAPI.fetchMyPolls(ownerID: ownerID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// プレビュー（任意）
#Preview {
    MyPostsListView(ownerID: AppConfig.devUserID)
}
