import Foundation

/// Demo data for «خريطتي». Booth footprints and label positions come from the Figma component
/// «خريطتي/Map/Exhibition» (496 × 1357.8). Distances, times and crowd levels are the values drawn in
/// the screens 1.1 – 3.12. Replace with `GET /map/hall`, `GET /map/booths`, `GET /map/crowd`.
enum MockMap {
    private static func booth(_ id: String, _ name: String, _ cat: PlaceCategory, logo: String,
                              frame: (Double, Double, Double, Double), label: (Double, Double),
                              meters: Int, minutes: Int, crowd: CrowdLevel, wait: Int? = nil,
                              summary: String = "", entrance: String = "المدخل من الممر الغربي",
                              photo: String? = nil, reason: String? = nil) -> Booth {
        Booth(id: id, name: name, category: cat, logoText: logo, summary: summary,
              frame: MapRect(x: frame.0, y: frame.1, width: frame.2, height: frame.3),
              labelPoint: MapPoint(x: label.0, y: label.1), entrance: entrance,
              distanceMeters: meters, walkMinutes: minutes, crowd: crowd, waitMinutes: wait,
              photo: photo, interestReason: reason)
    }

    static let booths: [Booth] = [
        booth("A1", "Nournet", .companies, logo: "NN", frame: (73.78, 15.13, 109.12, 60.76), label: (94.98, 16.12),
              meters: 420, minutes: 8, crowd: .low, summary: "خدمات الاتصالات ومراكز البيانات."),
        booth("B1", "T&S", .companies, logo: "T&S", frame: (214.52, 16.37, 86.8, 42.16), label: (237.89, 8.06),
              meters: 400, minutes: 7, crowd: .low, entrance: "المدخل من الممر الأوسط"),
        booth("B2", "BARQ", .companies, logo: "BQ", frame: (214.52, 69.69, 88.66, 44.64), label: (233.55, 62.62),
              meters: 350, minutes: 6, crowd: .low, entrance: "المدخل من الممر الأوسط"),
        booth("A2", "معادن", .companies, logo: "MA", frame: (70.06, 88.91, 112.22, 42.16), label: (101.49, 80.6),
              meters: 380, minutes: 7, crowd: .medium),
        booth("B3", "node", .companies, logo: "nd", frame: (213.9, 126.11, 90.52, 77.5), label: (235.41, 135.47),
              meters: 250, minutes: 5, crowd: .low, summary: "حلول تقنية وبرمجيات.", entrance: "المدخل من الممر الأوسط"),
        booth("A3", "منصة رؤى", .government, logo: "رؤى", frame: (68.82, 146.57, 113.46, 53.32), label: (91.26, 143.84),
              meters: 300, minutes: 6, crowd: .low),
        booth("A4", "إجادة ejada", .companies, logo: "ej", frame: (66.34, 216.63, 114.7, 62.62), label: (85.37, 218.55),
              meters: 190, minutes: 4, crowd: .low, summary: "تقنية المعلومات والتحول الرقمي.",
              photo: "photo-ai-city", reason: "ضمن اهتماماتك: التحول الرقمي"),
        booth("B4", "systems", .companies, logo: "sys", frame: (213.9, 222.21, 90.52, 44.64), label: (227.04, 215.14),
              meters: 195, minutes: 4, crowd: .low, entrance: "المدخل من الممر الأوسط"),
        booth("B5", "ضوئيات", .companies, logo: "ضو", frame: (213.28, 281.73, 93, 104.78), label: (230.45, 304.73),
              meters: 90, minutes: 2, crowd: .high, entrance: "المدخل من الممر الأوسط"),
        booth("A5", "NSG", .companies, logo: "NSG", frame: (63.24, 295.37, 117.18, 72.54), label: (100.25, 302.25),
              meters: 170, minutes: 4, crowd: .low, summary: "حلول البيانات والتحليلات.",
              photo: "photo-ai-classroom", reason: "هادئ الآن، عروض حلول البيانات"),
        booth("A6", "CNTXT", .companies, logo: "CX", frame: (60.14, 384.03, 119.04, 46.5), label: (91.88, 377.89),
              meters: 130, minutes: 3, crowd: .low, summary: "حلول تقنية للحوسبة السحابية والتحول الرقمي.",
              photo: "photo-robotics-lab", reason: "قريب منك وضمن اهتماماتك"),
        booth("B6", "قطار الحرمين", .government, logo: "HHR", frame: (213.28, 407.03, 88.66, 197.78), label: (216.38, 471.51),
              meters: 95, minutes: 2, crowd: .high, entrance: "المدخل من الممر الأوسط"),
        booth("A7", "PwC", .companies, logo: "pwc", frame: (57.66, 447.89, 120.9, 46.5), label: (96.53, 441.75),
              meters: 180, minutes: 4, crowd: .medium,
              summary: "استشارات الأعمال والتحول الرقمي، مع عروض حية للأمن السيبراني.", photo: "photo-vr-table"),
        booth("A8", "توال TAWAL", .companies, logo: "TW", frame: (53.94, 512.99, 123.38, 114.7), label: (75.76, 540.95),
              meters: 250, minutes: 5, crowd: .high, wait: 15, summary: "البنية التحتية للاتصالات والأبراج.", photo: "photo-water-oasis"),
        booth("B7", "وزارة العدل", .government, logo: "MOJ", frame: (211.42, 627.13, 91.14, 72.54), label: (221.03, 628.99),
              meters: 260, minutes: 5, crowd: .low, entrance: "المدخل من الممر الأوسط"),
        booth("C1", "وزارة الداخلية", .government, logo: "MOI", frame: (55.8, 649.45, 121.52, 199.64), label: (75.95, 714.86),
              meters: 210, minutes: 4, crowd: .low, photo: "photo-canyon-pavilions"),
        booth("B8", "بيت الفنون الرقمية", .companies, logo: "فن", frame: (209.56, 718.83, 93, 74.4), label: (201.62, 726.64),
              meters: 330, minutes: 6, crowd: .medium, photo: "photo-digital-arts"),
        booth("B9", "الحرس الوطني", .government, logo: "SANG", frame: (210.8, 810.03, 138.88, 109.12), label: (235.6, 830.18),
              meters: 420, minutes: 8, crowd: .low, entrance: "المدخل من الممر الأوسط"),
        booth("C2", "منطقة التفعيل", .services, logo: "✦", frame: (48.98, 878.85, 124, 211.42), label: (66.03, 950.15),
              meters: 520, minutes: 9, crowd: .medium),
        booth("B10", "السعودية الرقمية", .government, logo: "SD", frame: (208.94, 938.99, 141.36, 262.26), label: (229.09, 1035.71),
              meters: 610, minutes: 10, crowd: .low, entrance: "المدخل من الممر الأوسط"),
        booth("C3", "وزارة الثقافة", .government, logo: "MOC", frame: (43.4, 1118.79, 127.1, 99.82), label: (68.82, 1134.29),
              meters: 760, minutes: 12, crowd: .low),
        booth("C4", "الموارد البشرية", .government, logo: "HR", frame: (39.06, 1255.81, 128.96, 78.74), label: (58.28, 1260.77),
              meters: 900, minutes: 14, crowd: .low),
        booth("B11", "Beem", .companies, logo: "Bm", frame: (205.84, 1256.37, 101.68, 76.88), label: (231.07, 1265.42),
              meters: 880, minutes: 14, crowd: .low, entrance: "المدخل من الممر الأوسط"),
    ]

