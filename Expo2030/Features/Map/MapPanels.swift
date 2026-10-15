import SwiftUI

/// Chooses the bottom panel for the current `MapModel.panel`.
struct MapPanelSwitch: View {
    @Bindable var model: MapModel

    var body: some View {
        switch model.panel {
        case .none:
            EmptyView()
        case .locationPeek:
            MapPanelContainer { LocationPeekPanel(model: model) }
        case .filterResults(let results):
            MapPanelContainer { FilterResultsPanel(model: model, results: results) }
        case .categoryPeek(let category):
            MapPanelContainer { CategoryPeekPanel(model: model, category: category) }
        case .booth(let booth, let expanded):
            if booth.crowd == .high {
                MapPanelContainer { CrowdedBoothPanel(model: model, booth: booth) }
            } else {
                BoothCardPanel(model: model, booth: booth, expanded: expanded)
            }
        case .alternatives(let booth, let alts):
            MapPanelContainer { AlternativesPanel(model: model, booth: booth, alternatives: alts) }
        case .replaceReview(let from, let to):
            MapPanelContainer { ReplaceReviewPanel(model: model, from: from, to: to) }
        case .routeOptions(let target, let routes, let selected):
            MapPanelContainer { RouteOptionsPanel(model: model, target: target, routes: routes, selected: selected) }
        case .navigating:
            TripCardPanel(model: model)
        case .arrived(let booth):
            MapPanelContainer { ArrivalPanel(model: model, booth: booth) }
        case .nextStop(let booth):
            MapPanelContainer { NextStopPanel(model: model, booth: booth) }
        case .friends:
            MapPanelContainer { FriendsPanel(model: model) }
        case .friendCard(let friend):
            MapPanelContainer { FriendCardPanel(model: model, friend: friend) }
        case .meetingPicker(let editing):
            MapPanelContainer { MeetingPickerPanel(model: model, editing: editing) }
        case .meetingReview(let point):
            MapPanelContainer { MeetingReviewPanel(model: model, point: point) }
        case .meetingStatus:
            MapPanelContainer { MeetingStatusPanel(model: model) }
        case .meetingArrived(let point):
            MapPanelContainer { MeetingArrivedPanel(model: model, point: point) }
        }
    }
}

// MARK: - 1.1 «أنتِ الآن»

struct LocationPeekPanel: View {
    @Bindable var model: MapModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.permissions.canShowLocation, let loc = model.location {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.accuracy == .low || model.permissions.isApproximate ? "موقعك التقريبي" : "أنتِ الآن")
                            .textStyle(.caption).foregroundStyle(Color.textSecondary)
                        Text(loc.areaTitle).textStyle(.headline).foregroundStyle(Color.textPrimary)
                        Text(loc.areaDetail).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    Button { model.recenter() } label: {
                        Icon(.navigate, size: 22, color: .locationBlue)
                            .frame(width: 48, height: 48)
                            .background(Color.locationBlueBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("توسيط الخريطة على موقعي")
                }
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("ازدحام المعرض الآن:").textStyle(.caption).foregroundStyle(Color.textSecondary)
                        CrowdBadge(level: model.hallCrowd, style: .mapCompact)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    let low = loc.accuracy == .low || model.permissions.isApproximate
                    HStack(spacing: 4) {
                        Text(low ? "دقة الموقع منخفضة" : "دقة الموقع عالية").textStyle(.caption)
                        Icon(low ? .warning : .check, size: 13)
                    }
                    .foregroundStyle(low ? Color.statusWarning : Color.crowdLow)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(low ? Color.statusWarningBg : Color.crowdLowBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                }
            } else {
                LocationUnavailableCard(status: model.permissions.status) {
                    model.sheet = .locationExplainer
                }
            }
            Button("إغلاق") { model.panel = .none }
                .appButton(.text, height: 36)
        }
    }

}

// MARK: - 1.5 filter results

