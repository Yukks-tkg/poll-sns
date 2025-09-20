import SwiftUI

struct PollDetailView: View {
    let poll: Poll

    @State private var options: [PollOption] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var selectedOptionID: UUID?
    @State private var isSubmitting = false
    @State private var voted = false

    // 仮ユーザーID（後で Supabase Auth に置換）
    private let dummyUserID = UUID(uuidString: "47f61351-7f40-4899-8710-23173bd9c943")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                optionsSection
                Spacer(minLength: 0)
            }
            .padding()
        }
        .navigationTitle("Poll")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadOptions() }
    }

    // MARK: - Sections split to help type-checking

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 質問
            Text(poll.question)
                .font(.title2).bold()
                .multilineTextAlignment(.leading)

            // カテゴリと作成日
            HStack(spacing: 12) {
                // カテゴリのチップ風表示
                Text(poll.category)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())

                // 作成日（created_at があれば）
                if let created = poll.createdAtFormatted {
                    Label(created, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var optionsSection: some View {
        if loading {
            loadingView
        } else if let msg = errorMessage {
            errorView(msg)
        } else if options.isEmpty {
            emptyView
        } else {
            optionsList
        }
    }

    // MARK: - Subviews for optionsSection

    private var loadingView: some View {
        ProgressView("読み込み中…")
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Text("読み込みに失敗しました").font(.headline)
            Text(msg).font(.caption).foregroundStyle(.secondary)
            Button("再読み込み") { Task { await loadOptions() } }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyView: some View {
        Text("選択肢がありません")
            .frame(maxWidth: .infinity, minHeight: 120)
            .foregroundStyle(.secondary)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var optionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(options) { opt in
                Button {
                    selectedOptionID = opt.id
                } label: {
                    HStack {
                        Image(systemName: selectedOptionID == opt.id ? "largecircle.fill.circle" : "circle")
                        Text(opt.displayText)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedOptionID == opt.id ? Color.accentColor.opacity(0.1)
                                                          : Color(.systemGray6))
                )
            }

            Button {
                Task { await submitVote() }
            } label: {
                if isSubmitting {
                    ProgressView()
                } else {
                    Text(voted ? "投票済み" : "この選択で投票する")
                }
            }
            .disabled(selectedOptionID == nil || isSubmitting || voted)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(voted ? Color(.systemGray5) : Color.accentColor)
            .foregroundColor(voted ? Color.secondary : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Load & Submit

    private func loadOptions() async {
        loading = true
        defer { loading = false }
        do {
            options = try await PollAPI.fetchOptions(for: poll.id)
            errorMessage = nil
            print("options:", options.map(\.displayText))
        } catch {
            errorMessage = error.localizedDescription
            print("loadOptions error:", error)
        }
    }

    private func submitVote() async {
        guard let optionID = selectedOptionID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await PollAPI.submitVote(pollID: poll.id, optionID: optionID, userID: dummyUserID)
            voted = true
            print("vote OK:", optionID)
        } catch {
            errorMessage = error.localizedDescription
            print("submitVote error:", error)
        }
    }
}

#Preview {
    PollDetailView(poll: .init(
        id: UUID(),
        question: "今夜の晩ごはんは？",
        category: "food",
        created_at: "2025-09-18T05:37:46.29979+00:00"
    ))
}
