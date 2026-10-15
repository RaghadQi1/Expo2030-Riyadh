import Foundation

// MARK: - My Journey (13.x) & QR (14.10 – 14.18)

enum JourneySection: String, CaseIterable, Identifiable, Hashable {
    // RTL order as drawn: زرتها · محفوظة · ملاحظاتي · المتابعة
    case visited, saved, notes, followUp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .visited: "زرتها"
        case .saved: "محفوظة"
        case .notes: "ملاحظاتي"
        case .followUp: "المتابعة"
        }
    }
}

enum AttachmentKind: String, Codable, Hashable {
    case photo, voice, link
    var title: String {
        switch self {
        case .photo: "صورة"
        case .voice: "ملاحظة صوتية"
        case .link: "رابط"
        }
    }
}

struct NoteAttachment: Codable, Hashable, Identifiable {
    var id: String
    var kind: AttachmentKind
    var value: String                   // asset name / duration / URL
}

/// Structured note (13.03): prompts «ما أعجبني / ما تعلمته / فكرة ألهمتني / سؤال للمتابعة / كتابة حرة».
struct VisitNote: Codable, Hashable, Identifiable {
    var id: String
    var placeId: String                 // pavilion id or booth code
    var placeName: String
    var title: String = ""
    var liked: String = ""
    var learned: String = ""
    var idea: String = ""
    var followUpQuestion: String = ""
    var freeText: String = ""
    var attachments: [NoteAttachment] = []
    var updatedAt: Date = Date()
    /// Created offline and waiting to sync (17.04).
    var isPendingSync = false

    var isEmpty: Bool {
        [title, liked, learned, idea, followUpQuestion, freeText].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            && attachments.isEmpty
    }

    /// One-line preview for lists.
    var preview: String {
        [liked, learned, idea, followUpQuestion, freeText].first { !$0.isEmpty } ?? title
    }
}

enum VisitConfirmation: Hashable, Codable {
    case confirmed                      // «✓ زيارة أكدتها»
    case scannedOnly(TimeOfDay)         // «مسحت رمزه 5:22 م» · «لم تؤكد الزيارة»
}

struct JourneyVisit: Codable, Hashable, Identifiable {
    var id: String
    var placeId: String
    var title: String
    var start: TimeOfDay
    var end: TimeOfDay?
    var confirmation: VisitConfirmation
    var extrasText: String?             // «ملاحظة واحدة · صورتان»
    var thumbnail: String?

    var timeText: String {
        switch confirmation {
        case .scannedOnly(let t): return "مسحت رمزه \(t.arabic12h)"
        case .confirmed:
            guard let end else { return start.arabic12h }
            let mins = end.minutes - start.minutes
            return "\(start.arabic12h.replacingOccurrences(of: " م", with: "").replacingOccurrences(of: " ص", with: "")) – \(end.arabic12h) · \(mins) د"
        }
    }
}

struct SavedPlace: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var photo: String?
}

struct FollowUpItem: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var isDone = false
}

/// AI draft summary (13.07). Originals are never modified.
struct JourneySummary: Codable, Hashable {
    var title: String                   // «رحلتك في إكسبو · 1 أكتوبر»
    var subtitle: String                // «4 تجارب · 3 ملاحظات · 1 …»
    var duration: String                // «2 س 05 د»
    var distance: String                // «1.9 كم مشي»
    var priority: String                // «★ الورشة ✓»
    var learned: [String]
    var interesting: [String]
    var nextSteps: [String]
}

/// Result of scanning a pavilion QR code (14.13).
struct ScannedPlace: Codable, Hashable {
    var placeId: String
    var name: String
    var subtitle: String
    var photo: String?
}

// MARK: - Offline & sync (17.x)

enum ConnectivityState: Hashable {
    case online
    case offline(lastSynced: String)    // «آخر مزامنة 3:41 م»
    case syncing(pending: Int)
    case restored
}

// MARK: - Assistant (12.x, خريطتي 7.x)

enum AssistantContext: Codable, Hashable {
    case plan, map, pavilion(String), journey, general
    var title: String {
        switch self {
        case .plan: "يرى: خطتي"
        case .map: "يرى: خريطتي"
        case .pavilion: "يرى: تفاصيل الجناح"
        case .journey: "يرى: رحلتي"
        case .general: "يرى: الصفحة الحالية"
        }
    }
}

enum AssistantCard: Codable, Hashable {
    /// «خطة أقصر مشيًا» — proposal that needs a preview before changing the plan (12.02/12.03).
    case planSuggestion(title: String, chips: [String], reason: String)
    /// List of pavilion / booth alternatives.
    case alternatives([AssistantAlternative], primaryAction: String?)
    /// A single booth / place result with actions (خريطتي 7.7, 7.10).
    case place(AssistantPlaceResult)
    /// Meeting point proposal (خريطتي 7.9).
    case meetingPoint(MeetingPoint, note: String)
}

struct AssistantAlternative: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var crowd: CrowdLevel
}

struct AssistantPlaceResult: Codable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var walkText: String                // «٣ د مشيًا»
    var distanceText: String            // «١٣٠ م»
    var crowd: CrowdLevel
    var reason: String
}

struct AssistantMessage: Codable, Hashable, Identifiable {
    enum Role: Codable, Hashable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var card: AssistantCard? = nil
    /// «الازدحام: بيانات الممرات قبل دقيقتين» — always shown under live-data answers.
    var sourceNote: String? = nil
}

struct AssistantReply: Codable, Hashable {
    var message: AssistantMessage
    var followUps: [String] = []
}
