import Foundation

// MARK: - Geometry in hall-map space

/// Rectangle in the exhibition-hall coordinate space («خريطتي/Map/Exhibition», 496 × 1357.8 pt).
struct MapRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var center: MapPoint { MapPoint(x: x + width / 2, y: y + height / 2) }
    func contains(_ p: MapPoint) -> Bool { p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height }
}

enum HallMap {
    /// Size of the hall canvas in Figma points. The base image `map-exhibition-base` uses the same space.
    static let width: Double = 496
    static let height: Double = 1357.8
}

// MARK: - Booths (خريطتي)

/// A booth inside the exhibition hall (PwC, CNTXT, توال…). Not to be confused with site-level `Pavilion`s.
struct Booth: Codable, Hashable, Identifiable {
    var id: String                      // booth code: "A7"
    var name: String                    // «PwC»
    var category: PlaceCategory         // .companies / .government / .services
    var logoText: String                // text inside the 40-pt mint logo tile («pwc», «TW»)
    var summary: String                 // short description in the expanded card
    var frame: MapRect                  // footprint (tap area / highlight)
    var labelPoint: MapPoint            // top-left of the white label pill
    var entrance: String                // «المدخل من الممر الغربي»
    var distanceMeters: Int
    var walkMinutes: Int
    var crowd: CrowdLevel
    var waitMinutes: Int?
    var isOpen: Bool = true
    var isFreeEntry: Bool = true
    var updatedMinutesAgo: Int = 2
    var photo: String?                  // asset name for the card header
    var interestReason: String?         // «قريب منك وضمن اهتماماتك»

    var codeTitle: String { "\(category.singularTitle)، جناح \(id)" }   // «شركات، جناح A7»
    var statusText: String { isOpen ? (isFreeEntry ? "مفتوح الآن، دخول حر" : "مفتوح الآن") : "مغلق الآن" }
}

extension PlaceCategory {
    /// Category label used inside booth subtitles («شركات، جناح A7», «جهات حكومية، جناح B6»).
    var singularTitle: String {
        switch self {
        case .all, .pavilions: "أجنحة"
        case .government: "جهات حكومية"
        case .companies: "شركات"
        case .services: "خدمات"
        }
    }
}

/// Small labels on the hall map (gates, plaza, info point, corridor).
struct MapLandmark: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case gate, label }
    var id: String
    var name: String
    var point: MapPoint                 // top-left of the label pill
    var kind: Kind
}

/// Quick search chips (1.2 «بحث سريع»).
struct QuickService: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var icon: String                    // AppIcon raw value
}

/// Crowd heat overlay drawn on the map.
struct CrowdHotspot: Codable, Hashable, Identifiable {
    var id: String
    var frame: MapRect
    var level: CrowdLevel
    var badgePoint: MapPoint
}

// MARK: - Location

enum LocationAccuracy: String, Codable, Hashable {
    case high, low, unavailable, servicesOff, denied
}

struct UserLocation: Codable, Hashable {
    var point: MapPoint
    var headingDegrees: Double?         // nil = low accuracy (no cone)
    var accuracy: LocationAccuracy
    var areaTitle: String               // «بين منطقة المطاعم ومساحة العمل»
    var areaDetail: String              // «قرب البوابة ٨، تتجهين غربًا»
}

// MARK: - Search & filters (1.2 – 1.6)

struct SearchResult: Codable, Hashable, Identifiable {
    var id: String { booth.id }
    var booth: Booth
    var subtitle: String
}

struct MapFilter: Codable, Hashable {
    var category: PlaceCategory = .all
    var crowd: Set<CrowdLevel> = []
    var maxDistance: Int? = nil         // meters: 100 / 200 / 300 / nil(أي)

    var isEmpty: Bool { category == .all && crowd.isEmpty && maxDistance == nil }

    /// «شركات، هادئ، حتى ٢٠٠ م»
    var summary: String {
        var parts: [String] = []
        if category != .all { parts.append(category.title) }
        for level in CrowdLevel.allCases where crowd.contains(level) { parts.append(level.filterTitle) }
        if let d = maxDistance { parts.append("حتى \(ArabicDigits.format(d)) م") }
        return parts.joined(separator: "، ")
    }
}

extension CrowdLevel {
    /// Labels used by the map filter sheet (Busy / Medium / Quiet).
    var filterTitle: String {
        switch self {
        case .low: "هادئ"
        case .medium: "متوسط"
        case .high: "مزدحم"
        case .unknown: "غير معروف"
        }
    }
}

// MARK: - Routes & turn-by-turn (2.3 – 2.11)

enum RouteKind: String, Codable, Hashable {
    case fastest, quietest
    var title: String {
        switch self {
        case .fastest: "الأسرع"
        case .quietest: "الأقل ازدحامًا"
        }
    }
}

