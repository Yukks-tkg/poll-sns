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

    // Results
    @State private var results: [VoteResult] = []
    @State private var totalVotes: Int = 0
    @State private var showResults = false

    // Temporary user id (later replace with Supabase Auth user id)
    private let dummyUserID = UUID(uuidString: "47f61351-7f40-4899-8710-23173bd9c943")!

    // Lock state (disable interactions when voted / submitting / loading)
    private var isLocked: Bool { voted || isSubmitting || loading }

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

                // 問題文
                Text(poll.question)
                    .font(.title2).bold()
                    .multilineTextAlignment(.leading)

                // カテゴリ + 作成日時
                HStack(spacing: 12) {
                    Text(poll.category)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())

                    if let created = poll.createdAtFormatted {
                        Label(created, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                optionsSection
                resultsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationTitle("Poll")
        .task {
            await loadOptions()
            await loadResults()
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
            showResults = true
        } catch {
            // 結果は無くても UI は出す
            results = []
            totalVotes = 0
            showResults = true
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func countFor(optionID: UUID) -> Int {
        results.first(where: { $0.option_id == optionID })?.count ?? 0
    }
}
