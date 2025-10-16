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
    // 追加: description の補完用
    @State private var descriptionText: String? = nil

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

    // 地域で色分け表示
    @State private var colorizeByRegion = false
    @State private var regionBreakdown: [UUID: PollAPI.RegionBreakdown] = [:]

    // 切替モード（将来: 性別/年代/地域のUIトグルで使用）
    private enum BreakdownMode { case gender, age, region }
    @State private var breakdownMode: BreakdownMode = .gender

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
    @State private var ownerName: String?

    // Delete state
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var deleteError: String?

    // Lock state (disable interactions when voted / submitting / loading)
    private var isLocked: Bool { voted || isSubmitting || loading }

    // 作成者テキスト（Auth導入前は devUserID と一致したら「あなた」）
    private var ownerText: String {
        if let owner = poll.owner_id, owner == AppConfig.currentUserID {
            return "作成者: あなた"
        } else if let name = ownerName, !name.isEmpty {
            return "作成者: \(name)"
        } else if poll.owner_id != nil {
            return "作成者: 匿名"
        } else {
            return "作成者: －"
        }
    }

    private func relativeFromAbsoluteString(_ absolute: String) -> String {
        let abs = DateFormatter()
        abs.locale = Locale(identifier: "ja_JP")
        abs.dateFormat = "yyyy/MM/dd HH:mm"
        guard let date = abs.date(from: absolute) else { return absolute }
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "ja_JP")
        rel.unitsStyle = .full
        return rel.localizedString(for: date, relativeTo: Date())
    }

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

    // MARK: - Small subviews
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
                    let ratio = total > 0 ? Double(count) / Double(total) : 0
                    let percentText = ratio.formatted(.percent.precision(.fractionLength(0)))
                    Text("\(percentText) (\(count)票)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        let grandTotal: Int
        var total: Int { male + female + other }

        private let maleColor = Color.blue
        private let femaleColor = Color.pink
        private let otherColor = Color.purple

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                    Spacer()
                    let ratio = grandTotal > 0 ? Double(total) / Double(grandTotal) : 0
                    let percentText = ratio.formatted(.percent.precision(.fractionLength(0)))
                    Text("\(percentText) (\(total)票)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

                if total > 0 {
                    ZStack {
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(spacing: 12) {
                                let denom = total > 0 ? Double(total) : 0
                                let malePctText   = (denom > 0 ? Double(male)   / denom : 0).formatted(.percent.precision(.fractionLength(0)))
                                let femalePctText = (denom > 0 ? Double(female) / denom : 0).formatted(.percent.precision(.fractionLength(0)))
                                let otherPctText  = (denom > 0 ? Double(other)  / denom : 0).formatted(.percent.precision(.fractionLength(0)))

                                Label("男性 \(malePctText) (\(male)票)", systemImage: "square.fill")
                                    .foregroundStyle(maleColor).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("女性 \(femalePctText) (\(female)票)", systemImage: "square.fill")
                                    .foregroundStyle(femaleColor).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("その他 \(otherPctText) (\(other)票)", systemImage: "square.fill")
                                    .foregroundStyle(otherColor).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.trailing, 24)
                            .padding(.bottom, 6)
                        }

                        LinearGradient(
                            colors: [Color.clear, Color(.systemBackground)],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 40)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.top, 2)
                }
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
        let grandTotal: Int
        var total: Int { teens + twenties + thirties + forties + fiftiesPlus }

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
                    let ratio = grandTotal > 0 ? Double(total) / Double(grandTotal) : 0
                    let percentText = ratio.formatted(.percent.precision(.fractionLength(0)))
                    Text("\(percentText) (\(total)票)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

                if total > 0 {
                    ZStack {
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(spacing: 12) {
                                let denom = total > 0 ? Double(total) : 0
                                let p10 = (denom > 0 ? Double(teens) / denom : 0).formatted(.percent.precision(.fractionLength(0)))
                                let p20 = (denom > 0 ? Double(twenties) / denom : 0).formatted(.percent.precision(.fractionLength(0)))
                                let p30 = (denom > 0 ? Double(thirties) / denom : 0).formatted(.percent.precision(.fractionLength(0)))
                                let p40 = (denom > 0 ? Double(forties) / denom : 0).formatted(.percent.precision(.fractionLength(0)))
                                let p50 = (denom > 0 ? Double(fiftiesPlus) / denom : 0).formatted(.percent.precision(.fractionLength(0)))

                                Label("10代 \(p10) (\(teens)票)", systemImage: "square.fill")
                                    .foregroundStyle(c10).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("20代 \(p20) (\(twenties)票)", systemImage: "square.fill")
                                    .foregroundStyle(c20).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("30代 \(p30) (\(thirties)票)", systemImage: "square.fill")
                                    .foregroundStyle(c30).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("40代 \(p40) (\(forties)票)", systemImage: "square.fill")
                                    .foregroundStyle(c40).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("50代以上 \(p50) (\(fiftiesPlus)票)", systemImage: "square.fill")
                                    .foregroundStyle(c50).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.trailing, 24)
                            .padding(.bottom, 6)
                        }

                        LinearGradient(
                            colors: [Color.clear, Color(.systemBackground)],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 40)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // 地域用の積み上げバー＋凡例
    private struct ResultBarStackedRegion: View {
        let label: String
        let hokkaido: Int
        let tohoku: Int
        let kanto: Int
        let chubu: Int
        let kinki: Int
        let chugoku: Int
        let shikoku: Int
        let kyushu_okinawa: Int
        let overseas: Int
        let grandTotal: Int

        var total: Int { hokkaido + tohoku + kanto + chubu + kinki + chugoku + shikoku + kyushu_okinawa + overseas }

        // 任意の配色（被らないよう視認性重視）
        private let cHokkaido = Color.mint
        private let cTohoku = Color.blue
        private let cKanto = Color.indigo
        private let cChubu = Color.teal
        private let cKinki = Color.green
        private let cChugoku = Color.orange
        private let cShikoku = Color.cyan
        private let cKyushu = Color.pink
        private let cOverseas = Color.purple

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                    Spacer()
                    let ratio = grandTotal > 0 ? Double(total) / Double(grandTotal) : 0
                    let percentText = ratio.formatted(.percent.precision(.fractionLength(0)))
                    Text("\(percentText) (\(total)票)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    let seg: (Int) -> CGFloat = { v in
                        total > 0 ? w * CGFloat(v) / CGFloat(total) : 0
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5))
                        HStack(spacing: 0) {
                            Capsule().fill(cHokkaido).frame(width: seg(hokkaido))
                            Capsule().fill(cTohoku).frame(width: seg(tohoku))
                            Capsule().fill(cKanto).frame(width: seg(kanto))
                            Capsule().fill(cChubu).frame(width: seg(chubu))
                            Capsule().fill(cKinki).frame(width: seg(kinki))
                            Capsule().fill(cChugoku).frame(width: seg(chugoku))
                            Capsule().fill(cShikoku).frame(width: seg(shikoku))
                            Capsule().fill(cKyushu).frame(width: seg(kyushu_okinawa))
                            Capsule().fill(cOverseas).frame(width: seg(overseas))
                        }
                    }
                }
                .frame(height: 8)

                if total > 0 {
                    ZStack {
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(spacing: 12) {
                                let denom = total > 0 ? Double(total) : 0
                                let pct: (Int) -> String = { v in
                                    (denom > 0 ? Double(v) / denom : 0).formatted(.percent.precision(.fractionLength(0)))
                                }
                                Label("北海道 \(pct(hokkaido)) (\(hokkaido)票)", systemImage: "square.fill")
                                    .foregroundStyle(cHokkaido).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("東北 \(pct(tohoku)) (\(tohoku)票)", systemImage: "square.fill")
                                    .foregroundStyle(cTohoku).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("関東 \(pct(kanto)) (\(kanto)票)", systemImage: "square.fill")
                                    .foregroundStyle(cKanto).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("中部 \(pct(chubu)) (\(chubu)票)", systemImage: "square.fill")
                                    .foregroundStyle(cChubu).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("近畿 \(pct(kinki)) (\(kinki)票)", systemImage: "square.fill")
                                    .foregroundStyle(cKinki).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("中国 \(pct(chugoku)) (\(chugoku)票)", systemImage: "square.fill")
                                    .foregroundStyle(cChugoku).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("四国 \(pct(shikoku)) (\(shikoku)票)", systemImage: "square.fill")
                                    .foregroundStyle(cShikoku).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("九州・沖縄 \(pct(kyushu_okinawa)) (\(kyushu_okinawa)票)", systemImage: "square.fill")
                                    .foregroundStyle(cKyushu).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Label("海外 \(pct(overseas)) (\(overseas)票)", systemImage: "square.fill")
                                    .foregroundStyle(cOverseas).font(.caption2)
                                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.trailing, 24)
                            .padding(.bottom, 6)
                        }

                        LinearGradient(
                            colors: [Color.clear, Color(.systemBackground)],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 40)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var resultsPlaceholder: some View {
        ZStack(alignment: .topLeading) {
            Text("投票すると結果が見えます")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.top, 12)
            Text("結果")
                .font(.title3).bold()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

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

    @ViewBuilder
    private var ageFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("年代")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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

    // 背景（description）セクション
    @ViewBuilder
    private var backgroundSection: some View {
        if let desc = (descriptionText ?? poll.description),
           !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("質問したきっかけ")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(desc)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("結果").font(.title3).bold()
                Spacer()
                Button {
                    colorizeByGender.toggle()
                    if colorizeByGender {
                        colorizeByAge = false
                        colorizeByRegion = false
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
                        colorizeByGender = false
                        colorizeByRegion = false
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

                Button {
                    colorizeByRegion.toggle()
                    if colorizeByRegion {
                        colorizeByGender = false
                        colorizeByAge = false
                        Task { await loadRegionBreakdown() }
                    }
                } label: {
                    Text("地域")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorizeByRegion ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundColor(colorizeByRegion ? .accentColor : .secondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(colorizeByRegion ? Color.accentColor : Color(.systemGray4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("地域で色分け")
                .accessibilityValue(colorizeByRegion ? "オン" : "オフ")

                if totalVotes > 0 {
                    Text("総投票数：\(totalVotes)票").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("まだ投票はありません").font(.footnote).foregroundStyle(.secondary)
                }
            }

            // ForEach の中で複数型を返さないよう、モード別に ForEach を分割
            if colorizeByRegion {
                ForEach(options) { opt in
                    let rb = regionBreakdown[opt.id]
                    ResultBarStackedRegion(
                        label: opt.displayText,
                        hokkaido: rb?.hokkaido ?? 0,
                        tohoku: rb?.tohoku ?? 0,
                        kanto: rb?.kanto ?? 0,
                        chubu: rb?.chubu ?? 0,
                        kinki: rb?.kinki ?? 0,
                        chugoku: rb?.chugoku ?? 0,
                        shikoku: rb?.shikoku ?? 0,
                        kyushu_okinawa: rb?.kyushu_okinawa ?? 0,
                        overseas: rb?.overseas ?? 0,
                        grandTotal: totalVotes
                    )
                }
            } else if colorizeByAge {
                ForEach(options) { opt in
                    let ab = ageBreakdown[opt.id]
                    ResultBarStackedAge(
                        label: opt.displayText,
                        teens: ab?.teens ?? 0,
                        twenties: ab?.twenties ?? 0,
                        thirties: ab?.thirties ?? 0,
                        forties: ab?.forties ?? 0,
                        fiftiesPlus: ab?.fiftiesPlus ?? 0,
                        grandTotal: totalVotes
                    )
                }
            } else if colorizeByGender {
                ForEach(options) { opt in
                    let gb = genderBreakdown[opt.id]
                    ResultBarStacked(
                        label: opt.displayText,
                        male: gb?.male ?? 0,
                        female: gb?.female ?? 0,
                        other: gb?.other ?? 0,
                        grandTotal: totalVotes
                    )
                }
            } else {
                ForEach(options) { opt in
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

    // MARK: - Header section (extracted from body)
    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
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

            Text(displayCategory(poll.category))
                .font(.caption2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
        }
    }

    // MARK: - Bindings / extracted views to reduce type-check cost
    private var isDeleteErrorPresented: Binding<Bool> {
        Binding<Bool>(
            get: { deleteError != nil },
            set: { newValue in
                if !newValue { deleteError = nil }
            }
        )
    }

    @ViewBuilder
    private var reportSheetView: some View {
        ReportSheet(
            pollID: poll.id,
            reporterUserID: AppConfig.currentUserID,
            onDone: {
                showReportThanks = true
            }
        )
        .presentationDetents([.medium, .large])
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(role: .destructive) {
                    showReport = true
                } label: {
                    Label("通報する", systemImage: "exclamationmark.bubble")
                }
                if let owner = poll.owner_id, owner == AppConfig.currentUserID {
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

    var body: some View {
        // ScrollView とその直後の軽い修飾子までをいったん確定
        let base = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                Text(poll.question)
                    .font(.title2).bold()
                    .multilineTextAlignment(.leading)

                // 背景（description）カード
                backgroundSection

                HStack(spacing: 12) {
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
        .toolbar { toolbarContent }

        // 重い修飾子を段階的に適用（型推論の分割）
        let withSheet = base.sheet(isPresented: $showReport) { reportSheetView }

        let withThanks = withSheet.alert("ご協力ありがとうございます", isPresented: $showReportThanks) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("不適切な投稿の通報を受け付けました。確認までしばらくお待ちください。")
        }

        let withDelete = withThanks.alert("この投稿を削除しますか？", isPresented: $showDeleteConfirm) {
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

        let withError = withDelete.alert("エラー", isPresented: isDeleteErrorPresented) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }

        // 最終的なイベント系修飾子を適用して返す
        return withError
            .task {
                await loadOptions()

                // 追加: description が空なら詳細を取得して補完
                if (poll.description == nil || poll.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) {
                    do {
                        if let detailed = try await PollAPI.fetchPollDetail(id: poll.id),
                           let desc = detailed.description,
                           !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            descriptionText = desc
                        }
                    } catch {
                        // 補完失敗は無視（背景は非表示のまま）
                    }
                }

                if let owner = poll.owner_id {
                    do {
                        async let emojiTask = PollAPI.fetchOwnerEmoji(userID: owner)
                        async let profileTask = PollAPI.fetchProfile(userID: owner)
                        let (emoji, profile) = try await (emojiTask, profileTask)
                        await MainActor.run {
                            self.ownerEmoji = emoji
                            if let name = profile?.username, !name.isEmpty {
                                self.ownerName = name
                            }
                        }
                    } catch {
                    }
                }

                do {
                    let map = try await PollAPI.fetchUserVoteDetailMap(pollIDs: [poll.id], userID: AppConfig.currentUserID)
                    if let detail = map[poll.id] {
                        await MainActor.run {
                            self.voted = true
                            self.myChoiceLabel = detail.1
                            self.selectedOptionID = detail.0
                        }
                    } else {
                        await MainActor.run {
                            self.voted = false
                            self.myChoiceLabel = nil
                            self.selectedOptionID = nil
                        }
                    }
                    let hasVoted = await MainActor.run { self.voted }
                    if hasVoted {
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
                            await MainActor.run {
                                self.selectedOptionID = optID
                                self.myChoiceLabel = chosen.displayText
                            }
                        }
                        await loadResults()
                        if colorizeByGender { await loadGenderBreakdown() }
                        if colorizeByAge { await loadAgeBreakdown() }
                        if colorizeByRegion { await loadRegionBreakdown() }
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
            .onChange(of: colorizeByRegion) { on in
                Task {
                    if on { await loadRegionBreakdown() }
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
            results = []
            totalVotes = 0
        }
    }

    @MainActor private func submitVote() async {
        guard let optionID = selectedOptionID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await PollAPI.submitVote(pollID: poll.id, optionID: optionID, userID: AppConfig.currentUserID)
            voted = true
            if let chosen = options.first(where: { $0.id == optionID }) {
                myChoiceLabel = chosen.displayText
            }
            await loadResults()
            if colorizeByGender { await loadGenderBreakdown() }
            if colorizeByAge { await loadAgeBreakdown() }
            if colorizeByRegion { await loadRegionBreakdown() }
            showResults = true
            NotificationCenter.default.post(
                name: .pollDidVote,
                object: nil,
                userInfo: [
                    AppNotificationKey.pollID: poll.id,
                    AppNotificationKey.optionID: optionID,
                    AppNotificationKey.userID: AppConfig.currentUserID
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
            let list = try await PollAPI.fetchAgeBreakdown(for: poll.id, gender: genderFilter.apiValue)
            ageBreakdown = Dictionary(uniqueKeysWithValues: list.map { ($0.option_id, $0) })
        } catch {
            ageBreakdown = [:]
        }
    }

    @MainActor private func loadRegionBreakdown() async {
        do {
            let list = try await PollAPI.fetchRegionBreakdown(for: poll.id)

            // RPCの結果を辞書化
            var dict = Dictionary(uniqueKeysWithValues: list.map { ($0.option_id, $0) })

            // 返ってこなかった option には 0 で補完
            for opt in options {
                if dict[opt.id] == nil {
                    dict[opt.id] = PollAPI.RegionBreakdown(
                        option_id: opt.id,
                        hokkaido: 0, tohoku: 0, kanto: 0, chubu: 0,
                        kinki: 0, chugoku: 0, shikoku: 0, kyushu_okinawa: 0, overseas: 0
                    )
                }
            }

            regionBreakdown = dict
        } catch {
            regionBreakdown = [:]
        }
    }

    private func countFor(optionID: UUID) -> Int {
        results.first(where: { $0.option_id == optionID })?.count ?? 0
    }
}
