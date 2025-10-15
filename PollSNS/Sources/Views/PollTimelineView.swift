import SwiftUI
import Combine

struct PollTimelineView: View {
    @State private var polls: [Poll] = []
    @State private var errorMessage: String?
    @State private var selectedCategory: String = "all"
    @State private var sortOrder: String = "latest"
    @State private var likeCounts: [UUID: Int] = [:]
    @State private var likedSet: Set<UUID> = []
    @State private var likingNow: Set<UUID> = []
    @State private var votedSet: Set<UUID> = []
    @State private var myChoiceMap: [UUID: String] = [:]
    @State private var showingNewPoll = false
    @State private var animateSort = false

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
        .padding(.bottom, 10)
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
                            VStack(alignment: .leading, spacing: 4) {
                                PollRow(
                                    poll: poll,
                                    isVoted: votedSet.contains(poll.id),
                                    myChoiceLabel: myChoiceMap[poll.id]
                                )
                                HStack(spacing: 8) {
                                    Text(displayCategory(poll.category))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.systemGray6))
                                        .clipShape(Capsule())
                                    if let t = poll.createdAtFormatted {
                                        Text(t)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

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
                .id(sortOrder)
                .refreshable { await load() }
            }
            .navigationTitle("タイムライン")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewPoll = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .task {
                if polls.isEmpty {
                    await load()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pollDidVote).receive(on: RunLoop.main)) { _ in
                Task { await reloadTimeline() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pollDidDelete).receive(on: RunLoop.main)) { note in
                let extractedID: UUID? = {
                    if let any = note.userInfo?["pollID"] {
                        if let u = any as? UUID { return u }
                        if let s = any as? String { return UUID(uuidString: s) }
                    }
                    return nil
                }()
                guard let id = extractedID else { return }
                Task { @MainActor in
                    withAnimation {
                        polls.removeAll { $0.id == id }
                    }
                    await reloadTimeline()
                }
            }
            .onChange(of: sortOrder) { _ in
                animateSort = true
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
            .padding(.vertical, 12)
        }
    }

    // ISO8601（小数秒あり/なし）→ Date 変換ヘルパ
    private func parseISO8601(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return frac.date(from: s) ?? plain.date(from: s)
    }

    @MainActor
    private func load() async {
        do {
            let userID = AppConfig.currentUserID
            let categoryParam = (selectedCategory == "all") ? nil : selectedCategory

            // 1) 一覧は最新で取得（人気はクライアント側で並べ替え）
            let fetched = try await PollAPI.fetchPolls(limit: 20,
                                                       order: "created_at.desc",
                                                       category: categoryParam)
            polls = fetched

            // 2) 付帯情報（いいね数・自分のいいね・投票状況）を取得
            let ids = polls.map(\.id)
            likeCounts = try await PollAPI.fetchLikeCounts(pollIDs: ids)
            likedSet   = try await PollAPI.fetchUserLiked(pollIDs: ids, userID: userID)
            do {
                let detail = try await PollAPI.fetchUserVoteDetailMap(pollIDs: ids, userID: userID)
                self.votedSet = Set(detail.keys)
                self.myChoiceMap = detail.reduce(into: [:]) { $0[$1.key] = $1.value.1 }
            } catch {
                self.votedSet = []
                self.myChoiceMap = [:]
            }

            // 3) 人気順をクライアント側で担保（サーバーが順序を返さなくても OK）
            if sortOrder == "popular" {
                let sorter: (Poll, Poll) -> Bool = { lhs, rhs in
                    let lLikes = lhs.like_count ?? likeCounts[lhs.id] ?? 0
                    let rLikes = rhs.like_count ?? likeCounts[rhs.id] ?? 0
                    if lLikes != rLikes { return lLikes > rLikes }
                    let lDate = parseISO8601(lhs.created_at) ?? .distantPast
                    let rDate = parseISO8601(rhs.created_at) ?? .distantPast
                    return lDate > rDate
                }
                if animateSort {
                    withAnimation(.easeInOut) { polls.sort(by: sorter) }
                } else {
                    polls.sort(by: sorter)
                }
                animateSort = false
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleLike(for pollID: UUID, isLiked: Bool, current: Int) async {
        if likingNow.contains(pollID) { return }
        likingNow.insert(pollID)

        if isLiked {
            likedSet.remove(pollID)
            likeCounts[pollID] = max(0, current - 1)
        } else {
            likedSet.insert(pollID)
            likeCounts[pollID] = current + 1
        }

        do {
            let userID = AppConfig.currentUserID
            if isLiked {
                try await PollAPI.unlike(pollID: pollID, userID: userID)
            } else {
                try await PollAPI.like(pollID: pollID, userID: userID)
            }
        } catch {
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