    static func booth(_ id: String) -> Booth? { booths.first { $0.id == id } }

    static let landmarks: [MapLandmark] = [
        MapLandmark(id: "gate8", name: "البوابة ٨", point: MapPoint(x: 438.96, y: 68.2), kind: .gate),
        MapLandmark(id: "gate7", name: "البوابة ٧", point: MapPoint(x: 438.96, y: 882.26), kind: .gate),
        MapLandmark(id: "plaza", name: "ساحة الواحة – النافورة", point: MapPoint(x: 376.96, y: 572.88), kind: .label),
        MapLandmark(id: "info-east", name: "معلومات البوابة الشرقية", point: MapPoint(x: 357.12, y: 916.36), kind: .label),
        MapLandmark(id: "corridor", name: "الممر الرئيسي", point: MapPoint(x: 386.26, y: 426.56), kind: .label),
        MapLandmark(id: "live-show", name: "عرض حي", point: MapPoint(x: 401.76, y: 791.74), kind: .label),
    ]

    static let hotspots: [CrowdHotspot] = [
        CrowdHotspot(id: "h1", frame: MapRect(x: 204.6, y: 367.04, width: 105.4, height: 52.08), level: .high,
                     badgePoint: MapPoint(x: 227.82, y: 381.93)),
        CrowdHotspot(id: "h2", frame: MapRect(x: 117.8, y: 527, width: 93, height: 86.8), level: .high,
                     badgePoint: MapPoint(x: 134.82, y: 559.25)),
        CrowdHotspot(id: "h3", frame: MapRect(x: 372, y: 737.8, width: 93, height: 105.4), level: .medium,
                     badgePoint: MapPoint(x: 372.59, y: 779.35)),
    ]

