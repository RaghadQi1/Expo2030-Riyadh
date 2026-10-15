import SwiftUI

/// 09.01 «مقارنة الخطط» — two plan options side by side, timeline of the selected one, adopt CTA.
struct PlanCompareView: View {
    let options: [PlanOption]
    var onAdopt: (PlanOption) async -> Void

    @State private var selectedId: String = ""
    @State private var isAdopting = false

    /// RTL: first column is drawn on the right — the recommended option sits on the right as in Figma.
    private var ordered: [PlanOption] {
        options.sorted { $0.isRecommended && !$1.isRecommended }
    }

    private var selected: PlanOption? { options.first { $0.id == selectedId } ?? ordered.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(options.count == 1 ? "خطتك المقترحة" : "خطط تناسبك")
                    .textStyle(.title1).foregroundStyle(Color.textPrimary)

                HStack(alignment: .top, spacing: 10) {
                    ForEach(ordered) { option in
                        PlanOptionColumn(option: option, isSelected: option.id == selected?.id) {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedId = option.id }
                        }
                    }
                }

                if let selected {
                    Text("الخط الزمني — \(selected.name)").textStyle(.title3).foregroundStyle(Color.textPrimary)
                        .padding(.top, 4)
                    VStack(spacing: 12) {
                        ForEach(Array(selected.steps.enumerated()), id: \.element.id) { index, step in
                            PlanTimelineRow(step: previewStep(step), isLast: index == selected.steps.count - 1)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.bgCanvas)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    guard let selected else { return }
                    isAdopting = true
                    Task {
                        await onAdopt(selected)
                        isAdopting = false
                    }
                } label: {
                    Text("اعتمد «\(selected?.name ?? "")»")
                }
                .appButton(.primary, isLoading: isAdopting)
                .disabled(selected == nil || isAdopting)
            }
        }
        .appNavigationChrome(title: "مقارنة الخطط")
        .navigationBarBackButtonHidden(false)
        .onAppear { if selectedId.isEmpty { selectedId = ordered.first?.id ?? "" } }
    }

    /// In the comparison nothing is "live" yet.
    private func previewStep(_ step: PlanStep) -> PlanStep {
        var s = step
        s.liveState = .upcoming
        return s
    }
}

private struct PlanOptionColumn: View {
    let option: PlanOption
    let isSelected: Bool
    var onSelect: () -> Void

    private func walkingMinutes(for option: PlanOption) -> Int {
        let fallback = max(0, option.steps.filter { step in
            if case .experience = step.kind { return true }
            return false
        }.count - 1) * 5
        return max(option.metrics.walkingMinutes, fallback)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                Text(option.name).textStyle(.headline).foregroundStyle(Color.textPrimary)
                MetricLine(label: "المحطات", value: option.metrics.stopsText)
                MetricLine(label: "وقت المشي", value: "\(walkingMinutes(for: option)) د")
                MetricLine(label: "وقت التجارب", value: "\(option.metrics.experienceMinutes) د")
                MetricLine(label: "انتظار تقديري", value: option.metrics.estimatedWaitText)
                MetricLine(label: "الأولوية", value: option.metrics.priorityText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(isSelected ? Color.brandMint : Color.bgSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? Color.brandPrimary : Color.borderDefault, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("اختيار هذه الخطة")
    }
}
