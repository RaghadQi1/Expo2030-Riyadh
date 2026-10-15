import Foundation

/// How a visitor gets in (tags «دخول حر · بلا حجز» / «يتطلب حجزًا خارجيًا»).
enum EntryPolicy: Codable, Hashable {
    case free
    case externalBooking(provider: String, url: URL)
    case limitedSeats(Int)

    var title: String {
        switch self {
        case .free: "دخول حر · بلا حجز"
        case .externalBooking: "يتطلب حجزًا خارجيًا"
        case .limitedSeats: "مقاعد محدودة · بلا حجز مسبق"
        }
    }
}

/// Accessibility line «موثّق من الجهة المشاركة». `nil` availability = «لا تتوفر معلومة».
struct AccessibilityFeature: Codable, Hashable, Identifiable {
    var id: String { title }
    var title: String
    var available: Bool?
}

/// Live operational values shown with a Data Freshness line (crowd, wait time, seats).
struct LiveStatus: Codable, Hashable {
    var crowd: CrowdLevel
    var waitMinutes: Int?
    var seatsLeft: Int?
    var updatedMinutesAgo: Int
    var source: String = "الجهة المشاركة"

    /// Stale > 10 min turns warning (Figma "Data Freshness" rule).
    var isStale: Bool { updatedMinutesAgo > 10 }

    var freshnessText: String {
        let ago: String
        switch updatedMinutesAgo {
        case 0: ago = "محدّث الآن"
        case 1: ago = "محدّث قبل دقيقة"
        case 2: ago = "محدّث قبل دقيقتين"
        case 3...10: ago = "محدّث قبل \(updatedMinutesAgo) دقائق"
        default: ago = "محدّث قبل \(updatedMinutesAgo) دقيقة"
        }
        return "\(ago) · المصدر: \(source)"
    }
}

/// A pavilion / experience on the Expo site (Discover, Pavilion Detail, Plan).
struct Pavilion: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var organization: String
    var experienceType: String          // «تجربة تفاعلية»، «جلسة حوارية»…
    var axis: ExpoAxis
    var photo: String                   // asset name
    var hours: String                   // «مفتوح 10ص – 11م»
    var durationMinutes: Int
    var languages: String               // «العربية · English»
    var entrance: String                // «مدخل B الشمالي»
    var entranceNote: String            // «المدخل الصحيح: B الشمالي (المدخل A مخصص للخروج)»
    var entry: EntryPolicy
    var live: LiveStatus
    var walkMinutes: Int?               // only when location is available
    var distanceMeters: Int?
    var about: String
    var highlights: [String]
    var attendanceRules: [String]
    var accessibility: [AccessibilityFeature]
    var accessibilityVerifiedOn: String
    /// Position on the illustrative site map (Map/Base 640 × 1000).
    var sitePoint: MapPoint
    var shortName: String               // label on the site map
    var recommendationReason: String?   // «لأنك اخترت «التقنيات» و«تجارب عملية»»
}

enum EventStatus: Codable, Hashable {
    case upcoming, startingSoon(minutes: Int), bookingRequired
}

/// A timed session / show / workshop inside a pavilion (Event Detail 08.07, Discover «فعاليات قادمة»).
struct ExpoEvent: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var pavilionId: String
    var venue: String                   // «قاعة 3 · جناح صحة الإنسان»
    var organizer: String
    var format: String                  // «جلسة حوارية»
    var axis: ExpoAxis
    var photo: String
    var start: TimeOfDay
    var durationMinutes: Int
    var language: String
    var entry: EntryPolicy
    var capacity: Int?
    var about: String
    var takeaways: [String]
    var attendanceRules: [String]
    var accessibility: [AccessibilityFeature]
    var entranceNote: String
    var isPinnedInPlan: Bool = false
    var accessibilityVerifiedOn: String = ""

    var end: TimeOfDay { start.adding(minutes: durationMinutes) }
    var timeRange: String { "\(start.arabic12h.replacingOccurrences(of: " م", with: "")) – \(end.arabic12h)" }
}

/// Category tabs on the map and search (الكل · الأجنحة · جهات حكومية · شركات · خدمات).
enum PlaceCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case all, pavilions, government, companies, services
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "الكل"
        case .pavilions: "الأجنحة"
        case .government: "جهات حكومية"
        case .companies: "شركات"
        case .services: "خدمات"
        }
    }
}

/// Discover home payload (08.01).
struct DiscoverFeed: Codable, Hashable {
    var nextStop: NextStopSummary?
    var axes: [ExpoAxis]
    var opportunities: [Pavilion]       // «فرصة تناسبك الآن» / «الأجنحة والفعاليات»
    var upcomingEvents: [ExpoEvent]
    var recommendations: [Pavilion]     // «تجارب متنوعة قد تهمك»
}

/// «رحلتك اليوم · 1 من 4 — التالي: جناح الذكاء والمستقبل» card on Discover.
struct NextStopSummary: Codable, Hashable {
    var progressText: String            // «رحلتك اليوم · 1 من 4»
    var progress: Double
    var title: String                   // «التالي: جناح الذكاء والمستقبل»
    var subtitle: String                // «ورشة الروبوتات»
    var startsAt: String                // «تبدأ 3:30 م»
    var pavilionId: String
}

struct SearchFilters: Codable, Hashable {
    var category: PlaceCategory = .all
    var axes: Set<ExpoAxis> = []
    var maxDistanceMeters: Int? = nil   // أي / 300 / 200 / 100
    var openNow = false
    var lowCrowdOnly = false

    var isEmpty: Bool { category == .all && axes.isEmpty && maxDistanceMeters == nil && !openNow && !lowCrowdOnly }
}
