import SwiftUI

struct ReportSheet: View {
    let pollID: UUID
    let reporterUserID: UUID
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selected: PollAPI.ReportReason = .spam
    @State private var note: String = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("理由") {
                    Picker("理由", selection: $selected) {
                        ForEach(PollAPI.ReportReason.allCases, id: \.self) { r in
                            Text(r.display).tag(r)
                        }
                    }
                }
                Section("詳細（任意）") {
                    TextEditor(text: $note)
                        .frame(minHeight: 120)
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(note.count)/300")
                                .font(.caption2).foregroundStyle(.secondary)
                                .padding(8)
                        }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("通報")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if sending { ProgressView() } else { Text("送信") }
                    }
                    .disabled(sending)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        sending = true
        defer { sending = false }
        do {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = trimmed.isEmpty ? nil : String(trimmed.prefix(300))
            try await PollAPI.submitReport(
                pollID: pollID,
                reporterUserID: reporterUserID,
                reason: selected,
                detail: text
            )
            onDone?()
            dismiss()
        } catch {
            self.error = "送信に失敗しました。ネットワーク状況をご確認ください。"
        }
    }
}
