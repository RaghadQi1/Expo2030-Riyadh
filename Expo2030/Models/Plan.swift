import Foundation

// MARK: - Personalization (07.01 – 07.06)

enum VisitGoal: String, Codable, CaseIterable, Identifiable, Hashable {
    case explore, learn, handsOn, family, networking
    var id: String { rawValue }
    var title: String {
        switch self {
        case .explore: "استكشاف"
        case .learn: "تعلّم"
        case .handsOn: "تجارب عملية"
        case .family: "زيارة عائلية"
        case .networking: "تواصل مهني"
        }
    }
    var subtitle: String {
        switch self {
        case .explore: "أشوف أبرز الأجنحة بدون تخطيط عميق"
        case .learn: "أفهم موضوعًا بعمق من خبراء وعروض"
        case .handsOn: "ورش وتجارب تفاعلية أشارك فيها بنفسي"
        case .family: "أنشطة مناسبة للأطفال ومسارات مريحة"
        case .networking: "أقابل جهات وأشارك ملفي المهني"
        }
    }
}

/// Sub-interests shown when an axis option is expanded (hidden chip rows in 07.02).
enum SubInterests {
    static func of(_ axis: ExpoAxis) -> [String] {
        switch axis {
        case .tech: ["الذكاء الاصطناعي", "التحول الرقمي", "التقنية والابتكار"]
        case .earth: ["البيئة والمناخ", "المياه", "الزراعة", "الطاقة والاستدامة"]
        case .human: ["التعليم", "الصحة", "تنمية المهارات", "جودة الحياة"]
        case .culture: ["الفنون", "التراث", "السياحة والثقافة", "الهوية"]
        case .coop: ["التعاون الدولي", "الشراكات", "الحلول العالمية"]
        }
    }

    /// Option titles in 07.02 differ slightly from the Discover axis names.
    static func optionTitle(_ axis: ExpoAxis) -> String {
        axis == .earth ? "الأرض والاستدامة" : axis.title
    }
}

enum TimeBudget: String, Codable, CaseIterable, Identifiable, Hashable {
    case oneHour, twoHours, halfDay, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .oneHour: "ساعة"
        case .twoHours: "ساعتان"
        case .halfDay: "نصف يوم"
        case .custom: "مدة مخصصة"
        }
    }
    var subtitle: String {
        switch self {
        case .oneHour: "2–3 تجارب قصيرة"
        case .twoHours: "3–5 تجارب مع استراحة"
        case .halfDay: "حوالي 4 ساعات"
        case .custom: "حدّد البداية والنهاية"
        }
    }
}

enum ComfortPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case lessWalking, regularBreaks, stepFree, quietPlaces
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lessWalking: "مشي أقل"
        case .regularBreaks: "استراحات منتظمة"
        case .stepFree: "مسارات بلا درجات"
        case .quietPlaces: "أماكن هادئة"
        }
    }
    var subtitle: String {
        switch self {
        case .lessWalking: "نرتّب المحطات المتقاربة ونقلل التنقل"
        case .regularBreaks: "استراحة قصيرة كل 45–60 دقيقة"
        case .stepFree: "نفضّل المنحدرات والمصاعد عند توفر بياناتها"
        case .quietPlaces: "نتجنب الأماكن الأكثر صخبًا قدر الإمكان"
        }
    }
}

struct PlanPreferences: Codable, Hashable {
    var goals: Set<VisitGoal> = []
    var axes: Set<ExpoAxis> = []
    var subInterests: Set<String> = []
    var time: TimeBudget?
    var customStart: TimeOfDay?
    var customEnd: TimeOfDay?
    var comfort: Set<ComfortPreference> = []
    var mustNotMiss: Set<String> = []   // event ids
}

/// A pinnable experience offered on 07.05 («تجربة ما تبغى تفوتك؟»).
struct PriorityCandidate: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    // Provided by Flask; demo candidates omit these and still decode.
    var startMinutes: Int? = nil
    var endMinutes: Int? = nil
}

// MARK: - Plan timeline

enum PlanStepKind: Codable, Hashable {
    /// انتقال — walking between stops.
    case walk(minutes: Int, via: String?)
    /// انتظار تقديري — only when the source provides it.
    case wait(walkMinutes: Int, waitMinutes: Int)
    /// تجربة — a pavilion visit or an event.
    case experience(placeId: String)
    /// استراحة
    case rest(minutes: Int)
}

/// Live state of an experience (Figma «Plan/Live Step»): Upcoming → Activating → Active → Completed.
enum LiveStepState: String, Codable, Hashable {
    case upcoming, activating, active, completed
}

/// Marks used in before/after previews (09.01, 09.05, 09.08).
enum StepChange: Codable, Hashable {
    case none
    case new(reason: String)            // «جديد · بديل عن المدن الذكية»
}

