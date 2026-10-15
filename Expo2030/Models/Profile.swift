import Foundation

// MARK: - Professional profile (14.01 – 14.09) & account (16.01)

struct Experience: Codable, Hashable, Identifiable {
    var id: String
    var title: String                   // «محللة بيانات أولى»
    var subtitle: String                // «شركة تقنية النقل · 2022 – الآن»
}

/// «ما الذي تبحث عنه ؟» chips on 14.02.
enum LookingFor: String, CaseIterable, Codable, Hashable, Identifiable {
    case explore, job, internship, collaboration
    var id: String { rawValue }
    var title: String {
        switch self {
        case .explore: "اكتشف"
        case .job: "فرصة عمل"
        case .internship: "فرصة تدريب"
        case .collaboration: "تعاون"
        }
    }
}

struct CVFile: Codable, Hashable {
    var fileName: String                // «Sadeem-CV-2026.pdf»
    var details: String                 // «PDF · 412 KB · رُفع 2:10 م»
}

struct ProfessionalProfile: Codable, Hashable {
    var displayName: String
    var photo: String?
    var jobTitle: String = ""
    var bio: String = ""
    var education: String = ""
    var experiences: [Experience] = []
    var skills: [String] = []
    var lookingFor: Set<LookingFor> = []
    var linkedIn: String = ""
    var website: String = ""
    var preferredContact: String = ""
    var contactGoal: String = ""
    var cv: CVFile? = nil

    var isEmpty: Bool { jobTitle.isEmpty && bio.isEmpty && experiences.isEmpty && skills.isEmpty }
}

/// Fields the user can include in a shared profile link (14.04 «ماذا تشارك؟»).
enum ProfileField: String, CaseIterable, Codable, Hashable, Identifiable {
    case jobTitle, bio, education, experiences, skills, links, contact, cv
    var id: String { rawValue }
    var title: String {
        switch self {
        case .jobTitle: "المسمى"
        case .bio: "النبذة"
        case .education: "التخصص والتعليم"
        case .experiences: "الخبرات"
        case .skills: "المهارات"
        case .links: "الروابط"
        case .contact: "وسيلة التواصل"
        case .cv: "السيرة الذاتية (CV)"
        }
    }
}

enum LinkValidity: String, CaseIterable, Codable, Hashable, Identifiable {
    case oneHour, today, oneDay, oneWeek
    var id: String { rawValue }
    var title: String {
        switch self {
        case .oneHour: "ساعة"
        case .today: "حتى نهاية اليوم"
        case .oneDay: "24 ساعة"
        case .oneWeek: "أسبوع"
        }
    }
}

struct ProfileShareLink: Codable, Hashable {
    var url: String                     // «expo-riyadh.example/p/noura-q7k2»
    var fields: Set<ProfileField>
    var validity: LinkValidity
    var validUntilText: String          // «صالح حتى غد 4:40 م · 6 حقول»
    var isActive: Bool
}

/// Account preferences (16.01).
struct AccountSettings: Codable, Hashable {
    var notificationsEnabled = false
    var reduceMotion = false
    var largeText = false
}