struct FilterResultsPanel: View {
    @Bindable var model: MapModel
    let results: [SearchResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if results.isEmpty {
                VStack(spacing: 8) {
                    Text("لا توجد نتائج مطابقة للتصفية الحالية").textStyle(.headline)
                    Text("لم نجد مواقع تطابق الفلاتر المختارة. جرّبي تقليلها أو إعادة تعيينها لعرض كل المواقع.")
                        .textStyle(.footnote).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
                    Button("إعادة تعيين") { model.clearFilter() }.appButton(.mint, height: 44)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Text("\(ArabicDigits.format(results.count)) \(results.count <= 10 ? "أجنحة" : "جناحًا") تطابق اختيارك")
                        .textStyle(.headline)
                    Spacer()
                    Text("الأقرب أولًا").textStyle(.caption).foregroundStyle(Color.textSecondary)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { r in
                            MapResultRow(booth: r.booth, subtitle: r.booth.codeTitle, compact: true) { model.select(r.booth) }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }
}

/// Search / filter result row (1.2, 1.3, 1.5): cube tile, name + subtitle, distance chip + crowd badge.
struct MapResultRow: View {
    let booth: Booth
    var subtitle: String
    var compact = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(booth.category == .government ? .flag : .cube, size: 18, color: .brandPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(booth.name).textStyle(.headline).foregroundStyle(Color.textPrimary)
                    Text(subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 3) {
                        Text(compact ? "\(ArabicDigits.format(booth.distanceMeters)) م"
                                     : "\(ArabicDigits.format(booth.walkMinutes)) د، \(ArabicDigits.format(booth.distanceMeters)) م")
                            .textStyle(.caption).foregroundStyle(Color.textSecondary)
                        Icon(.walk, size: 12, color: .textSecondary)
                    }
                    CrowdBadge(level: booth.crowd, style: .mapCompact)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 1.6 category peek

struct CategoryPeekPanel: View {
    @Bindable var model: MapModel
    let category: PlaceCategory

    var body: some View {
        let list = model.booths.filter { category == .pavilions || $0.category == category }
            .sorted { $0.distanceMeters < $1.distanceMeters }
        HStack(spacing: 12) {
            Icon(category == .government ? .flag : (category == .services ? .info : .cube), size: 22, color: .brandPrimary)
                .frame(width: 44, height: 44)
                .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ArabicDigits.format(list.count)) \(category.title)").textStyle(.headline)
                if let first = list.first {
                    Text("الأقرب: \(first.name)، \(ArabicDigits.minutes(first.walkMinutes))")
                        .textStyle(.footnote).foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("عرض القائمة") {
                model.panel = .filterResults(list.map { SearchResult(booth: $0, subtitle: $0.codeTitle) })
            }
            .appButton(.mint, height: 40, fullWidth: false)
        }
        .padding(.bottom, 6)
    }
}

// MARK: - 2.1 / 2.2 booth card

struct BoothCardPanel: View {
    @Bindable var model: MapModel
    let booth: Booth
    var expanded: Bool
    @State private var loading = false
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                BoothPhoto(booth: booth).frame(height: expanded ? 150 : 120).clipped()
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(booth.isOpen ? Color.crowdLow : Color.statusError).frame(width: 8, height: 8)
                        Text(booth.statusText).textStyle(.caption).foregroundStyle(Color.textPrimary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.92), in: Capsule())
                    Spacer()
                    Button { model.panel = .none } label: {
                        Icon(.close, size: 16, color: .textPrimary)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.92), in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("إغلاق")
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    BoothLogo(text: booth.logoText)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(booth.name).textStyle(.title2).foregroundStyle(Color.textPrimary)
                        Text(booth.codeTitle).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CrowdBadge(level: booth.crowd, style: .map)
                }
                if expanded {
                    expandedDetails
                } else {
                    Text("\(ArabicDigits.minutes(booth.walkMinutes)) مشيًا  |  \(ArabicDigits.format(booth.distanceMeters)) م  |  \(booth.entrance)")
                        .textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    updatedLine
                }
                HStack(spacing: 10) {
                    Button {
                        Task {
                            loading = true
                            defer { loading = false }
                            do { try await model.showRoutes(to: booth) }
                            catch { toast.show((error as? AppError)?.message ?? "تعذّر حساب الطريق الآن", icon: .warning, iconColor: .statusError) }
                        }
                    } label: {
                        ButtonLabel(title: "الاتجاهات", icon: .navigate)
                    }
                    .appButton(.primary, isLoading: loading)
                    Button(expanded ? "عرض أقل" : "التفاصيل") {
                        model.panel = .booth(booth, expanded: !expanded)
                    }
                    .appButton(.mint)
                    .frame(width: 140)
                }
            }
            .padding(16)
        }
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .shadow(color: .shadowTint.opacity(0.16), radius: 18, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var updatedLine: some View {
        HStack(spacing: 4) {
            Icon(.refresh, size: 13, color: .crowdLow)
            Text("محدّث قبل \(booth.updatedMinutesAgo == 2 ? "دقيقتين" : ArabicDigits.minutes(booth.updatedMinutesAgo))")
                .textStyle(.caption).foregroundStyle(Color.crowdLow)
        }
    }

    private var expandedDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !booth.summary.isEmpty {
                    Text(booth.summary).textStyle(.subhead).foregroundStyle(Color.textSecondary)
                }
                Text("معلومات الجناح").textStyle(.headline)
                VStack(spacing: 0) {
                    infoRow("التصنيف ورقم الجناح", booth.codeTitle)
                    infoRow("حالة الازدحام", nil) { CrowdBadge(level: booth.crowd, style: .mapCompact) }
                    infoRow("المسافة من موقعك", "\(ArabicDigits.format(booth.distanceMeters)) م")
                    infoRow("وقت الوصول مشيًا", ArabicDigits.minutes(booth.walkMinutes))
                    infoRow("الوصول والمدخل", "\(ArabicDigits.minutes(booth.walkMinutes)) مشيًا  |  \(ArabicDigits.format(booth.distanceMeters)) م  |  \(booth.entrance)")
                    infoRow("الحالة الآن", booth.statusText)
                    infoRow("آخر تحديث", nil) { updatedLine }
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private func infoRow(_ label: String, _ value: String?) -> some View {
        infoRow(label, value) { EmptyView() }
    }

    private func infoRow<Trailing: View>(_ label: String, _ value: String?, @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(label).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                Spacer(minLength: 12)
                if let value {
                    Text(value).textStyle(.footnote).foregroundStyle(Color.textPrimary).multilineTextAlignment(.trailing)
                }
                trailing()
            }
            .padding(.vertical, 9)
            Divider()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 3.1 crowded booth

struct CrowdedBoothPanel: View {
    @Bindable var model: MapModel
    let booth: Booth
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                BoothLogo(text: booth.logoText, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(booth.name).textStyle(.title3)
                    Text(booth.codeTitle).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { model.panel = .none } label: {
                    Icon(.close, size: 16, color: .textSecondary).frame(width: 32, height: 32)
                        .background(Color.bgSurface2, in: Circle()).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("إغلاق")
            }
            HStack(spacing: 8) {
                CrowdBadge(level: booth.crowd, style: .map)
                StatChip(icon: .walk, text: ArabicDigits.minutes(booth.walkMinutes))
                StatChip(icon: .route, text: "\(ArabicDigits.format(booth.distanceMeters)) م")
                Spacer()
            }
            HStack(spacing: 8) {
                Icon(.busy, size: 18, color: .crowdHigh)
                Text("مزدحم الآن، الانتظار المتوقع \(ArabicDigits.minutes(booth.waitMinutes ?? 15)) تقريبًا")
                    .textStyle(.footnote).foregroundStyle(Color.crowdHigh)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.crowdHighBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                Task { loading = true; try? await model.showRoutes(to: booth); loading = false }
            } label: { ButtonLabel(title: "الاتجاهات", icon: .navigate) }
            .appButton(.primary, isLoading: loading)
        }
    }
}

// MARK: - 3.2 alternatives

struct AlternativesPanel: View {
    @Bindable var model: MapModel
    let booth: Booth
    let alternatives: [BoothAlternative]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MapPanelHeader(title: "وجهتك مزدحمة الآن، هل تريد زيارة جناح آخر ؟",
                           subtitle: "\(booth.name.components(separatedBy: " ").first ?? booth.name): مزدحم، انتظار \(ArabicDigits.minutes(booth.waitMinutes ?? 15)) تقريبًا",
                           icon: .busy, iconTint: .crowdHigh, iconBackground: .crowdHighBg)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(alternatives) { alt in
                        Button { model.panel = .replaceReview(from: booth, to: alt.booth) } label: {
                            AlternativeBoothRow(alternative: alt)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 360)
            Button("متابعة إلى \(booth.name.components(separatedBy: " ").first ?? booth.name)") {
                Task { try? await model.routeIgnoringCrowd(to: booth) }
            }
            .appButton(.text, height: 44)
        }
    }
}

struct AlternativeBoothRow: View {
    let alternative: BoothAlternative
    var body: some View {
        let b = alternative.booth
        HStack(spacing: 12) {
            BoothPhoto(booth: b).frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(b.name).textStyle(.headline).foregroundStyle(Color.textPrimary)
                    NumberBadge(number: alternative.rank).scaleEffect(0.85)
                }
                HStack(spacing: 6) {
                    Text("\(b.category.singularTitle)، \(ArabicDigits.format(b.walkMinutes)) د، \(ArabicDigits.format(b.distanceMeters)) م")
                        .textStyle(.caption).foregroundStyle(Color.textSecondary)
                    CrowdBadge(level: b.crowd, style: .mapCompact)
                }
                HStack(spacing: 4) {
                    Icon(.sparkles, size: 12, color: .brandPrimary)
                    Text(alternative.reason).textStyle(.caption).foregroundStyle(Color.brandPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.borderDefault, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint("يعرض مراجعة الاستبدال")
    }
}

// MARK: - 3.3 replace review

struct ReplaceReviewPanel: View {
    @Bindable var model: MapModel
    let from: Booth
    let to: Booth
    @State private var loading = false
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        let shortFrom = from.name.components(separatedBy: " ").first ?? from.name
        VStack(alignment: .leading, spacing: 12) {
            MapPanelHeader(title: "استبدال الوجهة؟", onButton: { model.panel = .alternatives(from, model.lastAlternatives) })
            destinationCard(label: "الوجهة الحالية", booth: from, subtitle: from.codeTitle, highlighted: false)
            Image(systemName: "arrow.down").foregroundStyle(Color.textTertiary).frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            destinationCard(label: "الوجهة المقترحة", booth: to,
                            subtitle: "\(to.codeTitle)\(to.interestReason.map { "، \($0)" } ?? "")", highlighted: true)
            HStack(spacing: 6) {
                Icon(.star, size: 14, color: .textSecondary)
                Text("سنحفظ \(shortFrom) في «لاحقًا» لتعودي إليه عندما يهدأ").textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: 10) {
                Button("تأكيد الاستبدال") {
                    Task {
                        loading = true
                        defer { loading = false }
                        do {
                            try await model.replace(from, with: to)
                            toast.show("تم تغيير الوجهة إلى \(to.name)، وحُفظ \(shortFrom) في «لاحقًا»")
                        } catch {
                            toast.show("تعذّر تغيير الوجهة الآن", icon: .warning, iconColor: .statusError)
                        }
                    }
                }
                .appButton(.primary, isLoading: loading)
                Button("رجوع") { model.panel = .alternatives(from, model.lastAlternatives) }
                    .appButton(.mint).frame(width: 110)
            }
            Button("متابعة الوجهة الأصلية (\(shortFrom))") {
                Task { try? await model.routeIgnoringCrowd(to: from) }
            }
            .appButton(.text, height: 40)
        }
    }

    private func destinationCard(label: String, booth: Booth, subtitle: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).textStyle(.caption).foregroundStyle(highlighted ? Color.brandPrimary : Color.textSecondary)
            HStack(spacing: 12) {
                BoothPhoto(booth: booth).frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(booth.name).textStyle(.headline)
                    Text(subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                CrowdBadge(level: booth.crowd, style: .mapCompact)
                StatChip(icon: .walk, text: ArabicDigits.minutes(booth.walkMinutes))
                StatChip(icon: .route, text: "\(ArabicDigits.format(booth.distanceMeters)) م")
                Spacer()
            }
        }
        .padding(12)
        .background(highlighted ? Color.brandMint.opacity(0.5) : Color.bgSurface2,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.brandPrimary, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 2.3 / 2.5 / 3.4 / 3.10 route options

struct RouteOptionsPanel: View {
    @Bindable var model: MapModel
    let target: NavigationTarget
    let routes: [Route]
    let selected: RouteKind

    var body: some View {
        let current = routes.first { $0.kind == selected } ?? routes[0]
        VStack(alignment: .leading, spacing: 12) {
            MapPanelHeader(title: titleText, subtitle: subtitleText(current)) {
                if case .booth(let b) = target { model.panel = .booth(b, expanded: false) } else { model.panel = .none }
            }
            if routes.count == 1 {
                singleRoute(current)
            } else {
                ForEach(routes) { route in
                    RouteOptionRow(route: route, isSelected: route.kind == selected) { model.selectRoute(route.kind) }
                }
            }
            Button("بدء التوجيه") { model.startNavigation(target: target, route: current) }
                .appButton(.primary)
            if routes.count > 1 {
                Button {
                    model.sheet = .compareRoutes(target: target, routes: routes, current: selected)
                } label: {
                    HStack(spacing: 6) {
                        Icon(.compare, size: 18, color: .brandPrimary)
                        Text(selected == .fastest ? "قارن الطريق البديل" : "قارن مع الطريق الأسرع")
                            .textStyle(.button).foregroundStyle(Color.brandPrimary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var titleText: String {
        switch target {
        case .booth(let b): "إلى \(b.name)، جناح \(b.id)"
        default: "إلى \(target.title)"
        }
    }

    private func subtitleText(_ r: Route) -> String {
        var s = "الوصول المتوقع \(ArabicDigits.time(r.arrival))"
        if case .booth(let b) = target, b.crowd == .high, let w = b.waitMinutes {
            s += "، الانتظار \(ArabicDigits.format(w)) د تقريبًا"
        }
        return s
    }

    private func singleRoute(_ r: Route) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isCrowdedTarget ? "الطريق الأسرع" : "الأسرع والأهدأ").textStyle(.headline)
                HStack(spacing: 8) {
                    CrowdBadge(level: r.crowdOnRoute == .high && !isCrowdedTarget ? .medium : (isCrowdedTarget ? .high : .low), style: .mapCompact)
                    StatChip(icon: .walk, text: ArabicDigits.minutes(r.minutes))
                    StatChip(icon: .route, text: "\(ArabicDigits.format(r.meters)) م")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ArabicDigits.minutes(r.minutes)).textStyle(.title3)
        }
        .padding(14)
        .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.brandPrimary, lineWidth: 1.5))
    }

    private var isCrowdedTarget: Bool {
        if case .booth(let b) = target { return b.crowd == .high }
        return false
    }
}

// MARK: - 3.9 next stop

struct NextStopPanel: View {
    @Bindable var model: MapModel
    let booth: Booth

    var body: some View {
        let route = model.previewRoutes.first
        VStack(alignment: .leading, spacing: 12) {
            MapPanelHeader(eyebrow: "المحطة التالية في خطتك", title: "\(booth.name)، جناح \(booth.id)") {
                model.panel = .none
            }
            HStack(spacing: 8) {
                CrowdBadge(level: booth.crowd, style: .map)
                StatChip(icon: .walk, text: ArabicDigits.minutes(booth.walkMinutes))
                StatChip(icon: .route, text: "\(ArabicDigits.format(booth.distanceMeters)) م")
                if let route { Text("الوصول \(ArabicDigits.time(route.arrival.adding(minutes: 5)))").textStyle(.caption).foregroundStyle(Color.textSecondary) }
                Spacer()
            }
            HStack(spacing: 8) {
                Icon(.route, size: 16, color: .textSecondary)
                Text("طريق مستقيم عبر الممر الغربي، مرورًا بتوال").textStyle(.footnote).foregroundStyle(Color.textPrimary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button("بدء التوجيه") {
                Task {
                    if let route { model.startNavigation(target: .booth(booth), route: route) }
                    else { try? await model.startNavigation(to: .booth(booth)) }
                }
            }
            .appButton(.primary)
            Button("اختيار محطة أخرى") { model.isSearching = true }
                .appButton(.mint)
        }
    }
}

// MARK: - 3.5 – 3.8 arrival

struct ArrivalPanel: View {
    @Bindable var model: MapModel
    let booth: Booth
    @State private var confirming = false
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        let visit = model.visits[booth.id]
        let confirmed = visit?.confirmed == true
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Icon(.flag, size: 24, color: .white)
                    .frame(width: 56, height: 56)
                    .background(Color.brandPrimary, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(confirmed ? "تمت الزيارة" : "وصلتِ إلى وجهتك").textStyle(.title2)
                    Text(arrivalLine).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { model.panel = .none } label: {
                    Icon(.close, size: 16, color: .textSecondary).frame(width: 32, height: 32)
                        .background(Color.bgSurface2, in: Circle()).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("إغلاق")
            }
            .accessibilityElement(children: .contain)

            HStack(spacing: 4) {
                if confirmed { Icon(.check, size: 13, color: .statusSuccess) }
                Text(confirmed ? "تمت الزيارة" : "لم تُؤكَّد الزيارة بعد").textStyle(.caption)
                    .foregroundStyle(confirmed ? Color.statusSuccess : Color.textSecondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(confirmed ? Color.statusSuccessBg : Color.bgSurface2, in: Capsule())

            if let note = visit?.note, !note.isEmpty {
                Button { model.sheet = .note(booth) } label: {
                    HStack(spacing: 8) {
                        Icon(.note, size: 16, color: .textSecondary)
                        Text(note).textStyle(.footnote).foregroundStyle(Color.textPrimary).lineLimit(2)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تعديل الملاحظة: \(note)")
            }

            HStack(spacing: 8) {
                arrivalButton(title: confirmed ? "تمت الزيارة" : "أكد زيارتي", icon: .check, primary: !confirmed, loading: confirming) {
                    guard !confirmed else { return }
                    Task {
                        confirming = true
                        defer { confirming = false }
                        do {
                            try await model.confirmVisit(booth)
                            toast.show("تم تأكيد زيارتك")
                        } catch {
                            toast.show((error as? AppError)?.message ?? "تعذّر تأكيد الزيارة", icon: .warning, iconColor: .statusError)
                        }
                    }
                }
                arrivalButton(title: visit?.note == nil ? "أضف ملاحظة" : "تعديل الملاحظة", icon: .note, primary: false) {
                    model.sheet = .note(booth)
                }
                arrivalButton(title: "المحطة التالية", icon: .chevronLeft, primary: false) {
                    Task { await model.showNextStop() }
                }
            }
            Text("تأكيد الزيارة اختياري ويُحفظ في «رحلتي» فقط.")
                .textStyle(.caption).foregroundStyle(Color.textTertiary)
        }
    }

    private var arrivalLine: String {
        let time = model.arrivalTimes[booth.id].map { "، الوصول \(ArabicDigits.time($0))" } ?? ""
        return "\(booth.name)، جناح \(booth.id)\(time)"
    }

    private func arrivalButton(title: String, icon: AppIcon, primary: Bool, loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if loading { ProgressView().tint(primary ? .white : .brandPrimary) }
                else { Icon(icon, size: 20, color: primary ? .white : .brandPrimary) }
                Text(title).textStyle(.caption).foregroundStyle(primary ? Color.white : Color.brandPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(primary ? Color.brandPrimary : Color.brandMint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

