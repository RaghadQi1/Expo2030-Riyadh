import Foundation

/// Demo plans from 09.01 / 09.02 / 09.05 / 09.07 – 09.09. Replace with `POST /plans/generate`, `GET /plans/current`.
enum MockPlans {
    // MARK: Timeline «تجارب أكثر» (09.01 / 09.02)

    static let moreExperiencesSteps: [PlanStep] = [
        PlanStep(id: "s1", time: TimeOfDay(15, 30), kind: .walk(minutes: 4, via: "من البوابة الشمالية"),
                 title: "مشي 4 د · من البوابة الشمالية"),
        PlanStep(id: "s2", time: TimeOfDay(15, 34), kind: .experience(placeId: "p1-ai-future"),
                 title: "جناح الذكاء والمستقبل", subtitle: "20 د · دخول حر · مدخل B", liveState: .active),
        PlanStep(id: "s3", time: TimeOfDay(15, 54), kind: .walk(minutes: 6, via: "عبر الممر المركزي"),
                 title: "مشي 6 د · عبر الممر المركزي"),
        PlanStep(id: "s4", time: TimeOfDay(16, 0), kind: .experience(placeId: "e-city-2050"),
                 title: "عرض «مدينة 2050» · المدن الذكية", subtitle: "20 د · يبدأ 4:00 م"),
        PlanStep(id: "s5", time: TimeOfDay(16, 20), kind: .wait(walkMinutes: 5, waitMinutes: 5),
                 title: "مشي 5 د + انتظار تقديري ~5 د"),
        PlanStep(id: "s6", time: TimeOfDay(16, 30), kind: .experience(placeId: "e-robot-workshop"),
                 title: "ورشة «ابنِ روبوتك الأول»", subtitle: "45 د · مختبر الروبوتات · مقاعد محدودة", isPriority: true),
        PlanStep(id: "s7", time: TimeOfDay(17, 15), kind: .walk(minutes: 3, via: nil), title: "مشي 3 د"),
        PlanStep(id: "s8", time: TimeOfDay(17, 18), kind: .experience(placeId: "p4-space"),
                 title: "جناح الفضاء والاستكشاف", subtitle: "12 د · زيارة قصيرة"),
    ]

    static let deeperSteps: [PlanStep] = [
        PlanStep(id: "d1", time: TimeOfDay(15, 30), kind: .walk(minutes: 4, via: "من البوابة الشمالية"),
                 title: "مشي 4 د · من البوابة الشمالية"),
        PlanStep(id: "d2", time: TimeOfDay(15, 34), kind: .experience(placeId: "p1-ai-future"),
                 title: "جناح الذكاء والمستقبل", subtitle: "40 د · جولة موسّعة · مدخل B", liveState: .active),
        PlanStep(id: "d3", time: TimeOfDay(16, 14), kind: .rest(minutes: 10), title: "استراحة 10 د · منطقة الجلوس الشمالية"),
        PlanStep(id: "d4", time: TimeOfDay(16, 24), kind: .walk(minutes: 6, via: "عبر الممر المركزي"),
                 title: "مشي 6 د · عبر الممر المركزي"),
        PlanStep(id: "d5", time: TimeOfDay(16, 30), kind: .experience(placeId: "e-robot-workshop"),
                 title: "ورشة «ابنِ روبوتك الأول»", subtitle: "45 د · أسئلة مع المدربين", isPriority: true),
        PlanStep(id: "d6", time: TimeOfDay(17, 15), kind: .experience(placeId: "e-robots-education"),
                 title: "جلسة: الروبوتات في التعليم", subtitle: "15 د · ملخص الجلسة"),
    ]

    static let moreExperiences = PlanOption(
        id: "opt-more", name: "تجارب أكثر",
        metrics: PlanMetrics(stopsText: "4 تجارب", walkingMinutes: 18, experienceMinutes: 97, restMinutes: 0,
                             estimatedWaitText: "~5 د", priorityText: "★ محفوظة 4:30"),
        gains: "تنوّع: ذكاء اصطناعي، مدن ذكية، روبوتات، فضاء",
        tradeoffs: "عمق أقل في كل جناح، ولا استراحة",
        steps: moreExperiencesSteps, isRecommended: true)

    static let deeper = PlanOption(
        id: "opt-deeper", name: "تجربة أعمق",
        metrics: PlanMetrics(stopsText: "2 تجربة + جلسة", walkingMinutes: 10, experienceMinutes: 100, restMinutes: 10,
                             estimatedWaitText: "لا يوجد", priorityText: "★ محفوظة 4:30"),
        gains: "جولة موسّعة وأسئلة مع المدربين، ومشي أقل",
        tradeoffs: "جناحا المدن الذكية والفضاء",
        steps: deeperSteps)

