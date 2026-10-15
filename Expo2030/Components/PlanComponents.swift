import SwiftUI

/// One row of the plan timeline (Figma «Plan/Timeline Step» 1:3127 and «Plan/Live Step»).
/// Visual order (RTL): time column (44 pt, right) · rail (32-pt node + connector) · content (fills).
/// Grammar: انتقال → انتظار تقديري → تجربة → استراحة. Priority = gold outline + ★.
/// Active = #1F3F99 + «الآن». Changed = dashed info outline (before/after previews).
struct PlanTimelineRow: View {
    let step: PlanStep
    var isLast = false
    var onTap: (() -> Void)? = nil

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExperience: Bool {
        if case .experience = step.kind { return true }
        return false
    }

    private var isChanged: Bool {
        if case .new = step.change { return true }
        return false
    }

    private var isActive: Bool { step.liveState == .active }
    private var isCompleted: Bool { step.liveState == .completed }

    var body: some View {
        // RTL: first child is drawn on the right → time · rail · content.
        HStack(alignment: .top, spacing: 12) {
            Text(step.time.shortTime)
                .font(AppFont.latin(13, .regular))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, isExperience || isChanged || isRest ? 12 : 6)
            rail
            content
        }
        .opacity(isCompleted ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if isExperience || isChanged || isRest {
            Button { onTap?() } label: { card }
                .buttonStyle(.plain)
                .disabled(onTap == nil)
        } else {
            Text(step.title)
                .textStyle(.footnote)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
    }

    private var isRest: Bool {
        if case .rest = step.kind { return true }
        return false
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isActive {
                Tag(text: step.badge ?? "الآن", background: .liveActive, icon: .clock)
            } else if case .new(let reason) = step.change {
                Tag(text: "جديد · \(reason)", background: .statusInfo)
            } else if step.isPriority {
                Tag(text: "★ أولوية مثبتة", background: .axisCoop)
            } else if isCompleted {
                Tag(text: "✓ تمت", foreground: .textSecondary, background: .bgSurface2)
            }
            Text(step.title)
                .textStyle(.headline)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.leading)
            if let subtitle = step.subtitle {
                Text(subtitle).textStyle(.footnote).foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: isActive ? Color.liveActive.opacity(0.4) : .clear, radius: 12)
    }

    @ViewBuilder private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if isActive {
            shape.fill(Color.liveActive.opacity(0.07)).background(shape.fill(Color.bgSurface))
        } else if isChanged {
            shape.fill(Color.statusInfoBg)
        } else {
            shape.fill(Color.bgSurface)
        }
    }

    @ViewBuilder private var cardBorder: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if isActive {
            shape.strokeBorder(Color.liveActive, lineWidth: 2)
        } else if isChanged {
            shape.strokeBorder(Color.statusInfo, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else if step.isPriority {
            shape.strokeBorder(Color.axisCoop, lineWidth: 1.5)
        }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(spacing: 4) {
            ZStack {
                if isActive && !reduceMotion {
                    Circle().fill(Color.liveActive.opacity(0.25))
                        .frame(width: 52, height: 52)
                        .scaleEffect(pulse ? 1 : 0.8)
                        .opacity(pulse ? 0.4 : 0.9)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                        .onAppear { pulse = true }
                }
                Circle().fill(nodeColor).frame(width: 32, height: 32)
                Icon(nodeIcon, size: 16, color: nodeIconColor)
            }
            .frame(width: 32, height: 32)
            if !isLast {
                Rectangle().fill(Color.borderDefault)
                    .frame(width: 2, height: isExperience || isChanged ? 40 : 14)
            }
        }
    }

    private var nodeColor: Color {
        if isActive { return .liveActive }
        if isChanged { return .statusInfo }
        if step.isPriority { return .axisCoop }
        if isExperience { return .brandPrimary }
        if isRest { return .brandMint }
        return .bgSurface2
    }

    private var nodeIconColor: Color {
        (isExperience || isChanged || isActive) ? .white : (isRest ? .brandPrimary : .textSecondary)
    }

    private var nodeIcon: AppIcon {
        if isCompleted { return .check }
        if step.isPriority { return .star }
        switch step.kind {
        case .walk: return .walk
        case .wait: return .clock
        case .rest: return .coffee
        case .experience: return .door
        }
    }

    private var accessibilityText: String {
        var parts = [step.time.arabic12h, step.title]
        if let s = step.subtitle { parts.append(s) }
        if isActive { parts.append("الآن") }
        if step.isPriority { parts.append("أولوية مثبتة") }
        if case .new(let reason) = step.change { parts.append("جديد، \(reason)") }
        return parts.joined(separator: "، ")
    }
}

/// Metric block in the plan comparison (label 11M tertiary over value 12M primary).
struct MetricLine: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).textStyle(.caption2).foregroundStyle(Color.textTertiary)
            Text(value).font(AppFont.arabic(12, .medium)).foregroundStyle(Color.textPrimary)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// «ستكسب» / «قد يفوتك» callout used in plan comparison.
struct TradeoffBox: View {
    let title: String
    let text: String
    var tone: BannerTone

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).textStyle(.caption2).foregroundStyle(tone.foreground)
            Text(text).textStyle(.caption).foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tone.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Coloured diff row used in replan (09.05) and assistant (12.03) previews.
struct DiffRow: View {
    enum Style { case replan, assistant }
    let item: PlanDiffItem
    var style: Style = .replan

    private var tone: BannerTone {
        switch item.kind {
        case .removed: .error
        case .changed: .info
        case .kept, .added: .success
        }
    }

    private var label: String {
        if style == .replan { return item.kind.title }
        switch item.kind {
        case .removed: return "حذف"
        case .changed: return "تغيير"
        case .kept: return "محفوظ"
        case .added: return "إضافة"
        }
    }

    private var icon: AppIcon {
        switch item.kind {
        case .removed: .close
        case .changed: .route
        case .kept, .added: .check
        }
    }

    var body: some View {
        // RTL: icon (right) · texts · tag (left)
        HStack(spacing: 10) {
            if style == .replan { Icon(icon, size: 18, color: tone.foreground) }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(AppFont.arabic(12, .medium)).foregroundStyle(Color.textPrimary)
                Text(item.detail).textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Tag(text: label, background: tone.foreground)
        }
        .padding(.horizontal, style == .replan ? 14 : 12)
        .padding(.vertical, 10)
        .background(tone.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// «الأثر» tile: label (11M tertiary) over «before ← after» (12M).
struct ImpactTile: View {
    let metric: ImpactMetric
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.title).textStyle(.caption2).foregroundStyle(Color.textTertiary)
            Text("\(metric.before) ← \(metric.after)").font(AppFont.arabic(12, .medium)).foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
