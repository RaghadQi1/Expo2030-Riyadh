# عقد الواجهة البرمجية المقترح (API Contract) — تطبيق 2030Expo

> **تنبيه مهم:** كل ما في هذا الملف **اقتراحات** كُتبت من جهة الواجهة الأمامية فقط، وتحتاج اتفاقًا مع مطوّرة الباك إند قبل التنفيذ. لم يُختبر أي مسار هنا مع خادم حقيقي.
> كل مسار مذكور هنا له مقابل في الكود داخل `Expo2030/Services/Live/*.swift`، وكل نموذج بيانات له مقابل في `Expo2030/Models/*.swift`. أي تعديل يُتفق عليه يكفي تطبيقه في هذين المكانين، ولا يلزم تغيير الواجهات.

---

## 0. أساسيات مشتركة

| البند | الاقتراح |
|---|---|
| الرابط الأساسي | `API_BASE_URL`، مثل `https://api.example.com/v1/`، ويُضبط من مخطط التشغيل (Scheme) أو من Info.plist |
| التنسيق | JSON بترميز UTF-8 |
| أسماء الحقول | `snake_case` في الـ JSON، ويحوّلها التطبيق تلقائيًا إلى camelCase |
| التاريخ والوقت المطلق | ISO-8601، مثل `2026-10-01T15:34:00+03:00` |
| وقت اليوم في الجداول | `{"minutes": 934}` أي دقائق منذ منتصف الليل (النموذج `TimeOfDay`). يمكن الاتفاق على `"15:34"` بدلًا منه وتعديل `TimeOfDay` |
| اللغة | يرسل التطبيق `Accept-Language: ar`، ويُتوقع أن تأتي النصوص المعروضة عربية من الخادم |
| المصادقة | `Authorization: Bearer <access_token>` |
| رموز الحالة | `200/201` نجاح · `401` الجلسة منتهية · `404` غير موجود · `409` تعارض · `422` أخطاء حقول · `5xx` خطأ خادم |

### شكل الأخطاء (`APIProblem`)

```json
{
  "code": "validation_failed",
  "message": "بعض الحقول تحتاج تعديلًا.",
  "fields": { "email": "أدخل بريدًا إلكترونيًا صحيحًا، مثل name@example.com" }
}
```

يعرض التطبيق قيمة `message` للمستخدم كما هي، ويعرض كل قيمة في `fields` تحت حقلها.

### الأنواع ذات القيم المرتبطة (enum with associated values)

يرمّز Swift حاليًا هذه الأنواع بالشكل الافتراضي، مثل:

```json
{ "live": { "minutes": 60 } }
{ "until_end_of_visit": {} }
{ "agreed": { "_0": { "id": "m-plaza", "name": "…" } } }
```

**نقترح الاتفاق على شكل أوضح** مثل `{"type": "live", "minutes": 60}`، ثم إضافة `Codable` مخصص في النموذج. ينطبق هذا على الأنواع التالية:

- `LocationShareMode`
- `MeetingState`
- `PlanStepKind`
- `StepChange`
- `ReplanReason`
- `AddToPlanResult`
- `EntryPolicy`
- `AssistantCard`
- `VisitConfirmation`
- `NavigationTarget`

### وضع التشغيل

| المتغير | القيمة | المعنى |
|---|---|---|
| `EXPO_API_MODE` | `mock` (الافتراضي) | بيانات تجريبية داخل التطبيق، بلا أي اتصال |
| `EXPO_API_MODE` | `live` | يستخدم `Services/Live` مع `API_BASE_URL` |

إذا اختير `live` دون `API_BASE_URL` يعود التطبيق إلى `mock` تلقائيًا.

---

## 1. الحساب والدخول (الشاشات 05.x – 06.x)

