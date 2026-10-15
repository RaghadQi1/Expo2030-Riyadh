import Foundation

/// Canned answers for the demo assistant (12.01 – 12.07, خريطتي 7.1 – 7.12). The real assistant lives behind
/// `POST /assistant/messages`. Answers are suggestions only — every change to the plan, destination or a
/// friend needs a preview and an explicit confirmation in the UI.
enum MockAssistant {
    static let planPrompts = ["عندي ساعتين", "أبغى أقلل المشي", "وش البدائل لهذا الجناح؟", "وش بيتغير إذا أضفت الورشة؟", "رتّب ملاحظاتي"]
    static let mapPrompts = ["دلّيني على جناح", "اقترحي مكانًا أقل ازدحامًا", "اختاري نقطة التقاء بيني وبين ذكرى", "ما المحطة التالية في رحلتي؟"]

    static func planWelcome(name: String) -> String {
        "أهلًا\(name.isEmpty ? "" : " \(name)")! أقدر أساعدك في خطتك الحالية، البدائل، أو الطرق."
    }

    static func mapWelcome(name: String) -> String {
        "أهلًا\(name.isEmpty ? "" : " \(name)")! أقدر أدلّك على جناح، أقترح مكانًا أهدأ، أو أختار نقطة التقاء بينك وبين ذكرى."
    }

    static let thinkingText = "أبحث في الخريطة والازدحام الآن…"
    static let mapSourceNote = "الازدحام: بيانات الممرات قبل دقيقتين، وأوقات المشي تقديرية."

    static func reply(to text: String, context: AssistantContext) -> AssistantReply {
        let t = text
        if t.contains("دلّيني") || t.contains("دليني") || t.contains("جناح تقني") {
            let b = MockMap.booth("A6")!
            return AssistantReply(message: AssistantMessage(
                role: .assistant,
                text: "أقرب جناح تقني هادئ الآن هو CNTXT، على بعد ٣ دقائق من موقعك.",
                card: .place(AssistantPlaceResult(id: b.id, title: b.name, subtitle: "شركات، جناح A6، المدخل من الممر الغربي",
                                                  walkText: "٣ د مشيًا", distanceText: "١٣٠ م", crowd: .low,
                                                  reason: "قريب منك وضمن اهتماماتك في الذكاء الاصطناعي، والازدحام فيه منخفض.")),
                sourceNote: mapSourceNote))
        }
        if t.contains("أقل ازدحام") || t.contains("أهدأ") {
            return AssistantReply(message: AssistantMessage(
                role: .assistant, text: "هذه أهدأ ٣ أجنحة قريبة منك الآن:",
                card: .alternatives([
                    AssistantAlternative(id: "A6", title: "CNTXT", subtitle: "شركات، جناح A6، ٣ د", crowd: .low),
                    AssistantAlternative(id: "A5", title: "NSG", subtitle: "شركات، جناح A5، ٤ د", crowd: .low),
                    AssistantAlternative(id: "B4", title: "systems", subtitle: "شركات، جناح B4، ٤ د", crowd: .low),
                ], primaryAction: "الاتجاهات إلى CNTXT"),
                sourceNote: mapSourceNote))
        }
        if t.contains("نقطة التقاء") || t.contains("ذكرى") {
            return AssistantReply(message: AssistantMessage(
                role: .assistant, text: "أقترح ساحة الواحة – النافورة، فهي في المنتصف تقريبًا بينكما.",
                card: .meetingPoint(MockMap.meetingPoints[0], note: "أقل ازدحامًا من ممر قطار الحرمين، ومعلم واضح يسهل الالتقاء عنده."),
                sourceNote: "مبني على موقعك وموقع ذكرى المباشر، وبيانات الازدحام قبل دقيقتين."))
        }
        if t.contains("المحطة التالية") {
            let b = MockMap.booth("C1")!
            return AssistantReply(message: AssistantMessage(
                role: .assistant, text: "المحطة التالية في رحلتك بعد PwC هي وزارة الداخلية.",
                card: .place(AssistantPlaceResult(id: b.id, title: b.name, subtitle: "جهات حكومية، جناح C1",
                                                  walkText: "٤ د مشيًا", distanceText: "٢١٠ م", crowd: .low,
                                                  reason: "طريق مستقيم عبر الممر الغربي، والازدحام منخفض الآن.")),
                sourceNote: mapSourceNote))
        }
        if t.contains("المشي") {
            return AssistantReply(message: AssistantMessage(
                role: .assistant, text: "تقدر توفّر 8 دقائق مشي مع إبقاء ورشتك.",
                card: .planSuggestion(title: "خطة أقصر مشيًا", chips: ["مشي 18 ← 10 د", "الورشة محفوظة ★", "−1 محطة"],
                                      reason: "السبب: نحذف جناح الفضاء (أبعد محطة) ونضيف 10 د في جناح الذكاء والمستقبل القريب."),
                sourceNote: "مبني على خطتك الحالية وأوقات المشي التقديرية"))
        }
        if t.contains("البدائل") {
            return AssistantReply(message: AssistantMessage(
                role: .assistant, text: "المدن الذكية مزدحمة الآن (انتظار ~25 د). هذه ثلاثة بدائل قريبة تناسب اهتمامك:",
                card: .alternatives([
                    AssistantAlternative(id: "p4-space", title: "جناح الفضاء والاستكشاف", subtitle: "4 د · انتظار ~5 د", crowd: .low),
                    AssistantAlternative(id: "p9-digital-arts", title: "بيت الفنون الرقمية", subtitle: "6 د · انتظار ~10 د", crowd: .medium),
                    AssistantAlternative(id: "p6-water", title: "جناح المياه والواحات", subtitle: "3 د · الانتظار غير معروف", crowd: .unknown),
                ], primaryAction: nil),
                sourceNote: "الازدحام: حساسات الممرات وبيانات الجهات · قبل 3 د"))
        }
        if t.contains("ساعتين") {
            return AssistantReply(message: AssistantMessage(
                role: .assistant,
                text: "خطتك الحالية تغطي ساعتين (3:30–5:30 م) وفيها 4 تجارب مع الورشة المثبتة ★. تبي أقترح نسخة أهدأ أو أقل مشيًا؟"),
                followUps: ["أبغى أقلل المشي", "وش البدائل لهذا الجناح؟"])
        }
        if t.contains("الورشة") {
            return AssistantReply(message: AssistantMessage(
                role: .assistant,
                text: "الورشة مثبتة في خطتك 4:30 م ★. إضافتها مرة ثانية ما تغيّر شيء، وأي تعديل بيظهر لك كمعاينة قبل التطبيق."))
        }
        if t.contains("ملاحظاتي") {
            return AssistantReply(message: AssistantMessage(
                role: .assistant,
                text: "عندك 3 ملاحظات اليوم. أقدر أجهّز لك مسودة «ملخص اليوم» من «رحلتي»، وتبقى ملاحظاتك الأصلية كما هي."),
                followUps: ["ما المحطة التالية في رحلتي؟"])
        }
        return AssistantReply(message: AssistantMessage(
            role: .assistant,
            text: "جرّبي أحد الاقتراحات أدناه."),
            followUps: context == .map ? mapPrompts : planPrompts)
    }
}
