# توليد خطط إكسبو باستخدام Gemini + Flask + SwiftUI

أضفنا تخطيطًا باستخدام Gemini **بعد تسجيل الدخول** بالاعتماد فقط على الفعاليات الموجودة في `backend/data/events.json`، والأجنحة/الأكشاك في `backend/data/booths.json`.
هذه ملفات **محاكاة** لإكسبو وليست فعاليات رسمية لإكسبو 2030.

## 1. إعداد المفتاح على الماك

احصلي على مفتاح من https://aistudio.google.com/apikey (لا ترسليه لأحد ولا تضعيه في Swift).

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
cp .env.example .env
```

افتحي ملف `backend/.env` وضعي المفتاح في السطر `GEMINI_API_KEY=...`، **بدون مشاركة الملف أو إضافته إلى GitHub**.
المودل الافتراضي: `gemini-2.5-flash`، قابل للتغيير عبر `GEMINI_MODEL`.

## 2. تشغيل السيرفر

```bash
python3 -m app.main
```

تأكدي من `curl http://127.0.0.1:8001/health` ثم افتحي `Expo2030.xcodeproj` على محاكي آيفون وشغّليه بـ ⌘R. Xcode Scheme / Run / Arguments يجب أن يحتوي `EXPO_API_MODE=live`؛ وربط Swift للسيرفر مضبوط على `127.0.0.1:8001` للمحاكي على نفس الماك.

## 3. رحلة الاستخدام

تسجيل الدخول ← 6 أسئلة التخصيص الحالية ← زر «كوّن خطتي» ← طلب `/plans/generate` المحمي بتوكن الحساب ← Gemini يرجع معرفات فعاليات وبوثات فقط ← Flask يتحقق من المعرفات والمواعيد وعدم التداخل ← شاشة مقارنة الخطة ← «اعتمد» ← حفظ `plan` و`preferences` في قاعدة `instance/expo_users.sqlite3`.

> **مهم:** لو ما فيه مفتاح Gemini أو تعذر الاتصال، سيظهر خطأ؛ لن نعرض خطة mock على أنها ناتجة عن AI.

## 4. حدود الإصدار

- في الاختيارات غير المخصصة، وقت البداية الافتراضي **15:00** لتجربة التطبيق، وليس موقع المستخدم الزمني. اختيار المدة المخصصة يسمح بتحديد البداية والنهاية بدقة.
- حساب المسار والمشي والازدحام والحجوزات لا يدخل في هذا الإصدار من إنشاء الخطط؛ هذه المعلومات غير مؤكدة. كما أن أحداث Gemini الجديدة تستعمل معرّفات `E...` من بيانات Flask، بينما بعض صفحات تفاصيل التطبيق الحالية تستخدم بيانات mock مختلفة، لذا لا تفتح هذه التفاصيل الخاطئة.
- تعديل خطة Gemini يتم بإعادة أسئلة التخصيص من زر «تعديل»، ولا يُستخدم منطق تعديل `MockPlans` القديم حتى لا يخلط الأحداث الحقيقية للتطبيق التجريبي مع أحداث مختلقة.
- لا تختبر الخطة ببيانات المعرض الواقعية قبل توفر مصدر رسمي للأحداث، الوقت، المواقع ومسارات المشي.
- `API_BASE_URL=http://127.0.0.1:8001` يخص محاكي iOS على الماك. الآيفون الحقيقي يحتاج URL خارجيًا قابلًا للوصول وHTTPS في الإنتاج.

## 5. التحقق من حفظ الخطة والحساب

```bash
cd backend
sqlite3 instance/expo_users.sqlite3 'SELECT name,email FROM users;'
sqlite3 instance/expo_users.sqlite3 "SELECT u.email, s.kind, substr(s.payload,1,130) FROM user_state s JOIN users u ON u.id=s.user_id WHERE s.kind IN ('plan','preferences');"
```

## 6. نقاط التكامل

- Flask: `backend/app/gemini_planner.py` و `backend/app/user_api.py`.
- Swift: `Expo2030/Services/Live/PersistentServices.swift`, `Expo2030/Services/AppServices.swift`.
- شاشة التخصيص الحالية: `Expo2030/Features/Personalization/PersonalizationFlowView.swift`.
- تدعم `GET /plans/priority-candidates` فعالية مفضلة ذات ID حقيقي من dataset، و`POST /plans/generate` إنشاء خطة ببيانات JSON أصلية بعد تسجيل الدخول.