    static let quickServices: [QuickService] = [
        QuickService(id: "wc", title: "دورات المياه", icon: "droplet"),
        QuickService(id: "food", title: "المطاعم", icon: "coffee"),
        QuickService(id: "lift", title: "المصاعد", icon: "accessible"),
        QuickService(id: "info", title: "نقاط المعلومات", icon: "info"),
        QuickService(id: "cowork", title: "مساحة العمل", icon: "briefcase"),
    ]

    static let recentSearches = ["PwC", "وزارة الثقافة"]

    /// «أنتِ الآن» (1.1). The "Me" marker centre in the hall map.
    static let myLocation = UserLocation(point: MapPoint(x: 335.4, y: 365.8), headingDegrees: 270, accuracy: .high,
                                         areaTitle: "بين منطقة المطاعم ومساحة العمل",
                                         areaDetail: "قرب البوابة ٨، تتجهين غربًا")

    static let lowAccuracyLocation = UserLocation(point: MapPoint(x: 335.4, y: 365.8), headingDegrees: nil, accuracy: .low,
                                                  areaTitle: "قرب منطقة المطاعم",
                                                  areaDetail: "الاتجاه غير متاح بدقة الآن")

    static let hallCrowd: CrowdLevel = .medium

    // MARK: Routes

    private static let westAisleX = 186.0
    private static let mainCorridorX = 416.0

    /// Two options to PwC (2.3): fastest through the «قطار الحرمين» aisle, quietest via the main corridor.
    static func routes(to booth: Booth, from start: MapPoint = myLocation.point) -> [Route] {
        let entrance = MapPoint(x: booth.frame.x + booth.frame.width + 4, y: booth.frame.center.y)
        let fastestPath = [start, MapPoint(x: start.x, y: 383), MapPoint(x: westAisleX, y: 383),
                           MapPoint(x: westAisleX, y: entrance.y), entrance]
        let quietPath = [start, MapPoint(x: mainCorridorX, y: start.y), MapPoint(x: mainCorridorX, y: 634),
                         MapPoint(x: westAisleX, y: 634), MapPoint(x: westAisleX, y: entrance.y), entrance]
        let fastMinutes = booth.walkMinutes
        let quietMinutes = booth.walkMinutes + 3
        let baseArrival = TimeOfDay(21, 41)
        let fastest = Route(id: "r-fast-\(booth.id)", kind: .fastest, minutes: fastMinutes, meters: booth.distanceMeters,
                            note: "يمر بممر قطار الحرمين", arrival: baseArrival.adding(minutes: fastMinutes),
                            crowdOnRoute: .high, path: fastestPath,
                            steps: booth.id == "A7" ? pwcFastSteps : genericSteps(to: booth, path: fastestPath, minutes: fastMinutes))
        let quiet = Route(id: "r-quiet-\(booth.id)", kind: .quietest, minutes: quietMinutes,
                          meters: booth.distanceMeters + 130, note: "هادئ طوال الطريق",
                          arrival: baseArrival.adding(minutes: quietMinutes), crowdOnRoute: .low, path: quietPath,
                          steps: booth.id == "A7" ? pwcQuietSteps : genericSteps(to: booth, path: quietPath, minutes: quietMinutes))
        return [fastest, quiet]
    }