| العملية | المسار | الطلب | الرد |
|---|---|---|---|
| دخول بالبريد | `POST /auth/login` | `{email, password}` | `Session` · `401` يعني بيانات خاطئة |
| إنشاء حساب | `POST /auth/register` | `SignUpRequest` | `201 Session` مع جلسة فورية؛ لا يُرسل بريد |
| نسيت كلمة المرور | `POST /auth/password/forgot` | `{email}` | `503` حاليًا؛ الاستعادة غير مفعّلة |
| تعيين كلمة مرور جديدة | `POST /auth/password/reset` | `{token, new_password}` | `503` حاليًا؛ غير مفعّل |
| الدخول الاجتماعي | `POST /auth/social` | `{provider, id_token}` | انظري الحالات تحت الجدول |
| إكمال الاسم (06.19) | `PATCH /me` | `{display_name}` | `Session` |
| دمج بيانات الضيف (06.24) | `POST /me/merge-guest-data` | `GuestDataSummary` + البيانات المحلية | `GuestDataSummary` لما دُمج |
| خروج | `POST /auth/logout` | — | `204` |

حالات رد `POST /auth/social`:

- `200`: يعيد `Session`.
- `202`: الحساب يحتاج اسمًا (`needs_profile`).
- `409`: يوجد حساب بالبريد نفسه بطريقة دخول أخرى (`existing_account` مع `existing_provider`).

مثال `Session`:

```json
{
  "user": { "id": "u_123", "name": "سديم الحربي", "email": "sadeem@example.com",
            "avatar_asset": null, "provider": "email", "is_email_verified": false,
            "uses_private_relay_email": false },
  "access_token": "…", "refresh_token": "…"
}
```

> **الدخول الاجتماعي:** يحتاج حزم المزودين الأصلية:
>
> - Apple: عبر AuthenticationServices.
> - Google وFacebook: حزمهما الرسمية (SDK)، ولم تُضمَّن في المشروع.
>
> في الوضع التجريبي تظهر ورقة «محاكاة»، وهي موسومة بأنها تجريبية.

---

## 2. الاكتشاف والأجنحة والفعاليات (08.x)

| العملية | المسار | ملاحظات |
|---|---|---|
| الصفحة الرئيسية | `GET /discover?personalized=true` | `DiscoverFeed`: المحطة التالية، المحاور، الفرص، الفعاليات، الترشيحات |
| قائمة الأجنحة | `GET /pavilions?axes=tech,earth&crowd=low&max_distance=500&open_now=true` | `[Pavilion]` |
| تفاصيل جناح | `GET /pavilions/{id}` | `Pavilion` |
| الفعاليات | `GET /events` و `GET /events/{id}` | `ExpoEvent` |
| البحث | `GET /search?q=…` | `[Pavilion]` |

مثال `Pavilion` (مختصر):

```json
{
  "id": "p1-ai-future", "name": "جناح الذكاء والمستقبل", "organization": "تحالف المستقبل الرقمي",
  "experience_type": "تجربة تفاعلية", "axis": "tech", "photo": "https://cdn…/ai.jpg",
  "hours": "مفتوح 10ص – 11م", "duration_minutes": 20, "languages": "العربية · English",
  "entrance": "مدخل B الشمالي", "entrance_note": "المدخل الصحيح: B الشمالي (المدخل A مخصص للخروج)",
  "entry": { "free": {} },
  "live": { "crowd": "medium", "wait_minutes": 5, "seats_left": null, "updated_minutes_ago": 2, "source": "الجهة المشاركة" },
  "walk_minutes": 4, "distance_meters": 320,
  "about": "…", "highlights": ["…"], "attendance_rules": ["…"],
  "accessibility": [{ "title": "مقاعد استراحة داخل القاعة 2", "available": true }],
  "accessibility_verified_on": "موثّق من الجهة المشاركة · آخر تحديث 1 أكتوبر",
  "site_point": { "x": 412, "y": 300 }, "short_name": "الذكاء", "recommendation_reason": "لأنك اخترت «التقنيات»"
}
```

> **الصور:** يتوقع التطبيق الآن **اسم أصل محلي** في `photo`. عند الربط نقترح إرجاع رابط HTTPS، ثم استبدال `PhotoView` بعرض صورة من الإنترنت (`AsyncImage` أو مكتبة تخزين مؤقت). هذا مذكور في ملاحظات التسليم.
>
> **حداثة البيانات:** `live.updated_minutes_ago > 10` يجعل التطبيق يعرض تحذير «قد لا تكون البيانات محدّثة».

