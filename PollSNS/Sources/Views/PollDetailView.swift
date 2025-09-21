import SwiftUI

struct PollDetailView: View {
    // Input
    let poll: Poll

    // UI state
    @State private var options: [PollOption] = []
    @State private var selectedOptionID: UUID?
    @State private var isSubmitting = false
    @State private var voted = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showAbsoluteTime = false

    // Results
    @State private var results: [VoteResult] = []
    @State private var totalVotes: Int = 0
    @State private var showResults = false

    // Temporary user id (later replace with Supabase Auth user id)
    private let dummyUserID = UUID(uuidString: "47f61351-7f40-4899-8710-23173bd9c943")!

    // Lock state (disable interactions when voted / submitting / loading)
    private var isLocked: Bool { voted || isSubmitting || loading }

    // 作成者テキスト（Auth導入前は devUserID と一致したら「あなた」）
    private var ownerText: String {
        if let owner = poll.owner_id, owner == AppConfig.devUserID {
            return "作成者: あなた"
        } else if poll.owner_id != nil {
            return "作成者: 匿名"
        } else {
            return "作成者: －"
        }
    }

    // absolute(固定書式) と relative(◯分前) の切り替えに使う
    private func relativeFromAbsoluteString(_ absolute: String) -> String {
        // 既存の createdAtFormatted は "yyyy/MM/dd HH:mm" 形式想定
        let abs = DateFormatter()
        abs.locale = Locale(identifier: "ja_JP")
        abs.dateFormat = "yyyy/MM/dd HH:mm"
        guard let date = abs.date(from: absolute) else { return absolute }
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "ja_JP")
        rel.unitsStyle = .full
        return rel.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Small subviews (to keep body shallow for type-checker)
    private struct OptionRow: View {
        let text: String
        let isSelected: Bool
        let locked: Bool
        let onTap: () -> Void
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(locked ? .secondary : (isSelected ? Color.accentColor : .secondary))
                Text(text)
                    .font(.body)
                    .foregroundStyle(locked ? .secondary : .primary)
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { if !locked { onTap() } }
        }
    }

    private struct ResultBar: View {
        let label: String
        let count: Int
        let total: Int
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                    Spacer()
                    Text("\(count)票").foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    let width = geo.size.width
                    let ratio = total > 0 ? CGFloat(count) / CGFloat(total) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5))
                        Capsule().fill(Color.accentColor.opacity(0.9))
                            .frame(width: width * ratio)
                    }
                }
                .frame(height: 8)
            }
        }
    }

    @ViewBuilder
    private var resultsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("結果")
                .font(.headline)
            Text("投票すると結果が見えます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var optionsSection: some View {
        // 選択肢
        if loading {
            ProgressView("読み込み中…")
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let msg = errorMessage {
            VStack(spacing: 8) {
                Text("読み込みに失敗しました")
                    .font(.headline)
                Text(msg).font(.caption).foregroundStyle(.secondary)
                Button("再読み込み") { Task { await loadOptions() } }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if options.isEmpty {
            Text("選択肢がありません")
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(spacing: 16) {
                ForEach(options) { opt in
                    OptionRow(
                        text: opt.displayText,
                        isSelected: selectedOptionID == opt.id,
                        locked: isLocked,
                        onTap: { selectedOptionID = opt.id }
                    )
                }

                Button {
                    Task { await submitVote() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Text(voted ? "投票済み" : "この選択で投票する")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOptionID == nil || isSubmitting || voted)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isLocked)
            .opacity(isLocked ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.15), value: isLocked)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        // 結果表示
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("結果").font(.headline)
                Spacer()
                if totalVotes > 0 {
                    Text("\(totalVotes)票").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("まだ投票はありません").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(options) { opt in
                let count = countFor(optionID: opt.id)
                ResultBar(label: opt.displayText, count: count, total: totalVotes)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(showResults ? 1 : 0.4)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ヘッダー：作成者 + 作成時刻(トグル) + カテゴリ
                HStack(alignment: .center, spacing: 12) {
                    // 簡易アバター
                    Circle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ownerText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let created = poll.createdAtFormatted {
                            Text(showAbsoluteTime ? created : relativeFromAbsoluteString(created))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .onTapGesture { showAbsoluteTime.toggle() }
                                .animation(.default, value: showAbsoluteTime)
                        }
                    }

                    Spacer()

                    // カテゴリチップ
                    Text(poll.category)
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }

                // 問題文
                Text(poll.question)
                    .font(.title2).bold()
                    .multilineTextAlignment(.leading)

                HStack(spacing: 12) {
                    // （ヘッダーに移動済みのためカテゴリのみ軽く再掲 or 必要なら削除）
                    // 表示が重複するならこのHStack自体を削除してもOK
                }

                optionsSection
                if showResults {
                    resultsSection
                } else {
                    resultsPlaceholder
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationTitle("Poll")
        .task {
            await loadOptions()
            do {
                // 判定: すでに投票済みなら結果を表示
                let votedNow = try await PollAPI.hasVoted(pollID: poll.id, userID: dummyUserID)
                voted = votedNow
                if votedNow {
                    await loadResults()
                    showResults = true
                } else {
                    showResults = false
                }
            } catch {
                // 判定に失敗したら結果は隠す（後で投票すれば表示）
                showResults = false
            }
        }
    }

    // MARK: - Actions

    private func loadOptions() async {
        loading = true
        defer { loading = false }
        do {
            options = try await PollAPI.fetchOptions(for: poll.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadResults() async {
        do {
            let rows = try await PollAPI.fetchResults(for: poll.id)
            results = rows
            totalVotes = rows.reduce(0) { $0 + $1.count }
        } catch {
            // 結果は無くても UI は出す
            results = []
            totalVotes = 0
        }
    }

    private func submitVote() async {
        guard let optionID = selectedOptionID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await PollAPI.submitVote(pollID: poll.id, optionID: optionID, userID: dummyUserID)
            voted = true
            await loadResults()
            showResults = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func countFor(optionID: UUID) -> Int {
        results.first(where: { $0.option_id == optionID })?.count ?? 0
    }
}
