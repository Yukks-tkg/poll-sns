import SwiftUI

/// 一覧セル共通：右端に「投票済み」バッジ、サブ行に「あなたの選択：◯◯」を表示可能
struct PollRow: View {
    let poll: Poll              // 既存のモデル型を想定（id, question, category など）
    let isVoted: Bool           // 投票済みなら true（右端バッジを出す）
    let myChoiceLabel: String?  // 自分が選んだ選択肢のラベル（任意）

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(poll.question)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                // 自分の選択が分かっていれば優先表示。無ければカテゴリを表示
                if let label = myChoiceLabel, !label.isEmpty {
                    Text("あなたの選択：\(label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(poll.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if isVoted {
                Label("投票済み", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .accessibilityLabel("投票済み")
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}