---

## 3. التخصيص والخطة (07.x، 09.x)

| العملية | المسار | الطلب ← الرد |
|---|---|---|
| خيارات «لا تفوّت» | `GET /plans/priority-candidates` | ← `[PriorityCandidate]` |
| توليد الخطة (07.07) | `POST /plans/generate` | `PlanPreferences` ← `[PlanOption]` (خياران عادةً) |
| اعتماد خيار (09.01) | `POST /plans/adopt` | `{id}` ← `Plan` |
| الخطة الحالية | `GET /plans/current` | ← `Plan` أو `404` إذا لا توجد خطة |
| إضافة جناح أو فعالية | `POST /plans/current/items` | `{id}` ← `AddToPlanResult` (`added` أو `conflict`) |
| حلّ تعارض | `POST /plans/current/conflicts/resolve` | `{id: option_id}` ← `Plan` |
| اقتراح إعادة جدولة (09.05) | `POST /plans/current/replan` | `ReplanReason` ← `ReplanProposal` (معاينة فقط دون تغيير) |
| تطبيق المعاينة | `POST /plans/current/replan/apply` | `{id}` ← `Plan` |
| تنبيه الازدحام (09.07) | `GET /plans/current/crowd-alerts` | ← `CrowdSituation` أو `404` |
| استبدال جناح مزدحم (09.09) | `POST /plans/current/swap` | `{id: alternative_id}` ← `Plan` |
| تأجيل المزدحم | `POST /plans/current/postpone-crowded` | ← `Plan` |
| التراجع (10 دقائق) | `POST /plans/current/undo` | ← `Plan` |
| إنهاء الزيارة | `POST /plans/current/finish` | ← `204` |

قواعد يحتاجها التصميم من الخادم:

- **التغيير بعد موافقة فقط:** أي تغيير على الخطة يمر بمعاينة أولًا (`ReplanProposal.diff` و`impact`) ثم تأكيد صريح.
- **الورشة المثبتة:** العنصر المثبت (`is_priority`) لا يُحذف أبدًا في الاقتراحات.
- **مهلة التراجع:** يعيد الخادم `undo_available_until` و`last_change_description` بعد كل تغيير.

مثال `PlanPreferences`:

```json
{ "goals": ["learn","handsOn"], "axes": ["tech"], "sub_interests": ["الذكاء الاصطناعي"],
  "time": "twoHours", "custom_start": null, "custom_end": null,
  "comfort": ["lessWalking"], "must_not_miss": ["e-robot-workshop"] }
```

---

## 4. خريطتي — القاعة والبحث والتوجيه (خريطتي 1.x – 3.x)

| العملية | المسار | الرد |
|---|---|---|
| أجنحة القاعة مع الإحداثيات | `GET /map/booths` | `[Booth]` |
| المعالم (البوابات والساحات) | `GET /map/landmarks` | `[MapLandmark]` |
| الازدحام الحي | `GET /map/crowd` | `[CrowdHotspot]` |
| موقعي داخل القاعة | `GET /map/me` | `UserLocation` (انظري الملاحظة الأولى بعد الجدول) |
| بحث وتصفية | `GET /map/search?q=تقنية&category=companies&crowd=low&max_distance=200` | `[SearchResult]` مرتبة من الأقرب |
| طريقان إلى جناح (2.3) | `GET /map/routes?to=A7` | `[Route]`: `fastest` و`quietest` |
| طريق إلى صديقة أو نقطة التقاء | `GET /map/route?x=410&y=600` | `Route` |
| بدائل جناح مزدحم (3.2) | `GET /map/booths/{id}/alternatives` | `[BoothAlternative]` |
| تأكيد زيارة جناح (3.5) | `POST /visits` | `{id}` ← `BoothVisit` |
| ملاحظة الوصول (3.7) | `POST /visits/{boothId}/note` | `{text}` (حتى 200 حرف) ← `BoothVisit` |
| المحطة التالية (3.9) | `GET /map/next-stop` | `Booth` أو `null` |