    static let options: [PlanOption] = [deeper, moreExperiences]

    static func plan(from option: PlanOption) -> Plan {
        Plan(id: "plan-\(option.id)", name: option.name, summary: "ساعتان · 3:30–5:30 م",
             steps: option.steps, endsAt: TimeOfDay(17, 30))
    }

    // MARK: Replan (09.05 «تأخرت») — texts from Figma 1:12804

    static func lateProposal(for plan: Plan, minutes: Int = 20) -> ReplanProposal {
        var after = plan
        after.steps = [
            PlanStep(id: "l1", time: TimeOfDay(15, 53), kind: .walk(minutes: 7, via: "من موقعك الحالي"),
                     title: "مشي 7 د · من موقعك الحالي"),
            PlanStep(id: "l2", time: TimeOfDay(16, 0), kind: .experience(placeId: "e-city-2050"),
                     title: "عرض «مدينة 2050» · المدن الذكية", subtitle: "20 د"),
            PlanStep(id: "l3", time: TimeOfDay(16, 30), kind: .experience(placeId: "e-robot-workshop"),
                     title: "ورشة «ابنِ روبوتك الأول»", subtitle: "45 د · مختبر الروبوتات", isPriority: true),
            PlanStep(id: "l4", time: TimeOfDay(17, 18), kind: .experience(placeId: "p1-ai-future"),
                     title: "جناح الذكاء والمستقبل", subtitle: "12 د · نسخة قصيرة",
                     change: .new(reason: "بديل عن جناح الفضاء")),
        ]
        after.endsAt = TimeOfDay(17, 30)
        return ReplanProposal(
            reason: .late(minutes: minutes),
            diff: [
                PlanDiffItem(kind: .removed, title: "جناح الذكاء والمستقبل", detail: "كان 3:34 م · نقترحه بعد الورشة إن بقي وقت"),
                PlanDiffItem(kind: .changed, title: "عرض «مدينة 2050»", detail: "يبقى 4:00 م · تبدأ منه مباشرة"),
                PlanDiffItem(kind: .kept, title: "ورشة «ابنِ روبوتك الأول» ★", detail: "4:30 م"),
                PlanDiffItem(kind: .changed, title: "جناح الفضاء ← جناح الذكاء والمستقبل", detail: "5:18 م · 12 د"),
            ],
            impact: [
                ImpactMetric(title: "التجارب", before: "97 د", after: "77 د"),
                ImpactMetric(title: "المشي", before: "18 د", after: "15 د"),
                ImpactMetric(title: "انتهاء الخطة", before: "5:30", after: "5:30 م"),
            ],
            after: after)
    }

    /// «أقلل المشي» (assistant 12.03): texts from Figma 1:13601.
    static func shorterWalkProposal(for plan: Plan) -> ReplanProposal {
        var after = plan
        after.steps.removeAll { $0.id == "s7" || $0.id == "s8" }
        if let i = after.steps.firstIndex(where: { $0.id == "s2" }) {
            after.steps[i].subtitle = "30 د · دخول حر · مدخل B"
        }
        return ReplanProposal(
            reason: .addedItem(title: "خطة أقصر مشيًا"),
            diff: [
                PlanDiffItem(kind: .removed, title: "جناح الفضاء والاستكشاف", detail: "كان 5:18 م · ينتقل إلى «محفوظة»"),
                PlanDiffItem(kind: .changed, title: "جناح الذكاء والمستقبل", detail: "20 ← 30 د"),
                PlanDiffItem(kind: .kept, title: "ورشة «ابنِ روبوتك الأول» ★", detail: "4:30 م"),
            ],
            impact: [ImpactMetric(title: "المشي", before: "18", after: "10 د"),
                     ImpactMetric(title: "نهاية الخطة", before: "5:30 م", after: "5:30 م")],
            after: after)
    }

    /// «أحتاج استراحة» — inserts a 15-minute rest before the next experience.
    static func breakProposal(for plan: Plan) -> ReplanProposal {
        var after = plan
        if let idx = after.steps.firstIndex(where: { $0.id == "s3" }) {
            after.steps.insert(PlanStep(id: "rest-\(UUID().uuidString.prefix(4))", time: TimeOfDay(15, 54),
                                        kind: .rest(minutes: 15), title: "استراحة 15 د · منطقة الجلوس الشمالية",
                                        change: .new(reason: "استراحة طلبتها")), at: idx)
        }
        after.endsAt = TimeOfDay(17, 30)
        return ReplanProposal(
            reason: .needBreak,
            diff: [
                PlanDiffItem(kind: .added, title: "استراحة 15 د", detail: "منطقة الجلوس الشمالية · 3:54 م"),
                PlanDiffItem(kind: .removed, title: "جناح الفضاء والاستكشاف", detail: "ينتقل إلى «لاحقًا» في رحلتي"),
                PlanDiffItem(kind: .kept, title: "ورشة «ابنِ روبوتك الأول»", detail: "4:30 م ★"),
            ],
            impact: [
                ImpactMetric(title: "المحطات", before: "4", after: "3"),
                ImpactMetric(title: "الاستراحات", before: "لا توجد", after: "15 د"),
                ImpactMetric(title: "النهاية", before: "5:30 م", after: "5:30 م"),
            ],
            after: after)
    }

