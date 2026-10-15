import SwiftUI

// MARK: - 6.1 / 6.6 / 6.9 meeting-point picker

struct MeetingPickerPanel: View {
    @Bindable var model: MapModel
    var editing: Bool

    var body: some View {
        let friendName = model.meetingFriend?.name ?? "صديقتك"
        VStack(alignment: .leading, spacing: 12) {
            MapPanelHeader(title: title, buttonIcon: .close, buttonLabel: "إغلاق") { model.panel = .none }
            if case .declined(let p, let reason) = model.meeting {
                VStack(alignment: .leading, spacing: 4) {
                    Text("رفضت \(friendName) \(p.name.components(separatedBy: " – ").first ?? p.name)")
                        .textStyle(.subheadStrong).foregroundStyle(Color.statusWarning)
                    Text(reason).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.statusWarningBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if model.meetingPoints.isEmpty {
                LoadingStateView(title: "نبحث عن نقاط مناسبة بينكما…")
            }
            ForEach(Array(model.meetingPoints.enumerated()), id: \.element.id) { index, point in
                let declined = isDeclined(point)
                Button { Task { await model.review(point) } } label: {
                    HStack(spacing: 12) {
                        Icon(.users, size: 20, color: declined ? .textTertiary : .brandPrimary)
                            .frame(width: 40, height: 40)
                            .background(declined ? Color.bgSurface2 : Color.brandMint,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.name).textStyle(.headline)
                                .foregroundStyle(declined ? Color.textTertiary : Color.textPrimary)
                            Text(subtitle(point, index: index, friendName: friendName, declined: declined))
                                .textStyle(.caption).foregroundStyle(declined ? Color.statusWarning : Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Icon(.chevronLeft, size: 16, color: .textTertiary)
                    }
                    .padding(12)
                    .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.borderDefault, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(declined)
            }
            if editing, let current = model.agreedPoint {
                HStack(spacing: 6) {
                    Icon(.info, size: 14, color: .textTertiary)
                    Text("تبقى \(current.name.components(separatedBy: " – ").last ?? current.name) هي النقطة المتفق عليها حتى توافق \(friendName) على التعديل")
                        .textStyle(.caption).foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    private var title: String {
        if editing { return "تعديل نقطة الالتقاء" }
        if case .declined = model.meeting { return "اختاري نقطة أخرى" }
        return "اقتراح نقطة التقاء"
    }

    private func isDeclined(_ p: MeetingPoint) -> Bool {
        if case .declined(let d, _) = model.meeting { return d.id == p.id }
        return false
    }

    private func subtitle(_ p: MeetingPoint, index: Int, friendName: String, declined: Bool) -> String {
        if declined { return "تم الرفض" }
        let times = "أنتِ \(ArabicDigits.format(p.myMinutes)) د، \(friendName) \(ArabicDigits.format(p.friendMinutes)) د"
        return index == 0 && !editing ? "\(times)، في المنتصف بينكما" : times
    }
}

// MARK: - 6.2 review

struct MeetingReviewPanel: View {
    @Bindable var model: MapModel
    let point: MeetingPoint
    @State private var sending = false
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        let friend = model.meetingFriend
        VStack(alignment: .leading, spacing: 12) {
            MapPanelHeader(title: "مراجعة الاقتراح") {
                Task { await model.openMeetingPicker(editing: model.agreedPoint != nil) }
            }
            HStack(spacing: 12) {
                Icon(.users, size: 22, color: .white)
                    .frame(width: 44, height: 44)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.name).textStyle(.headline)
                    Text(point.subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                etaTile(name: "أنتِ", avatar: "avatar-sadeem", minutes: point.myMinutes, meters: point.myMeters,
                        arrival: point.myArrival, color: .brandPrimary)
                etaTile(name: friend?.name ?? "صديقتك", avatar: friend?.avatar, minutes: point.friendMinutes,
                        meters: point.friendMeters, arrival: point.friendArrival, color: .statusWarning)
            }
            HStack(spacing: 16) {
                legend("طريقك", color: .locationBlue, dashed: false)
                legend("طريق \(friend?.name ?? "صديقتك")", color: .crowdHigh, dashed: true)
                Spacer()
            }
            Button("أرسل الاقتراح ل\(friend?.name ?? "صديقتك")") {
                Task {
                    sending = true
                    defer { sending = false }
                    do { try await model.propose(point) }
                    catch { toast.show((error as? AppError)?.message ?? "تعذّر إرسال الاقتراح", icon: .warning, iconColor: .statusError) }
                }
            }
            .appButton(.primary, isLoading: sending)
            Text("سيصل الاقتراح ل\(friend?.name ?? "صديقتك")، ولها القبول أو الرفض.")
                .textStyle(.caption).foregroundStyle(Color.textTertiary)
        }
    }

    private func etaTile(name: String, avatar: String?, minutes: Int, meters: Int, arrival: TimeOfDay, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                AvatarView(name: name, image: avatar, width: 26, height: 26, radius: 13)
                Text(name).textStyle(.subheadStrong)
            }
            Text(ArabicDigits.minutes(minutes)).textStyle(.title3).foregroundStyle(color)
            Text("\(ArabicDigits.format(meters)) م، الوصول \(ArabicDigits.time(arrival))")
                .textStyle(.caption).foregroundStyle(Color.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func legend(_ text: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text).textStyle(.caption).foregroundStyle(Color.textSecondary)
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 3, dash: dashed ? [5, 3] : []))
                .frame(width: 22, height: 3)
        }
    }
}

// MARK: - 6.3 / 6.5 / 6.10 / 6.11 status

struct MeetingStatusPanel: View {
    @Bindable var model: MapModel
    @State private var routing = false

    var body: some View {
        let friendName = model.meetingFriend?.name ?? "صديقتك"
        VStack(alignment: .leading, spacing: 12) {
            switch model.meeting {
            case .waiting(let p):
                statusHeader(icon: .clock, tint: .statusInfo, bg: .statusInfoBg,
                             title: "بانتظار رد \(friendName)…", subtitle: "اقترحتِ \(p.name)", spinning: true)
            case .pendingEdit(let current, let proposed):
                statusHeader(icon: .clock, tint: .statusInfo, bg: .statusInfoBg,
                             title: "بانتظار موافقة \(friendName) على التعديل", subtitle: "المقترحة: \(proposed.name)", spinning: true)
                StatusBanner(text: "النقطة الحالية ما زالت: \(current.name)", tone: .neutral, icon: .info)
                Button("التوجيه إلى النقطة الحالية") { go(current) }.appButton(.primary, isLoading: routing)
            case .agreed(let p):
                statusHeader(icon: .check, tint: .statusSuccess, bg: .statusSuccessBg,
                             title: "وافقت \(friendName)، نلتقي عند \(p.name.components(separatedBy: " – ").last ?? p.name)",
                             subtitle: "\(p.name)، الوصول \(ArabicDigits.time(p.myArrival))")
                HStack(spacing: 8) {
                    StatChip(icon: .walk, text: "\(friendName): \(ArabicDigits.format(p.friendMinutes)) د، في الطريق")
                    StatChip(icon: .walk, text: "أنتِ: \(ArabicDigits.format(p.myMinutes)) د")
                    Spacer()
                }
                Button("ابدأ التوجيه") { go(p) }.appButton(.primary, isLoading: routing)
                Button("تعديل النقطة") { Task { await model.openMeetingPicker(editing: true) } }.appButton(.mint)
            case .declined:
                MeetingPickerPanel(model: model, editing: false)
            case .none:
                EmptyStateView(icon: .users, title: "لا يوجد اقتراح نشط")
            }
            if showsClose {
                Button("إغلاق") { model.panel = .none }.appButton(.text, height: 40)
            }
        }
    }

    private var showsClose: Bool {
        switch model.meeting {
        case .agreed, .declined: false
        default: true
        }
    }

    private func go(_ p: MeetingPoint) {
        Task {
            routing = true
            defer { routing = false }
            try? await model.startNavigation(to: .meetingPoint(p))
        }
    }

    private func statusHeader(icon: AppIcon, tint: Color, bg: Color, title: String, subtitle: String, spinning: Bool = false) -> some View {
        HStack(spacing: 12) {
            Group {
                if spinning { ProgressView().tint(tint) } else { Icon(icon, size: 22, color: tint) }
            }
            .frame(width: 44, height: 44)
            .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.headline)
                Text(subtitle).textStyle(.footnote).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 6.8 arrived

struct MeetingArrivedPanel: View {
    @Bindable var model: MapModel
    let point: MeetingPoint

    var body: some View {
        let friendName = model.meetingFriend?.name ?? "صديقتك"
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Icon(.flag, size: 24, color: .white)
                    .frame(width: 56, height: 56)
                    .background(Color.brandPrimary, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("وصلتِ إلى نقطة الالتقاء").textStyle(.title2)
                    Text(arrivedLine(friendName)).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            StatChip(icon: .walk, text: "\(friendName): أقل من دقيقة")
            Button("تم") {
                model.meeting = .none
                model.panel = .none
            }
            .appButton(.primary)
        }
    }

    private func arrivedLine(_ name: String) -> String {
        guard let p = model.meetingFriend?.location?.point else { return "أبلغنا \(name) بوصولك" }
        let meters = Int((hypot(p.x - point.point.x, p.y - point.point.y) * MapCamera.metersPerPoint / 10).rounded()) * 10
        return "أبلغنا \(name) بوصولك، وهي على بعد \(ArabicDigits.format(max(10, meters))) م"
    }
}