struct PlanStep: Codable, Hashable, Identifiable {
    var id: String
    var time: TimeOfDay
    var kind: PlanStepKind
    var title: String
    var subtitle: String?
    var isPriority = false
    var liveState: LiveStepState = .upcoming
    var change: StepChange = .none
    /// Friend currently at this stop («سارة · الآن»).
    var badge: String? = nil
}

struct PlanMetrics: Codable, Hashable {
    var stopsText: String               // «4 تجارب»
    var walkingMinutes: Int
    var experienceMinutes: Int
    var restMinutes: Int
    var estimatedWaitText: String       // «~5 د» / «لا يوجد»
    var priorityText: String            // «★ محفوظة 4:30»
}

struct PlanOption: Codable, Hashable, Identifiable {
    var id: String
    var name: String                    // «تجارب أكثر»
    var metrics: PlanMetrics
    var gains: String                   // ستكسب
    var tradeoffs: String               // قد يفوتك
    var steps: [PlanStep]
    var isRecommended = false
}

struct Plan: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var summary: String                 // «ساعتان · 3:30–5:30 م»
    var steps: [PlanStep]
    var endsAt: TimeOfDay
    /// Set after a change so the user can undo for 10 minutes (09.09).
    var undoAvailableUntil: Date?
    var lastChangeDescription: String?

    var experiences: [PlanStep] { steps.filter { if case .experience = $0.kind { true } else { false } } }
}

/// Plan generation progress (07.07).
enum PlanGenerationStage: Int, CaseIterable, Hashable {
    case readingPreferences, walkingTimes, eventTimes, finishing
    var title: String {
        switch self {
        case .readingPreferences: "قراءة اختياراتك"
        case .walkingTimes: "حساب أوقات المشي والاستراحة"
        case .eventTimes: "التحقق من مواعيد الفعاليات"
        case .finishing: "ترتيب المحطات"
        }
    }
}

// MARK: - Changes / replanning

enum ReplanReason: Codable, Hashable {
    case late(minutes: Int)
    case needBreak
    case crowded(placeName: String)
    case addedItem(title: String)

    var bannerText: String {
        switch self {
        case .late(let m): "تأخرت \(m) دقيقة؛ أعاد Gemini ترتيب المحطات حسب وقتك المتبقي."
        case .needBreak: "طلبت استراحة 15 دقيقة، وأُعيد ترتيب المحطات بعدها باستخدام Gemini."
        case .crowded(let name): "السبب: \(name) مزدحم الآن."
        case .addedItem: "أُعيدت جدولة الخطة باستخدام Gemini لإضافة المحطة التي اخترتها."
        }
    }
}

enum DiffKind: String, Codable, Hashable {
    case removed, changed, kept, added
    var title: String {
        switch self {
        case .removed: "أُزيل"
        case .changed: "تغيّر"
        case .kept: "محفوظ"
        case .added: "أُضيف"
        }
    }
}

struct PlanDiffItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: DiffKind
    var title: String
    var detail: String
}

struct ImpactMetric: Codable, Hashable, Identifiable {
    var id: String { title }
    var title: String
    var before: String
    var after: String
}

struct ReplanProposal: Codable, Hashable, Identifiable {
    var id = UUID()
    var reason: ReplanReason
    var diff: [PlanDiffItem]
    var impact: [ImpactMetric]
    var after: Plan
}

/// Ways to resolve adding something that overlaps the plan (Conflict sheet).
struct ConflictOption: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var isSuggested = false
}

struct PlanConflict: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String                   // «تتعارض مع ورشتك المثبتة»
    var message: String
    var options: [ConflictOption]
}

enum AddToPlanResult: Codable, Hashable {
    case added(position: Int, time: TimeOfDay)
    case conflict(PlanConflict)
}

/// Crowded pavilion alternatives (09.07 – 09.09). Figma «Card/Alternative Pavilion»: unknown data says
/// «غير معروف» and never implies calm.
struct CrowdAlternative: Codable, Hashable, Identifiable {
    var id: String
    var pavilion: Pavilion
    var rank: Int
    var whyText: String                 // «يناسب اهتمامك بالتقنيات · عرض القبة 4:05 م»
    var durationMinutes: Int
    var walkMinutes: Int
    var waitText: String                // «انتظار ~5 د» / «الانتظار: غير معروف»
    var crowd: CrowdLevel
    var languages: String = "عربي / English"
    var entryText: String = "دخول حر · بلا حجز"
    var planImpact: String              // «تنتهي الخطة 5:30 م كما هي · الورشة محفوظة»
    var freshnessText: String           // «محدَّث قبل دقيقتين»
    var isStale = false
    var photo: String
    // Preview (09.08)
    var arrival: TimeOfDay
    var distanceMeters: Int
    var previewSubtitle: String         // «عرض القبة 4:05 م · 20 د»
}

struct CrowdSituation: Codable, Hashable {
    var pavilion: Pavilion
    var title: String                   // «المدن الذكية · عرض 4:00 م»
    var waitMinutes: Int
    var freshnessText: String           // «قبل 3 د»
    var alternatives: [CrowdAlternative]
}