- **إحداثيات القاعة:** المرجع مساحة القاعة في فيجما، أي **496 × 1357.8 نقطة**، وصورة القاعة مضمّنة في التطبيق (`map-exhibition-base`). كل `frame` و`label_point` و`path` بهذه الوحدات. إذا اختلف المرجع عند الخادم يلزم تحويل واحد في `MapModel`.
- **الموقع الداخلي:** تحديد مكان الزائر داخل القاعة يحتاج بنية تحتية، مثل Beacons أو UWB أو حزمة SDK من مزوّد خدمة. التطبيق يطلب إذن الموقع من iOS فعليًا، لكن **الإحداثيات تأتي من الخدمة**. يلزم الاتفاق على المصدر:
  - إما أن يرسل الجهاز قراءاته ويحسبها الخادم،
  - أو تحسبها حزمة على الجهاز.
- **ازدحام القاعة:** «ازدحام المعرض الآن» مستنتج حاليًا من نقاط الازدحام. نقترح إضافة `hall_level` إلى رد `GET /map/crowd`.
- **تقدّم التوجيه:** خطوات `Route.steps` تحمل نصوص التعليمات بالعربية وموضع كل خطوة. في الوضع التجريبي تتقدم الخطوات بمؤقّت؛ مع الخادم يجب أن يحرّكها الموقع الحقيقي، وإعادة الحساب (2.10) تحتاج حدثًا من مزوّد الموقع.

مثال `Booth`:

```json
{ "id": "A7", "name": "PwC", "category": "companies", "logo_text": "pwc",
  "summary": "استشارات الأعمال والتحول الرقمي، مع عروض حية للأمن السيبراني.",
  "frame": { "x": 57.66, "y": 447.89, "width": 120.9, "height": 46.5 },
  "label_point": { "x": 96.53, "y": 441.75 }, "entrance": "المدخل من الممر الغربي",
  "distance_meters": 180, "walk_minutes": 4, "crowd": "medium", "wait_minutes": null,
  "is_open": true, "is_free_entry": true, "updated_minutes_ago": 2, "photo": null, "interest_reason": null }
```

---

## 5. الأصدقاء ومشاركة الموقع ونقطة الالتقاء (خريطتي 4.x – 6.x)

| العملية | المسار | الطلب ← الرد |
|---|---|---|
| قائمة الأصدقاء | `GET /friends` | ← `[Friend]` |
| إنشاء رابط دعوة (4.2) | `POST /friends/invites` | ← `InviteLink` (صلاحيته 24 ساعة) |
| قراءة دعوة من QR أو رابط (4.8) | `GET /friends/invites/{code}` | ← `IncomingInvite` |
| قبول أو رفض دعوة | `POST /friends/invites/{id}/accept` و `/decline` | ← `Friend` / `204` |
| نوع المشاركة (5.1 – 5.4، 5.12) | `PUT /friends/{id}/sharing` | `{mode}` ← `Friend` |
| الاستمرار عند قفل الشاشة (5.15) | `PUT /friends/{id}/sharing/background` | `{enabled}` ← `Friend` |
| إظهار أو إخفاء الصديقة على الخريطة (5.9) | `PUT /friends/{id}/visibility` | `{enabled}` ← `Friend` |
| إيقاف المشاركة (5.16) | `DELETE /friends/{id}/sharing` | ← `Friend` |
| إزالة صديقة (5.18) | `DELETE /friends/{id}` | ← `204` |
| إنهاء الزيارة (5.21) | `POST /visits/end` | يوقف كل مشاركة لي فورًا ← `204` |
| نقاط التقاء مقترحة (6.1) | `GET /friends/{id}/meeting-points` | ← `[MeetingPoint]` |
| إرسال اقتراح التقاء (6.2) | `POST /friends/{id}/meetings` | `{id: point_id}` ← `MeetingState` |
| حالة الاقتراح (6.3 – 6.11) | `GET /friends/{id}/meetings/current` | ← `MeetingState` |

### قواعد الخصوصية التي يعتمد عليها التصميم

