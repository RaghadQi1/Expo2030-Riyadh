import Foundation

// MARK: - Errors

/// Error surface shown to the user. Services map transport/server errors into these cases.
enum AppError: Error, Equatable, Hashable {
    case offline
    case unauthorized
    case invalidCredentials
    case validation([String: String])          // field → message
    case notFound
    case conflict(String)
    case server(String)
    case permissionDenied(String)
    case cancelled
    case unknown

    var isOffline: Bool { self == .offline }

    var title: String {
        switch self {
        case .offline: "أنت غير متصل"
        case .unauthorized: "انتهت الجلسة"
        case .invalidCredentials: "بيانات الدخول غير صحيحة"
        case .validation: "تحقق من الحقول"
        case .notFound: "غير موجود"
        case .conflict: "يوجد تعارض"
        case .server: "تعذّر إكمال الطلب"
        case .permissionDenied: "الإذن غير مفعّل"
        case .cancelled: "تم الإلغاء"
        case .unknown: "حدث خطأ غير متوقع"
        }
    }

    var message: String {
        switch self {
        case .offline: "نعرض لك البيانات المحفوظة، وسنزامن التغييرات عند عودة الاتصال."
        case .unauthorized: "سجّلي الدخول مجددًا للمتابعة."
        case .invalidCredentials: "البريد أو كلمة المرور غير صحيحة. حاولي مرة أخرى أو استعيدي كلمة المرور."
        case .validation(let fields): fields.values.first ?? "بعض الحقول تحتاج تعديلًا."
        case .notFound: "لم نعثر على ما تبحثين عنه."
        case .conflict(let m), .server(let m), .permissionDenied(let m): m
        case .cancelled: "لم يتغير شيء."
        case .unknown: "حاولي مرة أخرى بعد قليل."
        }
    }
}

// MARK: - Shared enums

/// Crowd level — always shape + word + colour (never colour alone). Unknown = grey "?".
enum CrowdLevel: String, Codable, CaseIterable, Hashable {
    case low, medium, high, unknown

    var title: String {
        switch self {
        case .low: "ازدحام منخفض"
        case .medium: "ازدحام متوسط"
        case .high: "مزدحم"
        case .unknown: "الازدحام غير معروف"
        }
    }

    var shortTitle: String {
        switch self {
        case .low: "منخفض"
        case .medium: "متوسط"
        case .high: "مرتفع"
        case .unknown: "غير معروف"
        }
    }

    /// Shape glyph used next to the word (Figma: ● low, ▲ medium, ■ high, ? unknown).
    var glyph: String {
        switch self {
        case .low: "●"
        case .medium: "▲"
        case .high: "■"
        case .unknown: "?"
        }
    }
}

/// The five Expo 2030 axes (المحاور) shown on Discover.
enum ExpoAxis: String, Codable, CaseIterable, Identifiable, Hashable {
    case tech, earth, human, culture, coop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tech: "التقنيات"
        case .earth: "الأرض"
        case .human: "الإنسان"
        case .culture: "الثقافة"
        case .coop: "التعاون"
        }
    }
}

/// Simple geometric point in the exhibition-map coordinate space (496 × 1357.8 pt Figma canvas).
struct MapPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

/// Wall-clock time of day (minutes since midnight) — used for plan timelines without time zones.
struct TimeOfDay: Codable, Hashable, Comparable {
    var minutes: Int

    init(_ hour: Int, _ minute: Int = 0) { minutes = hour * 60 + minute }
    init(minutes: Int) { self.minutes = minutes }

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    /// Arabic 12h formatting used across the design, e.g. "4:25 م".
    var arabic12h: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "ص" : "م"
        return "\(h12):\(String(format: "%02d", minute)) \(suffix)"
    }

    /// 24h formatting used on event time blocks, e.g. "16:30".
    var h24: String { "\(hour):\(String(format: "%02d", minute))" }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }
    func adding(minutes m: Int) -> TimeOfDay { TimeOfDay(minutes: minutes + m) }
}

/// Eastern-Arabic digits used by the «خريطتي» screens (٢٠٠ م، ٤ دقائق). Other screens use Western digits,
/// exactly as drawn in Figma.
enum ArabicDigits {
    static func convert(_ s: String) -> String {
        let map: [Character: Character] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
                                           "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
        return String(s.map { map[$0] ?? $0 })
    }
    static func format(_ n: Int) -> String { convert(String(n)) }

    /// «٩:٤٥ م»
    static func time(_ t: TimeOfDay) -> String { convert(t.arabic12h) }

    /// Minutes in words as used in Figma: «دقيقة»، «دقيقتان»، «٤ دقائق»، «١٥ دقيقة».
    static func minutes(_ m: Int) -> String {
        switch m {
        case 1: "دقيقة"
        case 2: "دقيقتان"
        case 3...10: "\(format(m)) دقائق"
        default: "\(format(m)) دقيقة"
        }
    }
}
