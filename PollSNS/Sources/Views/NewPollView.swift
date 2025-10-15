import SwiftUI

extension Notification.Name {
    /// ルートのタブを「タイムライン」に切り替えるための通知
    static let switchToTimeline = Notification.Name("switchToTimeline")
}

struct NewPollView: View {
    @Environment(\.dismiss) private var dismiss

    var onCreated: (UUID) -> Void = { _ in }

    @State private var question: String = ""
    @State private var category: String = "food"
    @State private var options: [String] = ["", ""] // 2つ

    // 任意: 作成した経緯・背景
    @State private var descriptionText: String = ""
    private let descriptionMax = 300
    private var isDescriptionWithinLimit: Bool {
        descriptionText.count <= descriptionMax
    }

    @State private var isSubmitting = false
    @State private var errorMessage: String?

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
        // ❶ 質問は5文字以上80文字以内、❷ 選択肢は2つ以上かつ重複なし
        return q.count >= 5 && q.count <= 80 && Set(opts).count >= 2
    }

    var body: some View {
        Form {
            // 質問
            Section("質問【必須】") {
                TextField("例: 睡眠時間は平均してどれくらいですか？", text: $question, axis: .vertical)
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.never)
                HStack {
                    Spacer()
                    Text("\(question.count) / 80")
                        .foregroundColor(question.count > 80 ? .red : .secondary)
                        .font(.footnote)
                }
            }
            // 質問の注意
            let _trimmedQ = question.trimmingCharacters(in: .whitespacesAndNewlines)
            if _trimmedQ.count > 0 && _trimmedQ.count < 5 {
                Section {
                    Text("あと \(5 - _trimmedQ.count) 文字以上入力してください")
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            } else if _trimmedQ.count > 80 {
                Section {
                    Text("80文字以内で入力してください")
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            // カテゴリ
            Section("カテゴリ【必須】") {
                Picker("カテゴリ", selection: $category) {
                    ForEach(categories, id: \.key) { c in
                        Text(c.label).tag(c.key)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            // 選択肢
            Section("選択肢【必須】") {
                ForEach(options.indices, id: \.self) { i in
                    HStack {
                        Text("\(i+1).")
                        TextField("選択肢", text: $options[i])
                            .textInputAutocapitalization(.never)
                        Spacer(minLength: 8)
                        if options.count > 2 {
                            Button(role: .destructive) {
                                options.remove(at: i)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("この行を削除")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if options.count > 2 {
                            Button(role: .destructive) {
                                options.remove(at: i)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
                Button {
                    options.append("")
                } label: {
                    Label("行を追加", systemImage: "plus.circle")
                }
                .disabled(options.count >= 8)
            }

            // 任意: 作成した経緯・背景（質問と同じUI構成）
            Section("質問を作成した経緯・背景【任意】") {
                TextField("例: 仕事の関係で睡眠時間が変わりがちです。皆どのくらい寝ているのか参考にしたいです。", text: $descriptionText, axis: .vertical)
                    .lineLimit(2...6)
                    .textInputAutocapitalization(.never)
                HStack {
                    Spacer()
                    Text("\(descriptionText.count) / \(descriptionMax)")
                        .foregroundColor(descriptionText.count > descriptionMax ? .red : .secondary)
                        .font(.footnote)
                }
            }
            let _trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if _trimmedDesc.count > descriptionMax {
                Section {
                    Text("\(descriptionMax)文字以内で入力してください")
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            // エラー表示
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
                .disabled(!isValid || isSubmitting || !isDescriptionWithinLimit)
            }
        }
    }

    private func submit() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 5 && q.count <= 80 && isValid && isDescriptionWithinLimit else { return }
        isSubmitting = true; errorMessage = nil
        do {
            let descTrimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc: String? = descTrimmed.isEmpty ? nil : String(descTrimmed.prefix(descriptionMax))

            let id = try await PollAPI.createPoll(
                question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                options: validOptions,
                description: desc
            )
            onCreated(id)   // 親に通知
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