- **القبول وحده لا يشارك الموقع:** قبول الدعوة لا يبدأ المشاركة. القيمة الافتراضية `my_share = none`.
- **قراران مستقلان:** مشاركتي ومشاركة صديقتي معي (`shares_with_me`) منفصلتان.
- **الإخفاء عرض فقط:** إخفاء صديقة من خريطتي لا يغيّر شيئًا عندها.
- **الانتهاء التلقائي:** المشاركة المؤقتة تنتهي من جهة **الخادم** عند `my_share_ends_at`، ولا تعتمد على بقاء التطبيق مفتوحًا.
- **حداثة الموقع:** `location.updated_minutes_ago ≥ 10` يُعرض في التطبيق موقعًا قديمًا (5.8).
- **الأحداث الفورية (اقتراح):** اقتراح الالتقاء والرد عليه وتحديث موقع الصديقة تحتاج قناة فورية، مثل WebSocket أو SSE، وإشعارات APNs. التطبيق يستعلم مرة واحدة حاليًا. نقترح القناة `wss://…/v1/realtime` مع الأحداث التالية:
  - `friend.location`
  - `meeting.updated`
  - `invite.received`
  - `sharing.expiring`

مثال `Friend`:

```json
{ "id": "f-thikra", "name": "ذكرى", "avatar": "https://cdn…/thikra.jpg",
  "connected_since": "متصلتان منذ ٩:٣٥ م",
  "my_share": { "live": { "minutes": 60 } }, "my_share_ends_at": { "minutes": 1301 },
  "share_in_background": false, "shares_with_me": true, "is_visible_on_map": true,
  "location": { "point": { "x": 410, "y": 600 }, "area_text": "قرب ساحة الواحة",
                "distance_meters": 270, "walk_minutes": 6, "updated_minutes_ago": 0, "updated_at_text": "٩:٤١ م" } }
```

---

## 6. المساعد (12.x، خريطتي 7.x)

| العملية | المسار | الطلب ← الرد |
|---|---|---|
| بدء جلسة أو رسالة الترحيب | `POST /assistant/sessions` | `{text: "", context}` ← `AssistantReply` |
| إرسال سؤال | `POST /assistant/messages` | `{text, context}` ← `AssistantReply` |

- **السياق:** يحدد `context` الشاشة الحالية (`plan`، `map`، `pavilion`، `journey`، `general`).
- **البطاقات:** يمكن أن يحمل الرد بطاقة `card` من الأنواع التالية:
  - `plan_suggestion`
  - `alternatives`
  - `place`
  - `meeting_point`
- **مصدر البيانات:** إذا اعتمدت الإجابة على بيانات حية يُرسل `source_note`، مثل «الازدحام: بيانات الممرات قبل دقيقتين».
- **لا تغيير بلا تأكيد:** المساعد **لا ينفّذ أي تغيير بنفسه**. كل تغيير يمر بمعاينة يؤكدها المستخدم، ثم يستدعي التطبيق مسار الخطة أو الخريطة المناسب.
- **الصوت:** يتحول الصوت إلى نص **على الجهاز** باستخدام Speech، ولا يُرسل أي تسجيل صوتي إلى الخادم.

---

## 7. رحلتي والملاحظات وQR (13.x، 14.10 – 14.18، 17.x)

| العملية | المسار | الطلب ← الرد |
|---|---|---|
| زياراتي | `GET /journey/visits` | ← `[JourneyVisit]` |
| المحفوظات | `GET /journey/saved` | ← `[SavedPlace]` |
| حفظ أو إلغاء حفظ | `POST /journey/saved/toggle` | `{id}` ← `{saved: true}` |
| المتابعة | `GET /journey/follow-ups` | ← `[FollowUpItem]` |
| تعليم بند متابعة | `PUT /journey/follow-ups/{id}` | `{done}` ← `204` |
| ملاحظاتي | `GET /notes` | ← `[VisitNote]` |
| حفظ ملاحظة (upsert) | `PUT /notes/{id}` | `VisitNote` ← `VisitNote` |
| حذف ملاحظة | `DELETE /notes/{id}` | ← `204` |
| رفع مرفق | `POST /notes/{id}/attachments` (multipart) | ← `NoteAttachment` (`value` رابط) |
| تأكيد زيارة جناح | `POST /visits` | `{id}` ← `204` |
| قراءة رمز QR أو رمز يدوي (14.13 / 14.18) | `POST /qr/resolve` | `{code}` ← `ScannedPlace` · `422` إذا كان الرمز غير معروف |
| مسودة الملخص (13.07) | `POST /journey/summary` | ← `JourneySummary` |
| حفظ الملخص | `POST /journey/summaries` | `JourneySummary` ← `204` |
| الملخصات المحفوظة | `GET /journey/summaries` | ← `[JourneySummary]` |