    /// Turn-by-turn texts of 2.6 – 2.9.
    static let pwcFastSteps: [NavigationStep] = [
        NavigationStep(id: "n1", distanceText: "بعد ٢٠ مترًا", instruction: "انعطفي يسارًا", direction: .left,
                       thenText: "ثم بعد ١٨ مترًا انعطفي يمينًا", remainingText: "باقي ٤ دقائق",
                       progressText: "١٨٠ م، الوصول ٩:٤٥ م", alert: "ازدحام على الطريق عند ممر قطار الحرمين",
                       alertLevel: .high, landmark: "معلم قريب: مساحة العمل المشترك على يسارك", position: MapPoint(x: 335.4, y: 365.8)),
        NavigationStep(id: "n2", distanceText: "بعد ٨ أمتار", instruction: "انعطفي يمينًا", direction: .right,
                       thenText: "ثم تابعي بجانب جناح قطار الحرمين", remainingText: "باقي ٣ دقائق",
                       progressText: "١٥٠ م، الوصول ٩:٤٥ م", alert: "الممر التالي مزدحم، امشي بتمهل",
                       alertLevel: .high, landmark: "جناح ضوئيات على يمينك", position: MapPoint(x: 300, y: 383)),
        NavigationStep(id: "n3", distanceText: "بعد ٣٥ مترًا", instruction: "انعطفي يسارًا", direction: .left,
                       thenText: "ثم تابعي ٥٠ مترًا حتى PwC", remainingText: "باقي دقيقتان",
                       progressText: "٩٠ م، الوصول ٩:٤٥ م", alert: "أنتِ في منطقة مزدحمة الآن",
                       alertLevel: .high, landmark: "قطار الحرمين على يسارك", position: MapPoint(x: 210, y: 383)),
        NavigationStep(id: "n4", distanceText: "٢٥ مترًا", instruction: "تابعي إلى الأمام", direction: .straight,
                       thenText: "بجانب جناح PwC، المدخل على يمينك", remainingText: "أقل من دقيقة",
                       progressText: "٢٧ م، الوصول ٩:٤٥ م", alert: "ازدحام متوسط عند الجناح",
                       alertLevel: .medium, landmark: "تابعي إلى الأمام بجانب جناح PwC", position: MapPoint(x: 186, y: 440)),
    ]

    /// 2.11 «التوجيه بالطريق البديل».
    static let pwcQuietSteps: [NavigationStep] = [
        NavigationStep(id: "q1", distanceText: "بعد ٢٠ مترًا", instruction: "انعطفي يمينًا", direction: .right,
                       thenText: "ثم تابعي شمالًا بجانب منطقة المطاعم", remainingText: "باقي ٧ دقائق",
                       progressText: "٣١٠ م، الوصول ٩:٤٨ م", alert: "طريق هادئ، يتجنب ممر قطار الحرمين",
                       alertLevel: .low, landmark: "معلم قريب: منطقة المطاعم على يمينك", position: MapPoint(x: 335.4, y: 365.8)),
        NavigationStep(id: "q2", distanceText: "بعد ٦٠ مترًا", instruction: "انعطفي يمينًا", direction: .right,
                       thenText: "ثم تابعي غربًا عبر الممر العرضي", remainingText: "باقي ٤ دقائق",
                       progressText: "١٧٠ م، الوصول ٩:٤٨ م", alert: "طريق هادئ",
                       alertLevel: .low, landmark: "ساحة الواحة على يسارك", position: MapPoint(x: 416, y: 560)),
        NavigationStep(id: "q3", distanceText: "٣٠ مترًا", instruction: "تابعي إلى الأمام", direction: .straight,
                       thenText: "بجانب جناح PwC، المدخل على يمينك", remainingText: "أقل من دقيقة",
                       progressText: "٣٠ م، الوصول ٩:٤٨ م", alert: "ازدحام متوسط عند الجناح",
                       alertLevel: .medium, landmark: nil, position: MapPoint(x: 186, y: 520)),
    ]

