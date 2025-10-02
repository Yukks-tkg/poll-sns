
import SwiftUI

extension Notification.Name {
    static let pollDidDelete = Notification.Name("pollDidDelete")
}

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
    @State private var myChoiceLabel: String? = nil
    @State private var showAbsoluteTime = false

    // MARK: - Gender filter (UI only for now)
    private enum GenderFilter: String, CaseIterable, Identifiable {
        case all, male, female, other
        var id: Self { self }
        var label: String {
            switch self {
            case .all:    return "すべて"
            case .male:   return "男性"
            case .female: return "女性"
            case .other:  return "その他"
            }
        }
        /// API 渡し用（現状は未使用）
        var apiValue: String? {
            switch self {
            case .all:    return nil
            case .male:   return "male"
            case .female: return "female"
            case .other:  return "other"
            }
        }
    }

    @State private var genderFilter: GenderFilter = .all

    // MARK: - Age band filter
    private enum AgeBand: CaseIterable, Identifiable {
        case teens, twenties, thirties, forties, fiftiesPlus
        var id: Self { self }
        var label: String {
            switch self {
            case .teens: return "10代"
            case .twenties: return "20代"
            case .thirties: return "30代"
            case .forties: return "40代"
            case .fiftiesPlus: return "50代以上"
            }
        }
        var range: (Int?, Int?) {
            switch self {
            case .teens:        return (10, 19)
            case .twenties:     return (20, 29)
            case .thirties:     return (30, 39)
            case .forties:      return (40, 49)
            case .fiftiesPlus:  return (50, nil)
            }
        }
    }
    @State private var selectedAgeBand: AgeBand? = nil
    // 性別で色分け表示
    @State private var colorizeByGender = false
    @State private var genderBreakdown: [UUID: PollAPI.GenderBreakdown] = [:]

    // 年代で色分け表示
    @State private var colorizeByAge = false
    @State private var ageBreakdown: [UUID: PollAPI.AgeBreakdown] = [:]

    // Results
    @State private var results: [VoteResult] = []
    @State private var totalVotes: Int = 0
    @State private var showResults = false

    // Report sheet
    @State private var showReport = false

    // Thank-you alert after reporting
    @State private var showReportThanks = false

    // Owner avatar emoji (loaded from profiles)
    @State private var ownerEmoji: String?

    // Delete state
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var deleteError: String?

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

    // カテゴリ表示（コード -> 絵文字付き日本語ラベル）
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

    private struct ResultBarStacked: View {
        let label: String
        let male: Int
        let female: Int
        let other: Int
        var total: Int { male + female + other }

        private let maleColor = Color.blue
        private let femaleColor = Color.pink
        private let otherColor = Color.purple

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                    Spacer()
                    Text("\(total)票").foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    let mW = total > 0 ? w * CGFloat(male) / CGFloat(total) : 0
                    let fW = total > 0 ? w * CGFloat(female) / CGFloat(total) : 0
                    let oW = total > 0 ? w * CGFloat(other) / CGFloat(total) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5))
                        HStack(spacing: 0) {
                            Capsule().fill(maleColor).frame(width: mW)
                            Capsule().fill(femaleColor).frame(width: fW)
                            Capsule().fill(otherColor).frame(width: oW)
                        }
                    }
                }
                .frame(height: 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Label("男性 \(male)", systemImage: "square.fill")
                            .foregroundStyle(maleColor).font(.caption2)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Label("女性 \(female)", systemImage: "square.fill")
                            .foregroundStyle(femaleColor).font(.caption2)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Label("その他 \(other)", systemImage: "square.fill")
                            .foregroundStyle(otherColor).font(.caption2)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private struct ResultBarStackedAge: View {
        let label: String
        let teens: Int
        let twenties: Int
        let thirties: Int
        let forties: Int
        let fiftiesPlus: Int
        var total: Int { teens + twenties + thirties + forties + fiftiesPlus }

        // 色（好みで調整）
        private let c10 = Color.blue
        private let c20 = Color.teal
        private let c30 = Color.green
        private let c40 = Color.orange
        private let c50 = Color.pink

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                    Spacer()
                    Text("\(total)票").foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    let w10 = total > 0 ? w * CGFloat(teens)       / CGFloat(total) : 0
                    let w20 = total > 0 ? w * CGFloat(twenties)    / CGFloat(total) : 0
                    let w30 = total > 0 ? w * CGFloat(thirties)    / CGFloat(total) : 0
                    let w40 = total > 0 ? w * CGFloat(forties)     / CGFloat(total) : 0
                    let w50 = total > 0 ? w * CGFloat(fiftiesPlus) / CGFloat(total) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5))
                        HStack(spacing: 0) {
                            Capsule().fill(c10).frame(width: w10)
                            Capsule().fill(c20).frame(width: w20)
                            Capsule().fill(c30).frame(width: w30)
                            Capsule().fill(c40).frame(width: w40)
                            Capsule().fill(c50).frame(width: w50)
                        }
                    }
                }
                .frame(height: 8)

                // 凡例（横スクロールで折り返し防止）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Label("10代 \(teens)", systemImage: "square.fill")
                            .foregroundStyle(c10).font(.caption2)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Label("20代 \(twenties)", systemImage: "square.fill")
                            .foregroundStyle(c20).font(.caption2)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Label("30代 \(thirties)", systemImage: "square.fill")
                            .foregroundStyle(c30).font(.caption2)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Label("40代 \(forties)", systemImage: "square.fill")
                            .foregroundStyle(c40).font(.caption2)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Label("50代以上 \(fiftiesPlus)", systemImage: "square.fill")
                            .foregroundStyle(c50).font(.caption2)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.top, 2)
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

    // 性別フィルタ（UIのみ。切替で結果再読み込み）
    @ViewBuilder
    private var genderFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("フィルタ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("性別", selection: $genderFilter) {
                ForEach(GenderFilter.allCases) { g in
                    Text(g.label).tag(g)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.top, 4)
    }

    // 年代フィルタ（チップ方式で横スクロール。小画面でも省略されない）
    @ViewBuilder
    private var ageFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("年代")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // 「すべて」チップ
                    let isAll = (selectedAgeBand == nil)
                    Text("すべて")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isAll ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        .foregroundColor(isAll ? .accentColor : .primary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(isAll ? Color.accentColor : Color(.systemGray4), lineWidth: 1))
                        .onTapGesture {
                            if selectedAgeBand != nil {
                                selectedAgeBand = nil
                            }
                        }

                    ForEach(AgeBand.allCases) { b in
                        let isSel = (selectedAgeBand == b)
                        Text(b.label)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSel ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                            .foregroundColor(isSel ? .accentColor : .primary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSel ? Color.accentColor : Color(.systemGray4), lineWidth: 1))
                            .onTapGesture { selectedAgeBand = b }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 4)
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
                    HStack(spacing: 8) {
                        OptionRow(
                            text: opt.displayText,
                            isSelected: selectedOptionID == opt.id,
                            locked: isLocked,
                            onTap: { selectedOptionID = opt.id }
                        )
                        // 既に投票済みで、かつこの行が自分の選択ならバッジ表示
                        if voted, let label = myChoiceLabel, label == opt.displayText {
                            Label("あなたの選択", systemImage: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
            HStack(alignment: .center, spacing: 8) {
                Text("結果").font(.headline)
                Spacer()
                Button {
                    colorizeByGender.toggle()
                    if colorizeByGender {
                        colorizeByAge = false // 同時ONを避ける
                        Task { await loadGenderBreakdown() }
                    }
                } label: {
                    Text("性別")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorizeByGender ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundColor(colorizeByGender ? .accentColor : .secondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(colorizeByGender ? Color.accentColor : Color(.systemGray4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("性別で色分け")
                .accessibilityValue(colorizeByGender ? "オン" : "オフ")
                Button {
                    colorizeByAge.toggle()
                    if colorizeByAge {
                        colorizeByGender = false // 同時ONを避ける
                        Task { await loadAgeBreakdown() }
                    }
                } label: {
                    Text("年代")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorizeByAge ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundColor(colorizeByAge ? .accentColor : .secondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(colorizeByAge ? Color.accentColor : Color(.systemGray4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("年代で色分け")
                .accessibilityValue(colorizeByAge ? "オン" : "オフ")
                if totalVotes > 0 {
                    Text("\(totalVotes)票").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("まだ投票はありません").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(options) { opt in
                if colorizeByAge, let ab = ageBreakdown[opt.id] {
                    ResultBarStackedAge(
                        label: opt.displayText,
                        teens: ab.teens,
                        twenties: ab.twenties,
                        thirties: ab.thirties,
                        forties: ab.forties,
                        fiftiesPlus: ab.fiftiesPlus
                    )
                } else if colorizeByGender, let gb = genderBreakdown[opt.id] {
                    ResultBarStacked(label: opt.displayText, male: gb.male, female: gb.female, other: gb.other)
                } else {
                    let count = countFor(optionID: opt.id)
                    ResultBar(label: opt.displayText, count: count, total: totalVotes)
                }
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
                    // 簡易アバター（絵文字優先、なければプレースホルダー）
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 34, height: 34)
                        if let e = ownerEmoji, !e.isEmpty {
                            Text(e)
                                .font(.system(size: 20))
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

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
                    Text(displayCategory(poll.category))
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
        
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showReport = true
                    } label: {
                        Label("通報する", systemImage: "exclamationmark.bubble")
                    }
                    if let owner = poll.owner_id, owner == AppConfig.devUserID {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("投稿を削除", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(
                pollID: poll.id,
                reporterUserID: dummyUserID,
                onDone: {
                    showReportThanks = true
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("ご協力ありがとうございます", isPresented: $showReportThanks) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("不適切な投稿の通報を受け付けました。確認までしばらくお待ちください。")
        }
        .alert("この投稿を削除しますか？", isPresented: $showDeleteConfirm) {
            Button("キャンセル", role: .cancel) {}
            Button(deleting ? "削除中…" : "削除", role: .destructive) {
                Task {
                    deleting = true
                    defer { deleting = false }
                    do {
                        try await PollAPI.softDeleteOwnPoll(pollID: poll.id)
                        NotificationCenter.default.post(
                            name: .pollDidDelete,
                            object: nil,
                            userInfo: [AppNotificationKey.pollID: poll.id]
                        )
                        dismiss()
                    } catch {
                        deleteError = "削除に失敗しました。時間を置いてお試しください。"
                    }
                }
            }
        } message: {
            Text("削除すると他のユーザーからは見えなくなります（通報・ログは保持されます）。")
        }
        .alert("エラー", isPresented: .constant(deleteError != nil)) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .task {
            await loadOptions()

            // 投稿者の絵文字を取得（あれば表示に反映）
            if let owner = poll.owner_id {
                do {
                    let emoji = try await PollAPI.fetchOwnerEmoji(userID: owner)
                    await MainActor.run { self.ownerEmoji = emoji }
                } catch {
                    // 絵文字取得失敗は致命的ではないので握りつぶす
                }
            }

            do {
                let map = try await PollAPI.fetchUserVoteDetailMap(pollIDs: [poll.id], userID: dummyUserID)
                if let detail = map[poll.id] {
                    await MainActor.run {
                        self.voted = true
                        self.myChoiceLabel = detail.1
                    }
                } else {
                    await MainActor.run {
                        self.voted = false
                        self.myChoiceLabel = nil
                    }
                }
                if await MainActor.run(body: { self.voted }) {
                    await loadResults()
                    await MainActor.run { self.showResults = true }
                } else {
                    await MainActor.run { self.showResults = false }
                }
            } catch {
                await MainActor.run { self.showResults = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pollDidVote)) { note in
            Task {
                if let id = note.userInfo?[AppNotificationKey.pollID] as? UUID, id == poll.id {
                    await MainActor.run { self.voted = true }
                    if let optID = note.userInfo?[AppNotificationKey.optionID] as? UUID,
                       let chosen = options.first(where: { $0.id == optID }) {
                        await MainActor.run { self.myChoiceLabel = chosen.displayText }
                    }
                    await loadResults()
                    if colorizeByGender { await loadGenderBreakdown() }
                    if colorizeByAge { await loadAgeBreakdown() }
                    await MainActor.run { self.showResults = true }
                }
            }
        }
        .onChange(of: colorizeByGender) { on in
            Task {
                if on { await loadGenderBreakdown() }
            }
        }
        .onChange(of: colorizeByAge) { on in
            Task {
                if on { await loadAgeBreakdown() }
            }
        }
    }

    // MARK: - Actions

    @MainActor private func loadOptions() async {
        loading = true
        defer { loading = false }
        do {
            options = try await PollAPI.fetchOptions(for: poll.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor private func loadResults() async {
        do {
            let rows = try await PollAPI.fetchResults(
                for: poll.id,
                gender: nil,
                ageMin: nil,
                ageMax: nil
            )
            results = rows
            totalVotes = rows.reduce(0) { $0 + $1.count }
        } catch {
            // 結果は無くても UI は出す
            results = []
            totalVotes = 0
        }
    }

    @MainActor private func submitVote() async {
        guard let optionID = selectedOptionID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await PollAPI.submitVote(pollID: poll.id, optionID: optionID, userID: dummyUserID)
            voted = true
            if let chosen = options.first(where: { $0.id == optionID }) {
                myChoiceLabel = chosen.displayText
            }
            await loadResults()
            if colorizeByGender { await loadGenderBreakdown() }
            if colorizeByAge { await loadAgeBreakdown() }
            showResults = true
            NotificationCenter.default.post(
                name: .pollDidVote,
                object: nil,
                userInfo: [
                    AppNotificationKey.pollID: poll.id,
                    AppNotificationKey.optionID: optionID,
                    AppNotificationKey.userID: dummyUserID
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor private func loadGenderBreakdown() async {
        do {
            let list = try await PollAPI.fetchGenderBreakdown(for: poll.id, ageMin: nil, ageMax: nil)
            genderBreakdown = Dictionary(uniqueKeysWithValues: list.map { ($0.option_id, $0) })
        } catch {
            genderBreakdown = [:]
        }
    }

    @MainActor private func loadAgeBreakdown() async {
        do {
            // 年代色分けは「全バケットの可視化」という意味合いなので、
            // 年齢フィルタは適用せず、必要に応じて性別フィルタだけ反映
            let list = try await PollAPI.fetchAgeBreakdown(for: poll.id, gender: genderFilter.apiValue)
            ageBreakdown = Dictionary(uniqueKeysWithValues: list.map { ($0.option_id, $0) })
        } catch {
            ageBreakdown = [:]
        }
    }

    private func countFor(optionID: UUID) -> Int {
        results.first(where: { $0.option_id == optionID })?.count ?? 0
    }
}