enum TurnDirection: String, Codable, Hashable {
    case left, right, straight
    var icon: String {
        switch self {
        case .left: "chevron-left"
        case .right: "chevron-right"
        case .straight: "navigate"
        }
    }
}

struct NavigationStep: Codable, Hashable, Identifiable {
    var id: String
    var distanceText: String            // «بعد ٢٠ مترًا»
    var instruction: String             // «انعطفي يسارًا»
    var direction: TurnDirection
    var thenText: String                // «ثم بعد ١٨ مترًا انعطفي يمينًا»
    var remainingText: String           // «باقي ٤ دقائق»
    var progressText: String            // «١٨٠ م، الوصول ٩:٤٥ م»
    var alert: String?                  // «ازدحام على الطريق عند ممر قطار الحرمين»
    var alertLevel: CrowdLevel = .medium
    var landmark: String?               // «معلم قريب: مساحة العمل المشترك»
    var position: MapPoint              // where the user is during this step
}

struct Route: Codable, Hashable, Identifiable {
    var id: String
    var kind: RouteKind
    var minutes: Int
    var meters: Int
    var note: String                    // «يمر بممر قطار الحرمين» / «هادئ طوال الطريق»
    var arrival: TimeOfDay
    var crowdOnRoute: CrowdLevel
    var path: [MapPoint]
    var steps: [NavigationStep]
}

/// Destination of a navigation session: a booth, a friend, or a meeting point.
enum NavigationTarget: Codable, Hashable {
    case booth(Booth)
    case friend(Friend)
    case meetingPoint(MeetingPoint)

    var title: String {
        switch self {
        case .booth(let b): b.name
        case .friend(let f): f.name
        case .meetingPoint(let m): m.name
        }
    }

    var point: MapPoint {
        switch self {
        case .booth(let b): b.frame.center
        case .friend(let f): f.location?.point ?? MapPoint(x: 400, y: 540)
        case .meetingPoint(let m): m.point
        }
    }
}

/// «وجهتك مزدحمة الآن» — suggested replacements for a crowded booth (3.2).
struct BoothAlternative: Codable, Hashable, Identifiable {
    var id: String { booth.id }
    var booth: Booth
    var rank: Int
    var reason: String                  // «قريب منك وضمن اهتماماتك»
}

/// Visit status at a booth (3.5 – 3.8).
struct BoothVisit: Codable, Hashable {
    var boothId: String
    var arrivedAt: TimeOfDay
    var confirmed: Bool
    var note: String?
}

// MARK: - Friends & location sharing (4.x, 5.x)

enum LocationShareMode: Hashable, Codable {
    case none
    case staticOnce
    case live(minutes: Int)
    case untilEndOfVisit

    var title: String {
        switch self {
        case .none: "لا أشارك الآن"
        case .staticOnce: "موقع ثابت لمرة واحدة"
        case .live: "موقع مباشر لمدة محدودة"
        case .untilEndOfVisit: "حتى نهاية زيارتي"
        }
    }
}

struct FriendLocation: Codable, Hashable {
    var point: MapPoint
    var areaText: String                // «قرب ساحة الواحة»
    var distanceMeters: Int
    var walkMinutes: Int
    var updatedMinutesAgo: Int
    var updatedAtText: String           // «٩:٢٩ م»

    var isStale: Bool { updatedMinutesAgo >= 10 }
}

struct Friend: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var avatar: String?                 // asset name
    var connectedSince: String          // «متصلتان منذ ٩:٣٥ م»
    /// What I share with this friend.
    var myShare: LocationShareMode
    var myShareEndsAt: TimeOfDay?
    var shareInBackground: Bool
    /// Whether the friend shares her location with me (her decision).
    var sharesWithMe: Bool
    var isVisibleOnMap: Bool
    var location: FriendLocation?
}

struct InviteLink: Codable, Hashable {
    var url: String                     // «dalil.expo/i/sadeem-4F7K»
    var ownerName: String
    var validityText: String            // «صالح لمدة ٢٤ ساعة…»
}

struct IncomingInvite: Codable, Hashable, Identifiable {
    var id: String
    var from: Friend
}

// MARK: - Meeting point (6.x)

struct MeetingPoint: Codable, Hashable, Identifiable {
    var id: String
    var name: String                    // «ساحة الواحة – النافورة»
    var subtitle: String                // «الممر الرئيسي، بين البوابتين ٨ و٧»
    var point: MapPoint
    var myMinutes: Int
    var myMeters: Int
    var friendMinutes: Int
    var friendMeters: Int
    var myArrival: TimeOfDay
    var friendArrival: TimeOfDay
}

enum MeetingState: Codable, Hashable {
    case none
    case waiting(MeetingPoint)
    case agreed(MeetingPoint)
    case declined(MeetingPoint, reason: String)
    case pendingEdit(current: MeetingPoint, proposed: MeetingPoint)
}