- **الحفظ المحلي أولًا:** تُحفظ الملاحظات على الجهاز أولًا، والمعرّف `id` يولّده التطبيق (UUID)، لذلك **يجب أن يكون `PUT /notes/{id}` idempotent**. الطلبات التي تُرسل بعد انقطاع الاتصال قد تتكرر.
- **المرفقات:**
  - الصور تُحفظ حاليًا في مجلد التطبيق (`Application Support/Attachments`)، ولا تُرفع إلى أي مكان.
  - مسار الرفع أعلاه مقترح فقط.
  - الملاحظات الصوتية غير مفعّلة في هذه النسخة.
- **المسح ليس إثبات حضور:** المسح وحده **لا يُعد إثبات حضور**؛ الحالة تبقى `scanned_only` حتى يضغط المستخدم «أكد زيارتي».
- **الملخص مسودة:** الملخص الذي يكتبه المساعد مسودة لا تعدّل الملاحظات الأصلية، ولا تضيف مهارات إلى الملف المهني.

### المزامنة

نقترح أحد خيارين:

- **مسار واحد للدفعات:** `POST /sync` يستقبل مجموعة تغييرات `[{op, entity, id, payload, client_updated_at}]`، ويعيد نتيجة لكل عنصر.
- **الاكتفاء بـ idempotency:** الاعتماد على أن `PUT` لكل كيان idempotent.

الطبقة الحالية `SyncService` في الوضع التجريبي، وتُستبدل عند الاتفاق.

---

## 8. الملف المهني (14.01 – 14.09) والحساب (16.01)

| العملية | المسار | الطلب ← الرد |
|---|---|---|
| قراءة الملف | `GET /me/profile` | ← `ProfessionalProfile` أو `404` |
| حفظ الملف | `PUT /me/profile` | `ProfessionalProfile` ← نفسه |
| رفع السيرة الذاتية | `POST /me/profile/cv` (multipart, PDF) | ← `CVFile` |
| الرابط الحالي | `GET /me/profile/share-link` | ← `ProfileShareLink` أو `404` |
| إنشاء رابط وQR (14.04) | `POST /me/profile/share-link` | `{fields: [...], validity}` ← `ProfileShareLink` |
| تعطيل الرابط (14.09) | `DELETE /me/profile/share-link` | ← `204` |
| الصفحة العامة للمستلم (14.06 / 14.08) | `GET https://<domain>/p/{slug}` | صفحة HTML يقدمها الخادم، **لا تحتاج التطبيق** |

- **الحقول المشاركة فقط:** لا يُعرض للمستلم إلا الحقول المختارة في `fields`.
- **بعد التعطيل:** الصفحة العامة بعد التعطيل أو انتهاء الصلاحية تعرض 14.08.
- **ليست طلب توظيف:** لا يُرسل أي إشعار من نوع «راجعت الجهة ملفك» إلا إذا توفرت بيانات فعلية.

---

## 9. الإشعارات (4.16 / 4.17)

يطلب التطبيق إذن الإشعارات من iOS، لكنه **لا يسجّل رمز الجهاز (APNs token) في أي خادم** حاليًا. نقترح:

- **التسجيل:** `POST /devices` مع `{apns_token, platform: "ios"}`.
- **أنواع الإشعارات:**
  - `invite.received`
  - `meeting.proposed`
  - `meeting.answered`
  - `sharing.expiring` (قبل انتهاء المشاركة بـ 10 دقائق)
  - `plan.crowd_alert`