    /// 3.11 «التوجيه إلى CNTXT» and a generic fallback for other booths.
    static func genericSteps(to booth: Booth, path: [MapPoint], minutes: Int) -> [NavigationStep] {
        if booth.id == "A6" {
            return [NavigationStep(id: "c1", distanceText: "بعد ٣٥ مترًا", instruction: "انعطفي يسارًا", direction: .left,
                                   thenText: "ثم CNTXT على يمينك بعد ٨ أمتار", remainingText: "باقي دقيقة",
                                   progressText: "٤٢ م، الوصول ٩:٤٤ م", alert: "أنتِ في منطقة مزدحمة الآن",
                                   alertLevel: .high, landmark: "قطار الحرمين على يسارك", position: path[min(2, path.count - 1)])]
        }
        let arrival = ArabicDigits.time(TimeOfDay(21, 41).adding(minutes: minutes))
        return [
            NavigationStep(id: "g1", distanceText: "بعد ٢٠ مترًا", instruction: "انعطفي يسارًا", direction: .left,
                           thenText: "ثم تابعي عبر الممر الغربي", remainingText: "باقي \(ArabicDigits.minutes(minutes))",
                           progressText: "\(ArabicDigits.format(booth.distanceMeters)) م، الوصول \(arrival)",
                           alert: nil, landmark: nil, position: path[0]),
            NavigationStep(id: "g2", distanceText: "٣٠ مترًا", instruction: "تابعي إلى الأمام", direction: .straight,
                           thenText: "\(booth.name) على يمينك", remainingText: "أقل من دقيقة",
                           progressText: "٣٠ م، الوصول \(arrival)", alert: nil, landmark: nil,
                           position: path[max(0, path.count - 2)]),
        ]
    }

    /// 3.2 alternatives when TAWAL is crowded.
    static var tawalAlternatives: [BoothAlternative] {
        [BoothAlternative(booth: booth("A6")!, rank: 1, reason: "قريب منك وضمن اهتماماتك"),
         BoothAlternative(booth: booth("A5")!, rank: 2, reason: "هادئ الآن، عروض حلول البيانات"),
         BoothAlternative(booth: booth("A4")!, rank: 3, reason: "ضمن اهتماماتك: التحول الرقمي")]
    }

    /// «المحطة التالية في خطتك» (3.9).
    static let nextStopBoothId = "C1"

    // MARK: Social

    static let myInvite = InviteLink(url: "dalil.expo/i/sadeem-4F7K", ownerName: "سديم الحربي",
                                     validityText: "صالح لمدة ٢٤ ساعة، والقبول لا يشارك موقعك تلقائيًا")

    static let reem = Friend(id: "f-reem", name: "ريم", avatar: "avatar-reem", connectedSince: "متصلتان منذ ٨:٢٠ م",
                             myShare: .none, myShareEndsAt: nil, shareInBackground: false, sharesWithMe: false,
                             isVisibleOnMap: true, location: nil)

    static let thikra = Friend(id: "f-thikra", name: "ذكرى", avatar: "avatar-sara", connectedSince: "متصلتان منذ ٩:٣٥ م",
                               myShare: .none, myShareEndsAt: nil, shareInBackground: false, sharesWithMe: true,
                               isVisibleOnMap: true,
                               location: FriendLocation(point: MapPoint(x: 410, y: 600), areaText: "قرب ساحة الواحة",
                                                        distanceMeters: 270, walkMinutes: 6, updatedMinutesAgo: 0,
                                                        updatedAtText: "٩:٤١ م"))

