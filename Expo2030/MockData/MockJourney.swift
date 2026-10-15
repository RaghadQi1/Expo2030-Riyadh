import Foundation

/// Demo data for «رحلتي» (13.x), QR (14.x) and the journey summary. Replace with `GET /journey`, `GET /notes`.
enum MockJourney {
    static let dayTitle = "الأربعاء 1 أكتوبر · 3 زيارات مؤكدة"

    static let visits: [JourneyVisit] = [
        JourneyVisit(id: "v1", placeId: "p1-ai-future", title: "جناح الذكاء والمستقبل", start: TimeOfDay(15, 34),
                     end: TimeOfDay(15, 56), confirmation: .confirmed, extrasText: "ملاحظة واحدة · صورتان", thumbnail: "photo-ai-city"),
        JourneyVisit(id: "v2", placeId: "p4-space", title: "جناح الفضاء والاستكشاف", start: TimeOfDay(16, 5),
                     end: TimeOfDay(16, 25), confirmation: .confirmed, extrasText: "ملاحظة صوتية", thumbnail: "photo-space-astronauts"),
        JourneyVisit(id: "v3", placeId: "p3-robotics", title: "مختبر الروبوتات · الورشة", start: TimeOfDay(16, 30),
                     end: TimeOfDay(17, 15), confirmation: .confirmed, extrasText: "ملاحظة + رابط", thumbnail: "photo-robotics-lab"),
        JourneyVisit(id: "v4", placeId: "p9-digital-arts", title: "بيت الفنون الرقمية", start: TimeOfDay(17, 22),
                     end: nil, confirmation: .scannedOnly(TimeOfDay(17, 22)), extrasText: nil, thumbnail: "photo-digital-arts"),
    ]

    static let notes: [VisitNote] = [
        VisitNote(id: "n1", placeId: "p1-ai-future", placeName: "جناح الذكاء والمستقبل", title: "مدن تتعلم من سكانها",
                  liked: "غرفة المدينة المصغّرة: تحرك السيارات وتشوف أثر القرار فورًا.",
                  learned: "النماذج التنبؤية تقلل الازدحام بإعادة توزيع الحركة لحظيًا.",
                  followUpQuestion: "كيف تُحمى خصوصية السكان في هذه البيانات؟",
                  attachments: [NoteAttachment(id: "a1", kind: .photo, value: "photo-ai-city"),
                                NoteAttachment(id: "a2", kind: .photo, value: "photo-ai-classroom")]),
        VisitNote(id: "n2", placeId: "p4-space", placeName: "جناح الفضاء والاستكشاف", title: "عرض القبة عن المريخ",
                  attachments: [NoteAttachment(id: "a3", kind: .voice, value: "0:42")]),
        VisitNote(id: "n3", placeId: "p3-robotics", placeName: "مختبر الروبوتات · الورشة", title: "ابنِ روبوتك الأول",
                  learned: "بناء روبوت بسيط يبدأ بالحساسات قبل الخوارزميات.",
                  attachments: [NoteAttachment(id: "a4", kind: .link, value: "https://example.org/robot-kit")]),
    ]

    static let saved: [SavedPlace] = [
        SavedPlace(id: "p9-digital-arts", title: "بيت الفنون الرقمية", subtitle: "الثقافة · معرض ضوئي تفاعلي", photo: "photo-digital-arts"),
        SavedPlace(id: "p6-water", title: "جناح المياه والواحات", subtitle: "الأرض · تجربة تفاعلية", photo: "photo-water-oasis"),
        SavedPlace(id: "p2-smart-cities", title: "جناح المدن الذكية", subtitle: "التقنيات · عرض «مدينة 2050»", photo: "photo-ai-classroom"),
        SavedPlace(id: "p8-heritage", title: "جناح التراث الحي", subtitle: "الثقافة · معرض", photo: "photo-tree-tower"),
        SavedPlace(id: "p4-space", title: "جناح الفضاء والاستكشاف", subtitle: "لاحقًا · نُقل من خطتك", photo: "photo-space-astronauts"),
    ]

    static let followUps: [FollowUpItem] = [
        FollowUpItem(id: "fu1", title: "أراسل الجهة عن برنامج المتطوعين", subtitle: "جناح الذكاء والمستقبل · الأحد"),
        FollowUpItem(id: "fu2", title: "أراجع ملخص الورشة مع زملائي", subtitle: "مختبر الروبوتات"),
        FollowUpItem(id: "fu3", title: "كيف تُحمى خصوصية السكان في هذه البيانات؟", subtitle: "سؤال من ملاحظتك"),
    ]

    static let summary = JourneySummary(
        title: "رحلتك في إكسبو · 1 أكتوبر", subtitle: "4 تجارب · 3 ملاحظات · 1 صديق",
        duration: "2 س 05 د", distance: "1.9 كم مشي", priority: "★ الورشة ✓",
        learned: ["النماذج التنبؤية تعيد توزيع الحركة لحظيًا", "بناء روبوت بسيط يبدأ بالحساسات قبل الخوارزميات"],
        interesting: ["مدن تتكلم مع سكانها عبر البيانات المفتوحة", "عرض القبة عن المريخ"],
        nextSteps: ["أراسل الجهة عن برنامج المتطوعين (الأحد)", "أراجع ملخص الورشة مع زملائي"])

    /// Codes accepted on 14.18 «أدخل رمز الجناح» (demo).
    static let pavilionCodes: [String: String] = ["DA-09": "p9-digital-arts", "AI-01": "p1-ai-future", "SP-04": "p4-space"]

    static let scannedDigitalArts = ScannedPlace(placeId: "p9-digital-arts", name: "بيت الفنون الرقمية",
                                                 subtitle: "الثقافة · معرض ضوئي تفاعلي", photo: "photo-digital-arts")
}

/// Demo professional profile (14.02 / 14.06).
enum MockProfile {
    static let filled = ProfessionalProfile(
        displayName: "سديم الحربي", photo: "avatar-sadeem", jobTitle: "مهندسة بيانات",
        bio: "أعمل على تحليل بيانات التنقل في المدن، وأبحث عن شراكات لمشاريع المدن الذكية.",
        education: "بكالوريوس علوم الحاسب · جامعة الملك سعود",
        experiences: [Experience(id: "x1", title: "محللة بيانات أولى", subtitle: "شركة تقنية النقل · 2022 – الآن"),
                      Experience(id: "x2", title: "متدربة بحث", subtitle: "مختبر المدن الذكية · 2021")],
        skills: ["Python", "تحليل الحركة", "نمذجة تنبؤية", "SQL"],
        lookingFor: [.collaboration, .internship],
        linkedIn: "linkedin.com/in/Sadeem-example", website: "Sadeem.example/portfolio",
        preferredContact: "البريد: Sadeem@example.com", contactGoal: "شراكات بحثية · فرص تدريب للطلاب",
        cv: CVFile(fileName: "Sadeem-CV-2026.pdf", details: "PDF · 412 KB · رُفع 2:10 م"))

    static let shareLink = ProfileShareLink(url: "expo-riyadh.example/p/noura-q7k2",
                                            fields: [.jobTitle, .bio, .experiences, .skills, .links, .contact],
                                            validity: .oneDay, validUntilText: "صالح حتى غد 4:40 م · 6 حقول", isActive: true)
}
