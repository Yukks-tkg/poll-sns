import SwiftUI
import Combine

struct PollTimelineView: View {
    @State private var polls: [Poll] = []
    @State private var errorMessage: String?
    @State private var selectedCategory: String = "all"
    @State private var sortOrder: String = "latest" // "latest" or "popular"
    @State private var likeCounts: [UUID: Int] = [:]   // pollID -> いいね数
    @State private var likedSet: Set<UUID> = []        // 自分がいいね済みの pollID
    @State private var likingNow: Set<UUID> = []       // 二重タップ防止
    @State private var votedSet: Set<UUID> = []          // 自分が投票済みの pollID
    @State private var myChoiceMap: [UUID: String] = [:] // pollID -> 自分の選択ラベル
    @State private var showingNewPoll = false
    private let dummyUserID = UUID(uuidString: "47F61351-7F40-4899-8710-23173BD9C943")!

    private let categoryOptions: [(key: String, label: String)] = [
        ("all", "すべて"),
        ("food", "🍔 ごはん"),
        ("fashion", "👗 ファッション"),
        ("health", "🏃 健康"),
        ("hobby", "🎮 趣味"),
        ("travel", "✈️ 旅行"),
        ("relationship", "💬 人間関係"),
        ("school_work", "🏫 仕事/学校"),
        ("daily", "🧺 日常"),
        ("pets", "🐾 ペット"),
        ("other", "🌀 その他")
    ]

    private var sortBar: some View {
        HStack(spacing: 12) {
            Text("並び替え")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("並び替え", selection: $sortOrder) {
                Text("最新").tag("latest")
                Text("人気").tag("popular")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    var body: some View {
            VStack(spacing: 0) {
                sortBar
                categoryBar
                List(polls) { poll in
                    NavigationLink {
                        PollDetailView(poll: poll)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            // 共通行表示（投票済みバッジ & あなたの選択ラベル対応）
                            PollRow(
                                poll: poll,
                                isVoted: votedSet.contains(poll.id),
                                myChoiceLabel: myChoiceMap[poll.id]
                            )

                            // 右側：いいねボタン（既存）
                            let count = likeCounts[poll.id] ?? 0
                            let isLiked = likedSet.contains(poll.id)
                            Button {
                                Task { await toggleLike(for: poll.id, isLiked: isLiked, current: count) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isLiked ? "heart.fill" : "heart")
                                        .foregroundStyle(isLiked ? .red : .secondary)
                                    Text("\(count)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewPoll = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .task { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .pollDidVote)) { _ in
                Task { await reloadTimeline() }
            }
            .onChange(of: sortOrder) { _ in
                Task { await load() }
            }
            .sheet(isPresented: $showingNewPoll, onDismiss: {
                Task { await reloadTimeline() }
            }) {
                NavigationStack { NewPollView() }
            }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categoryOptions, id: \.key) { opt in
                    let isSel = (opt.key == selectedCategory)
                    Text(opt.label)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSel ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        .foregroundColor(isSel ? .accentColor : .primary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isSel ? Color.accentColor : Color(.systemGray4), lineWidth: 1)
                        )
                        .onTapGesture {
                            if selectedCategory != opt.key {
                                selectedCategory = opt.key
                                Task { await load() }
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func load() async {
        do {
            let categoryParam = (selectedCategory == "all") ? nil : selectedCategory
            if sortOrder == "popular" {
                polls = try await PollAPI.fetchPollsPopular(limit: 20, category: categoryParam)
            } else {
                polls = try await PollAPI.fetchPolls(limit: 20,
                                                     order: "created_at.desc",
                                                     category: categoryParam)
            }
            // いいね情報の取得（件数と自分の状態）
            let ids = polls.map(\.id)
            likeCounts = try await PollAPI.fetchLikeCounts(pollIDs: ids)
            likedSet   = try await PollAPI.fetchUserLiked(pollIDs: ids, userID: dummyUserID)
            // 投票済み情報（バッジと “あなたの選択” 表示用）
            do {
                let detail = try await PollAPI.fetchUserVoteDetailMap(pollIDs: ids, userID: dummyUserID)
                self.votedSet = Set(detail.keys)
                self.myChoiceMap = detail.reduce(into: [:]) { $0[$1.key] = $1.value.1 }
            } catch {
                // 取得失敗時は空のまま（UIは非表示になるだけ）
                self.votedSet = []
                self.myChoiceMap = [:]
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleLike(for pollID: UUID, isLiked: Bool, current: Int) async {
        // 二重送信防止
        if likingNow.contains(pollID) { return }
        likingNow.insert(pollID)

        // 楽観的更新
        if isLiked {
            likedSet.remove(pollID)
            likeCounts[pollID] = max(0, current - 1)
        } else {
            likedSet.insert(pollID)
            likeCounts[pollID] = current + 1
        }

        do {
            if isLiked {
                try await PollAPI.unlike(pollID: pollID, userID: dummyUserID)
            } else {
                try await PollAPI.like(pollID: pollID, userID: dummyUserID)
            }
        } catch {
            // 失敗したらロールバック
            if isLiked {
                likedSet.insert(pollID)
                likeCounts[pollID] = current
            } else {
                likedSet.remove(pollID)
                likeCounts[pollID] = current
            }
        }

        likingNow.remove(pollID)
    }
    
    @MainActor
    private func reloadTimeline() async {
        await load()
    }
}