    // MARK: Crowded pavilion (09.07) — texts from Figma 1:12973

    static var crowdSituation: CrowdSituation {
        CrowdSituation(
            pavilion: MockCatalog.pavilion("p2-smart-cities")!, title: "المدن الذكية · عرض 4:00 م",
            waitMinutes: 25, freshnessText: "قبل 3 د",
            alternatives: [
                CrowdAlternative(id: "p4-space", pavilion: MockCatalog.pavilion("p4-space")!, rank: 1,
                                 whyText: "يناسب اهتمامك بالتقنيات · عرض القبة 4:05 م", durationMinutes: 20, walkMinutes: 4,
                                 waitText: "انتظار ~5 د", crowd: .low,
                                 planImpact: "تنتهي الخطة 5:30 م كما هي · الورشة محفوظة",
                                 freshnessText: "محدَّث قبل دقيقتين", photo: "photo-space-hall",
                                 arrival: TimeOfDay(16, 5), distanceMeters: 280, previewSubtitle: "عرض القبة 4:05 م · 20 د"),
                CrowdAlternative(id: "p9-digital-arts", pavilion: MockCatalog.pavilion("p9-digital-arts")!, rank: 2,
                                 whyText: "تقنية + ثقافة · تجربة ضوئية تفاعلية", durationMinutes: 15, walkMinutes: 6,
                                 waitText: "انتظار ~10 د", crowd: .medium,
                                 planImpact: "تُختصر المحطة الأخيرة 5 د · الورشة محفوظة",
                                 freshnessText: "محدَّث قبل دقيقتين", photo: "photo-digital-arts",
                                 arrival: TimeOfDay(16, 7), distanceMeters: 420, previewSubtitle: "تجربة ضوئية 4:10 م · 15 د"),
                CrowdAlternative(id: "p6-water", pavilion: MockCatalog.pavilion("p6-water")!, rank: 3,
                                 whyText: "لتغيير الجو نحو الاستدامة · قريب جدًا", durationMinutes: 20, walkMinutes: 3,
                                 waitText: "الانتظار: غير معروف", crowd: .unknown,
                                 planImpact: "+3 د مشي · الورشة محفوظة",
                                 freshnessText: "آخر تحديث قبل 25 دقيقة", isStale: true, photo: "photo-water-oasis",
                                 arrival: TimeOfDay(16, 3), distanceMeters: 210, previewSubtitle: "تجربة تفاعلية 4:03 م · 20 د"),
            ])
    }

    /// Plan after swapping the crowded pavilion for `alternative` (09.08 / 09.09): the alternative takes the
    /// show slot and the original is postponed to 5:18 («المدن الذكية (مؤجَّل)»).
    static func swapped(_ plan: Plan, with alternative: CrowdAlternative) -> Plan {
        var after = plan
        if let idx = after.steps.firstIndex(where: { if case .experience("e-city-2050") = $0.kind { true } else { false } }) {
            after.steps[idx] = PlanStep(
                id: "swap-\(alternative.id)", time: alternative.arrival, kind: .experience(placeId: alternative.pavilion.id),
                title: alternative.pavilion.name,
                subtitle: "بديل عن المدن الذكية · \(alternative.previewSubtitle.components(separatedBy: " · ").first ?? "")",
                change: .new(reason: "بديل عن المدن الذكية"))
        }
        if let last = after.steps.firstIndex(where: { $0.id == "s8" }) {
            after.steps[last] = PlanStep(id: "postponed-city", time: TimeOfDay(17, 18), kind: .experience(placeId: "e-city-2050"),
                                         title: "المدن الذكية (مؤجَّل)", subtitle: "5:18 م · 12 د · قد يبقى مزدحمًا",
                                         change: .new(reason: "أُجّل بسبب الازدحام"))
        }
        after.undoAvailableUntil = Date().addingTimeInterval(10 * 60)
        after.lastChangeDescription = "حُدّثت خطتك · المدن الذكية أُجّلت إلى 5:18 م"
        return after
    }
}