    /// 5.10 «التوجيه إلى ذكرى».
    static func friendRoute(_ friend: Friend) -> Route {
        let target = friend.location?.point ?? MapPoint(x: 410, y: 600)
        let path = [myLocation.point, MapPoint(x: myLocation.point.x, y: 383), MapPoint(x: mainCorridorX, y: 383),
                    MapPoint(x: mainCorridorX, y: target.y), target]
        let mins = friend.location?.walkMinutes ?? 6
        let meters = friend.location?.distanceMeters ?? 270
        let step = NavigationStep(id: "f1", distanceText: "بعد ٥٥ مترًا", instruction: "انعطفي يمينًا", direction: .right,
                                  thenText: "ثم تابعي عبر ساحة الواحة باتجاه \(friend.name)",
                                  remainingText: "باقي \(ArabicDigits.minutes(mins))",
                                  progressText: "\(ArabicDigits.format(meters)) م إلى \(friend.name)، الوصول \(ArabicDigits.time(TimeOfDay(21, 41).adding(minutes: mins)))",
                                  alert: "\(friend.name) تتحرك، نحدّث المسار تلقائيًا مع موقعها المباشر", alertLevel: .unknown,
                                  landmark: nil, position: myLocation.point)
        return Route(id: "r-friend-\(friend.id)", kind: .fastest, minutes: mins, meters: meters, note: "",
                     arrival: TimeOfDay(21, 41).adding(minutes: mins), crowdOnRoute: .low, path: path, steps: [step])
    }

    /// 6.7 «التوجيه إلى نقطة الالتقاء».
    static func meetingRoute(_ point: MeetingPoint) -> Route {
        let path = [myLocation.point, MapPoint(x: myLocation.point.x, y: 383), MapPoint(x: mainCorridorX, y: 383),
                    MapPoint(x: mainCorridorX, y: point.point.y), point.point]
        let step = NavigationStep(id: "m1", distanceText: "بعد ٥٥ مترًا", instruction: "انعطفي يمينًا", direction: .right,
                                  thenText: "ثم النافورة أمامك بعد ٩٠ مترًا",
                                  remainingText: "باقي \(ArabicDigits.minutes(point.myMinutes))",
                                  progressText: "\(ArabicDigits.format(point.myMeters)) م إلى \(point.name.components(separatedBy: " – ").first ?? point.name)، الوصول \(ArabicDigits.time(point.myArrival))",
                                  alert: "ذكرى على بعد دقيقة من النقطة", alertLevel: .unknown, landmark: nil,
                                  position: myLocation.point)
        return Route(id: "r-meet-\(point.id)", kind: .fastest, minutes: point.myMinutes, meters: point.myMeters, note: "",
                     arrival: point.myArrival, crowdOnRoute: .low, path: path, steps: [step])
    }

    static let meetingPoints: [MeetingPoint] = [
        MeetingPoint(id: "m-plaza", name: "ساحة الواحة – النافورة", subtitle: "الممر الرئيسي، بين البوابتين ٨ و٧",
                     point: MapPoint(x: 421.6, y: 533), myMinutes: 4, myMeters: 180, friendMinutes: 2, friendMeters: 90,
                     myArrival: TimeOfDay(21, 46), friendArrival: TimeOfDay(21, 44)),
        MeetingPoint(id: "m-arts", name: "مدخل بيت الفنون الرقمية", subtitle: "الممر الأوسط، جناح B8",
                     point: MapPoint(x: 306, y: 756), myMinutes: 6, myMeters: 300, friendMinutes: 3, friendMeters: 140,
                     myArrival: TimeOfDay(21, 48), friendArrival: TimeOfDay(21, 45)),
        MeetingPoint(id: "m-info", name: "نقطة معلومات البوابة الشرقية", subtitle: "قرب البوابة ٧",
                     point: MapPoint(x: 381.3, y: 902), myMinutes: 9, myMeters: 450, friendMinutes: 4, friendMeters: 200,
                     myArrival: TimeOfDay(21, 51), friendArrival: TimeOfDay(21, 46)),
    ]
}
