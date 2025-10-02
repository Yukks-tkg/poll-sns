import SwiftUI

extension Notification.Name {
    /// ルートのタブを「タイムライン」に切り替えるための通知
    static let switchToTimeline = Notification.Name("switchToTimeline")
}

struct NewPollView: View {
    @Environment(\.dismiss) private var dismiss

    // 親に作成完了を知らせる
    var onCreated: (UUID) -> Void = { _ in }

    // 入力
    @State private var question: String = ""
    @State private var category: String = "food"
    @State private var options: [String] = ["", ""] // 2つ

    // 状態
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // カテゴリ選択（タイムラインと同じキーを使う）
    private let categories: [(key: String, label: String)] = [
        ("all","すべて"), ("food","🍔 ごはん"), ("fashion","👗 ファッション"),
        ("health","🏃‍♀️ 健康"), ("hobby","🎮 趣味"), ("travel","✈️ 旅行"),
        ("relationship","💬 人間関係"), ("school_work","🏫 仕事/学校"),
        ("daily","🗓 日常"), ("pets","🐶 ペット"), ("other","🌀 その他")
    ].filter { $0.key != "all" }

    private var validOptions: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
               .filter { !$0.isEmpty }
    }
    private var isValid: Bool {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let opts = validOptions
        // ❶ 質問は5文字以上120文字以内、❷ 選択肢は2つ以上かつ重複なし
        return q.count >= 5 && q.count <= 120 && Set(opts).count >= 2
    }

    var body: some View {
        Form {
            Section("質問") {
                TextField("例: 今夜の晩ごはんは？", text: $question)
                    .textInputAutocapitalization(.never)
                HStack {
                    Spacer()
                    Text("\(question.count) / 120")
                        .foregroundColor(question.count > 120 ? .red : .secondary)
                        .font(.footnote)
                }
            }
            // 質問が短すぎる場合の注意（あと何文字必要か）
            let _trimmedQ = question.trimmingCharacters(in: .whitespacesAndNewlines)
            if _trimmedQ.count > 0 && _trimmedQ.count < 5 {
                Section {
                    Text("あと \(5 - _trimmedQ.count) 文字以上入力してください")
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            } else if _trimmedQ.count > 120 {
                Section {
                    Text("120文字以内で入力してください")
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
            Section("カテゴリ") {
                Picker("カテゴリ", selection: $category) {
                    ForEach(categories, id: \.key) { c in
                        Text(c.label).tag(c.key)
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Section("選択肢（2つ以上）") {
                ForEach(options.indices, id: \.self) { i in
                    HStack {
                        Text("\(i+1).")
                        TextField("選択肢", text: $options[i])
                            .textInputAutocapitalization(.never)
                    }
                }
                Button {
                    options.append("")
                } label: {
                    Label("行を追加", systemImage: "plus.circle")
                }
                .disabled(options.count >= 8)
            }

            if let msg = errorMessage {
                Section {
                    Text(msg).foregroundColor(.red)
                }
            }
        }
        .navigationTitle("新規アンケート")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    NotificationCenter.default.post(name: .switchToTimeline, object: nil)
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSubmitting ? "作成中…" : "投稿") {
                    Task { await submit() }
                }
                .disabled(!isValid || isSubmitting)
            }
        }
    }

    private func submit() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 5 && q.count <= 120 && isValid else { return }
        isSubmitting = true; errorMessage = nil
        do {
            let id = try await PollAPI.createPoll(
                question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                options: validOptions
            )
            onCreated(id)   // 親に通知
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
