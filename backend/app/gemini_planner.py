"""AI-guided event selection. The local Expo fixture is the only source of truth.

Gemini ranks immutable event and booth IDs. Python validates identities, scheduled
events, opening hours and durations; no model-created venue/time enters an itinerary.
Data files describe a simulated Expo, NOT the official Expo 2030 schedule.
"""
from __future__ import annotations

import json
import logging
import os
import time
import uuid
from dataclasses import dataclass

from . import storage

logger = logging.getLogger(__name__)


class PlannerError(Exception):
    def __init__(self, message: str, status: int = 422):
        super().__init__(message)
        self.status = status


CATEGORIES = {
    'tech': {'AI & Technology', 'Smart Cities', 'Mobility'},
    'earth': {'Sustainability'},
    'human': {'Health & Wellbeing', 'Education'},
    'culture': {'Culture'},
    'coop': {'Business'},
}
KEYWORDS = {
    'الذكاء الاصطناعي': ('AI', 'Machine Learning'),
    'التحول الرقمي': ('Data', 'Technology', 'AI'),
    'التقنية والابتكار': ('Innovation', 'Robotics', 'Technology'),
    'البيئة والمناخ': ('Climate', 'Sustainability'),
    'المياه': ('Water',),
    'الزراعة': ('Agriculture',),
    'الطاقة والاستدامة': ('Renewable Energy', 'Sustainability'),
    'التعليم': ('Education',),
    'الصحة': ('Health',),
    'تنمية المهارات': ('Education',),
    'جودة الحياة': ('Wellbeing', 'Health'),
    'الفنون': ('Culture', 'Arts'),
    'التراث': ('Culture', 'Heritage'),
    'السياحة والثقافة': ('Culture',),
    'الهوية': ('Culture',),
    'التعاون الدولي': ('Business',),
    'الشراكات': ('Business',),
    'الحلول العالمية': ('Business',),
}


def _minute(t):
    if not isinstance(t, str):
        raise PlannerError('وقت الفعالية غير صالح في البيانات.')
    hh, mm = t.split(':')
    return int(hh) * 60 + int(mm)


def _clock(m):
    return f'{m // 60:02d}:{m % 60:02d}'


def _validate_preferences(pref):
    if not isinstance(pref, dict):
        raise PlannerError('أرسلي تفضيلات الزيارة بصيغة JSON.')
    # Swift's JSONEncoder converts these properties to snake_case.
    pref = dict(pref)
    for camel, snake in (('customStart', 'custom_start'), ('customEnd', 'custom_end'),
                         ('subInterests', 'sub_interests'), ('mustNotMiss', 'must_not_miss')):
        if camel not in pref and snake in pref:
            pref[camel] = pref[snake]
    time = pref.get('time')
    if time not in ('oneHour', 'twoHours', 'halfDay', 'custom'):
        raise PlannerError('حدّدي مدة الزيارة أولًا.')
    axes = pref.get('axes') or []
    if not isinstance(axes, list) or not axes or not set(axes).issubset(CATEGORIES):
        raise PlannerError('اختاري محورًا واحدًا على الأقل.')
    goals = pref.get('goals') or []
    comfort = pref.get('comfort') or []
    subs = pref.get('subInterests') or []
    pinned = pref.get('mustNotMiss') or []
    for value in (goals, comfort, subs, pinned):
        if not isinstance(value, list) or len(value) > 100 or any(not isinstance(x, str) for x in value):
            raise PlannerError('الاختيارات المرسلة غير صحيحة.')
    if time == 'custom':
        def read_time(key):
            obj = pref.get(key)
            minutes = obj.get('minutes') if isinstance(obj, dict) else None
            if type(minutes) is not int or not 0 <= minutes <= 1440:
                raise PlannerError('حددي بداية ونهاية صحيحتين للزيارة.')
            return minutes
        start, end = read_time('customStart'), read_time('customEnd')
        if not 30 <= end - start <= 480:
            raise PlannerError('اختاري مدة مخصصة بين نصف ساعة وثماني ساعات في اليوم نفسه.')
    else:
        # No start clock is selected in the original iOS flow. Explicit demo assumption.
        start = 15 * 60
        end = start + {'oneHour': 60, 'twoHours': 120, 'halfDay': 240}[time]
    return start, end


def _score(event, booths, pref):
    score = 0
    selected_cats = set().union(*(CATEGORIES[ax] for ax in pref['axes']))
    if event['category'] in selected_cats:
        score += 10
    text = ' '.join([event['title_en'], event['title_ar'], event['category'],
                     ' '.join(event.get('tags', [])),
                     ' '.join(booths[event['booth_id']].get('interests', []))]).lower()
    for sub in pref.get('subInterests', []):
        if any(k.lower() in text for k in KEYWORDS.get(sub, (sub,))):
            score += 5
    goals = pref.get('goals', [])
    if 'handsOn' in goals and ('workshop' in text or 'تفاعلية' in text):
        score += 3
    if 'learn' in goals and ('expert' in text or 'مقدمة' in text):
        score += 2
    if 'networking' in goals and event['category'] == 'Business':
        score += 3
    if event['event_id'] in pref.get('mustNotMiss', []):
        score += 100
    return score


def _choose_ids_with_gemini(pref, candidates, max_count):
    key = os.getenv('GEMINI_API_KEY', '').strip()
    if not key:
        raise PlannerError('لم يتم إعداد GEMINI_API_KEY في ملف backend/.env.', 503)
    try:
        from google import genai
        from google.genai import types
        from pydantic import BaseModel, Field
    except ImportError as exc:
        raise PlannerError('ثبّتي مكتبة google-genai باستخدام pip install -r requirements.txt.', 503) from exc

    class EventChoices(BaseModel):
        event_ids: list[str] = Field(description='Ordered candidate IDs (event E... or booth B...) from the supplied candidates only.')

    prompt = json.dumps({
        'visitor_preferences': {k: pref.get(k, []) for k in ('axes', 'subInterests', 'goals', 'comfort', 'mustNotMiss')},
        'previous_plan_ids': pref.get('_previous_ids', []),
        'rules': [
            'Choose only exact event_id values in candidates. IDs may identify an event or a booth. Never fabricate places.',
            'Rank events by preferences and feasibility, including quiet/short walking preferences if data supports it.',
            'Return up to max_count IDs. Events have fixed schedules; booths have opening hours and flexible visit slots.',
            'Prefer pinned events only if their time fits and they do not conflict.',
            'When possible preserve previous_plan_ids while adapting to the new constraints.',
            'This is simulated Expo event data; do not present as real-world official schedule.'
        ],
        'max_count': max_count,
        'candidates': candidates,
    }, ensure_ascii=False)
    try:
        model = os.environ.get('GEMINI_MODEL', 'gemini-3.8-flash')
        client = genai.Client(api_key=key, http_options={'timeout': 45000})
        # Retry only transient server overload; never invent a Gemini result.
        for attempt in range(3):
            try:
                response = client.models.generate_content(
                    model=model,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type='application/json', response_schema=EventChoices,
                        temperature=0.2,
                    ),
                )
                break
            except Exception as transient:
                if getattr(transient, 'code', None) not in (500, 502, 503, 504) or attempt == 2:
                    raise
                time.sleep(0.8 * 2 ** attempt)
        parsed = json.loads(response.text or '{}')
        ids = parsed.get('event_ids', [])
        if not isinstance(ids, list) or not ids or not all(isinstance(x, str) for x in ids):
            raise ValueError('AI did not return an ordered list of IDs')
        return ids
    except Exception as exc:
        # Do not log API keys, raw HTTP requests or secret-bearing exception bodies.
        # Google SDK exposes the HTTP response code on errors.APIError.
        status_code = getattr(exc, 'code', None)
        logger.warning('Gemini generation failed; HTTP status=%s, exception=%s, model=%s',
                       status_code, type(exc).__name__, model)
        if status_code in (401, 403):
            message = 'مفتاح Gemini غير صالح أو لا يملك الصلاحية. تحققي من GEMINI_API_KEY في backend/.env.'
        elif status_code == 402:
            message = 'حساب Gemini يحتاج رصيدًا أو تفعيل الفوترة قبل إنشاء الخطط.'
        elif status_code == 404:
            message = f'مودل Gemini ({model}) غير متاح لهذا المفتاح؛ تحققي من GEMINI_MODEL.'
        elif status_code == 429:
            message = 'تجاوزتِ الحصة المتاحة لـGemini (429). تحققي من حدود الاستخدام وحاولي لاحقًا.'
        elif status_code == 400:
            message = 'رفض Gemini صيغة الطلب (400). شغّلي فحص Gemini لمعرفة تفاصيل السبب.'
        elif status_code in (408, 500, 502, 503, 504):
            message = f'خدمة Gemini غير متاحة مؤقتًا أو انتهت مهلة الاتصال ({status_code}). جرّبي لاحقًا.'
        elif isinstance(exc, (ValueError, TypeError, KeyError, json.JSONDecodeError)):
            message = 'استجابة Gemini لم تكن JSON صالحًا لمعرّفات الفعاليات. أعيدي المحاولة.'
        else:
            message = 'فشل اتصال Gemini أو حدث خطأ غير متوقع. شغّلي scripts/check_gemini.py للتشخيص.'
        raise PlannerError(message, 502) from exc


def priority_candidates():
    """Provide both IDs and clocks, so Swift can hide incompatible priority options."""
    booth_map = {b['booth_id']: b for b in storage.source('booths')}
    return [{'id': e['event_id'], 'title': e['title_ar'],
             'start_minutes': _minute(e['start_time']),
             'end_minutes': _minute(e['end_time']),
             'subtitle': f"{e['start_time']}–{e['end_time']} · {booth_map[e['booth_id']]['name_ar']}"}
            for e in storage.events()]


def _interest_terms(sub):
    return tuple(str(term).casefold() for term in KEYWORDS.get(sub, (sub,))) + (str(sub).casefold(),)


def _interest_match(event, booth, sub, *, precise=False):
    # Use catalog labels first; shared generic tags are weaker evidence.
    names = [booth.get('name_ar', ''), booth.get('name_en', '')]
    if event is not None:
        names.extend([event.get('title_ar', ''), event.get('title_en', '')])
    if precise:
        haystack = ' '.join(names).casefold()
    else:
        haystack = ' '.join(names + list(booth.get('interests', [])) +
                            (list(event.get('tags', [])) if event else [])).casefold()
    return any(term in haystack for term in _interest_terms(sub))


def _filter_by_interests(events, booths, pref, booth_map):
    subs = pref.get('subInterests') or pref.get('sub_interests') or []
    if not subs:
        return events, booths
    # For each chosen interest, prefer an exact topic visible in an event/booth
    # name if one exists, else fall back to the catalog's tags/interests.
    strict = {sub: any(_interest_match(e, booth_map[e['booth_id']], sub, precise=True)
                           for e in events) or
                   any(_interest_match(None, b, sub, precise=True) for b in booths)
              for sub in subs}
    def matches(e, b):
        return any(_interest_match(e, b, sub, precise=strict[sub]) for sub in subs)
    return ([e for e in events if matches(e, booth_map[e['booth_id']])],
            [b for b in booths if matches(None, b)])


def _booth_score(booth, pref):
    chosen = set().union(*(CATEGORIES[a] for a in pref['axes']))
    rating = 10 if booth['category'] in chosen else 0
    info = ' '.join([booth['name_en'], booth['name_ar'], booth['category'],
                     ' '.join(booth.get('interests', []))]).lower()
    for sub in pref.get('subInterests', []):
        if any(term.lower() in info for term in KEYWORDS.get(sub, (sub,))):
            rating += 5
    if 'stepFree' in pref.get('comfort', []) and 'Wheelchair accessible' in booth.get('accessibility', []):
        rating += 2
    return rating


def generate_options(pref, selector=None, *, forced_booth_id=None):
    """Create a feasible itinerary from dataset IDs; a conflicting pin never crashes the flow.

    The AI ranks event and booth candidates. All actual timings are computed by Python.
    Events cannot be moved; booths can be visited during their declared opening hours.
    A 20-minute booth dwell is an explicit planning estimate, not a published event.
    """
    if isinstance(pref, dict):
        pref = dict(pref)
        for camel, snake in (('subInterests', 'sub_interests'),
                             ('customStart', 'custom_start'),
                             ('customEnd', 'custom_end'),
                             ('mustNotMiss', 'must_not_miss')):
            if camel not in pref and snake in pref:
                pref[camel] = pref[snake]
    start, end = _validate_preferences(pref)
    booths = {b['booth_id']: b for b in storage.source('booths')}
    all_events = storage.events()
    by_id = {e['event_id']: e for e in all_events}
    pins = set(pref.get('mustNotMiss', []))
    if pins - by_id.keys():
        raise PlannerError('إحدى الفعاليات المختارة لم تعد موجودة في بيانات إكسبو.')
    chosen_categories = set().union(*(CATEGORIES[a] for a in pref['axes']))

    # Events are valid only if the ENTIRE scheduled session fits the visit.
    valid_events = [e for e in all_events
                    if _minute(e['start_time']) >= start
                    and _minute(e['end_time']) <= end
                    and (e['category'] in chosen_categories or e['event_id'] in pins)]
    valid_event_ids = {e['event_id'] for e in valid_events}
    skipped = [by_id[x]['title_ar'] for x in sorted(pins - valid_event_ids)]
    active_pins = pins & valid_event_ids

    # Booth visits are flexible but must fit the booth's real data opening hours.
    valid_booths = [b for b in booths.values()
                    if (b['category'] in chosen_categories or b['booth_id'] == forced_booth_id)
                    and max(start, _minute(b['opening_time'])) + 20 <=
                    min(end, _minute(b['closing_time']))]
    valid_events, valid_booths = _filter_by_interests(valid_events, valid_booths, pref, booths)
    if not valid_events and not valid_booths:
        raise PlannerError('لا توجد فعاليات أو بوثات تطابق الاهتمامات المختارة خلال وقت الزيارة. غيّري الوقت أو الاهتمامات.')

    valid_events.sort(key=lambda e: (-_score(e, booths, pref), e['start_time'], e['event_id']))
    valid_booths.sort(key=lambda b: (-_booth_score(b, pref), b['booth_id']))
    # Hard cap on prompt size; pins are always explicitly included.
    listed_events = valid_events[:45]
    existing = {e['event_id'] for e in listed_events}
    listed_events.extend(by_id[x] for x in sorted(active_pins) if x not in existing)
    listed_booths = valid_booths[:32]
    if forced_booth_id and forced_booth_id not in {b['booth_id'] for b in listed_booths}:
        listed_booths.extend(b for b in valid_booths if b['booth_id'] == forced_booth_id)
    candidates = [{
        'event_id': e['event_id'], 'kind': 'event', 'name': e['title_ar'],
        'category': e['category'], 'tags': e.get('tags', []),
        'start_time': e['start_time'], 'end_time': e['end_time'],
        'booth_id': e['booth_id'], 'booth_name': booths[e['booth_id']]['name_ar'],
        'floor': booths[e['booth_id']]['floor'],
        'x': booths[e['booth_id']]['x'], 'y': booths[e['booth_id']]['y'],
    } for e in listed_events]
    candidates += [{
        'event_id': b['booth_id'], 'kind': 'booth', 'name': b['name_ar'],
        'category': b['category'], 'tags': b.get('interests', []),
        'opening_time': b['opening_time'], 'closing_time': b['closing_time'],
        'floor': b['floor'], 'x': b['x'], 'y': b['y'],
    } for b in listed_booths]
    ranker = selector or _choose_ids_with_gemini
    requested = ranker(pref, candidates, 10)
    if not isinstance(requested, list) or any(not isinstance(x, str) for x in requested):
        raise PlannerError('استجابة اختيار الأماكن غير صالحة.', 502)
    allowed = {x['event_id'] for x in candidates}
    if any(x not in allowed for x in requested):
        raise PlannerError('أعاد Gemini معرّفًا غير موجود في بياناتنا؛ أعيدي المحاولة.', 502)

    # A pin that clashes with another is not placed at a false time: skip the
    # lower-priority one and explain it to the visitor in the plan notes.
    selected_events = []
    for e in sorted((by_id[x] for x in active_pins), key=lambda e: (e['start_time'], e['event_id'])):
        a, b = _minute(e['start_time']), _minute(e['end_time'])
        if len(selected_events) >= (6 if end - start > 120 else 4):
            skipped.append(e['title_ar'] + ' (لا يتسع الوقت)')
            continue
        if any(a < _minute(other['end_time']) + 5 and
               _minute(other['start_time']) < b + 5 for other in selected_events):
            skipped.append(e['title_ar'] + ' (تعارض في الموعد)')
            continue
        selected_events.append(e)

    event_lookup = {e['event_id']: e for e in listed_events}
    # Fill event preferences from AI order, then scoring order if AI gives only
    # booth suggestions or sessions too close to each other.
    ranked_events = list(dict.fromkeys([x for x in requested if x in event_lookup] +
                                       [e['event_id'] for e in listed_events]))
    max_stops = 6 if end - start > 120 else 4
    # Reserve a booth slot when Gemini explicitly recommends a booth.
    AI_recommended_booth = any(x in {b['booth_id'] for b in listed_booths} for x in requested)
    event_cap = max_stops - (1 if (AI_recommended_booth or forced_booth_id) and valid_booths else 0)
    for identifier in ranked_events:
        if len(selected_events) >= max(len(selected_events), event_cap):
            break
        if identifier in active_pins:
            continue
        event = event_lookup[identifier]
        a, b = _minute(event['start_time']), _minute(event['end_time'])
        if any(a < _minute(other['end_time']) + 5 and
               _minute(other['start_time']) < b + 5 for other in selected_events):
            continue
        selected_events.append(event)
    selected_events.sort(key=lambda e: (_minute(e['start_time']), e['event_id']))

    # Flexible booth visits fill the available gaps. Never claim these are
    # scheduled performances, and always honor opening hours in source JSON.
    # An explicitly added booth can replace a non-pinned event if the current
    # events fill the entire visit. Never remove a visitor's fixed priority.
    if forced_booth_id:
        forced = booths[forced_booth_id]
        def has_booth_slot(events):
            last = start
            for session in events:
                a = _minute(session['start_time'])
                b = _minute(session['end_time'])
                t = max(last, _minute(forced['opening_time']))
                if t + 20 <= min(a - 5, _minute(forced['closing_time'])):
                    return True
                last = b + 5
            t = max(last, _minute(forced['opening_time']))
            return t + 20 <= min(end, _minute(forced['closing_time']))
        if not has_booth_slot(selected_events):
            for event in list(reversed(selected_events)):
                if event['event_id'] in active_pins:
                    continue
                selected_events.remove(event)
                if has_booth_slot(selected_events):
                    break
    occupied = [(_minute(e['start_time']), _minute(e['end_time'])) for e in selected_events]
    free_intervals = []
    cursor = start
    for a, b in occupied:
        if cursor < a:
            free_intervals.append((cursor, max(cursor, a - 5)))
        cursor = max(cursor, b + 5)
    if cursor < end:
        free_intervals.append((cursor, end))

    booth_lookup = {b['booth_id']: b for b in listed_booths}
    booth_order = list(dict.fromkeys([x for x in requested if x in booth_lookup] +
                                   [b['booth_id'] for b in listed_booths]))
    picked_booths = []
    # The requested extra booth is mandatory; it must occupy a real free interval.
    if forced_booth_id:
        requested_booth = booths.get(forced_booth_id)
        if not requested_booth:
            raise PlannerError('البوث المطلوب غير موجود في بيانات إكسبو.')
        if len(selected_events) >= max_stops:
            raise PlannerError('لا توجد مساحة لمحطة إضافية مع الحفاظ على فعالياتك المثبتة.')
        for gap_start, gap_end in free_intervals:
            t = max(gap_start, _minute(requested_booth['opening_time']))
            if t + 20 <= min(gap_end, _minute(requested_booth['closing_time'])):
                picked_booths.append((t, requested_booth))
                break
        if not picked_booths:
            raise PlannerError('ما فيه 20 دقيقة متاحة لإضافة هذا البوث دون تعارض. اختاري محطة ثانية أو مددي وقت الزيارة.')
    busy_booths = {e['booth_id'] for e in selected_events} | {b['booth_id'] for _, b in picked_booths}
    for gap_start, gap_end in free_intervals:
        slot = gap_start
        if picked_booths and gap_start <= picked_booths[0][0] < gap_end:
            # Reserve this interval for the explicitly requested booth.
            slot = max(slot, picked_booths[0][0] + 25)
        while slot + 20 <= gap_end and len(selected_events) + len(picked_booths) < max_stops:
            feasible = []
            for identifier in booth_order:
                if identifier in busy_booths:
                    continue
                booth = booth_lookup[identifier]
                at = max(slot, _minute(booth['opening_time']))
                if at + 20 <= min(gap_end, _minute(booth['closing_time'])):
                    feasible.append((at, booth))
            if not feasible:
                break
            # Earlier times use more of the visitor's window. AI decides which
            # item is preferred when equal; none of this is a measured walk time.
            feasible.sort(key=lambda item: (item[0], booth_order.index(item[1]['booth_id'])))
            slot, booth = feasible[0]
            picked_booths.append((slot, booth))
            busy_booths.add(booth['booth_id'])
            slot += 25  # estimated 20-minute visit + 5-minute planning buffer

    steps = []
    for event in selected_events:
        booth = booths[event['booth_id']]
        steps.append((_minute(event['start_time']), event['event_id'], {
            'time': {'minutes': _minute(event['start_time'])},
            'kind': {'experience': {'place_id': event['event_id']}},
            'title': event['title_ar'],
            'subtitle': f"فعالية {_clock(_minute(event['start_time']))}–{event['end_time']} · {booth['name_ar']}",
            'is_priority': event['event_id'] in active_pins,
            'live_state': 'upcoming', 'change': {'none': {}},
        }))
    for visit_time, booth in picked_booths:
        steps.append((visit_time, booth['booth_id'], {
            'time': {'minutes': visit_time},
            'kind': {'experience': {'place_id': booth['booth_id']}},
            'title': 'زيارة بوث: ' + booth['name_ar'],
            'subtitle': f"زيارة مقترحة 20 دقيقة · {booth['hall']} · الطابق {booth['floor']}",
            'is_priority': False, 'live_state': 'upcoming', 'change': {'none': {}},
        }))
    steps.sort(key=lambda item: (item[0], item[1]))
    if not steps:
        raise PlannerError('ما فيه محطات ممكن جدولتها ضمن هذا الوقت. جربي مدة أطول أو وقتًا آخر.')
    for idx, (_, _, payload) in enumerate(steps, 1):
        payload['id'] = 'ai-step-' + str(idx)

    pinned_titles = [e['title_ar'] for e in selected_events if e['event_id'] in active_pins]
    priority = '، '.join(pinned_titles) if pinned_titles else 'بدون فعاليات إلزامية'
    details = ['وقت المشي يُحتسب تقديريًا بخمس دقائق بين كل محطتين.']
    if skipped:
        details.append('لم نضف أولويات خارج الوقت أو المتعارضة: ' + '، '.join(skipped[:4]) + '.')
    if picked_booths:
        details.append('مدة كل زيارة بوث 20 دقيقة تقديرية، وليست موعد فعالية ثابتًا.')
    total_minutes = sum(_minute(e['end_time']) - _minute(e['start_time']) for e in selected_events) + 20 * len(picked_booths)
    estimated_walking_minutes = max(0, len(steps) - 1) * 5
    return [{
        'id': 'gemini-' + uuid.uuid4().hex[:14],
        'name': 'خطتك حسب اهتماماتك',
        'metrics': {
            'stops_text': f'{len(steps)} محطات', 'walking_minutes': estimated_walking_minutes,
            'experience_minutes': total_minutes, 'rest_minutes': 0,
            'estimated_wait_text': 'بحسب وقت الوصول',
            'priority_text': priority,
        },
        'gains': 'اختيارات Gemini من فعاليات وبوثات إكسبو، مع التحقق من مواعيد الفعاليات وساعات فتح البوثات.',
        'tradeoffs': ' '.join(details),
        'steps': [item[2] for item in steps],
        'is_recommended': True,
    }]


# Replanning always makes a NEW Gemini ranking request for the remaining window.
# This modifies only a proposed itinerary. Persistence is an explicit second step.
def regenerate_plan(current, preferences, reason, selector=None):
    if not isinstance(current, dict) or not isinstance(current.get('steps'), list):
        raise PlannerError('لا توجد خطة محفوظة لتعديلها.', 404)
    if not isinstance(preferences, dict):
        raise PlannerError('لم نجد تفضيلات الخطة السابقة؛ أنشئي خطة جديدة أولًا.', 422)
    if not isinstance(reason, dict) or len(reason) != 1:
        raise PlannerError('نوع التعديل غير معروف.')
    kind = next(iter(reason))
    details = reason[kind]
    if not isinstance(details, dict) or kind not in ('late', 'needBreak', 'addedItem'):
        raise PlannerError('نوع التعديل غير مدعوم.')

    start, end = _validate_preferences(preferences)
    start = current.get('visit_start_minutes', start)
    if type(start) is not int:
        raise PlannerError('بداية الزيارة غير صالحة في الخطة المحفوظة.')
    # Honor the end of the currently adopted plan, not another user's plan.
    stored_end = current.get('ends_at')
    if isinstance(stored_end, dict) and type(stored_end.get('minutes')) is int:
        end = min(end, stored_end['minutes'])
    pause = 0
    forced_booth = None
    requested_id = None
    explanation = 'أعيد ترتيب محطات الزيارة باستخدام Gemini.'
    if kind == 'late':
        minutes = details.get('minutes')
        if type(minutes) is not int or not 1 <= minutes <= 120:
            raise PlannerError('حدّدي تأخيرًا من دقيقة إلى 120 دقيقة.')
        start += minutes
        explanation = f'أعيد ترتيب المحطات بعد تأخير {minutes} دقيقة.'
    elif kind == 'needBreak':
        pause = 15
        start += pause
        explanation = 'أُضيفت استراحة 15 دقيقة في بداية الجزء المتبقي من الزيارة.'
    else:
        requested_id = details.get('title')  # Existing Swift enum field carries the catalog ID.
        if not isinstance(requested_id, str) or len(requested_id) > 30:
            raise PlannerError('المحطة المطلوبة غير صالحة.')
        events = {e['event_id']: e for e in storage.events()}
        booths = {b['booth_id']: b for b in storage.source('booths')}
        if requested_id not in events and requested_id not in booths:
            raise PlannerError('المحطة المطلوبة غير موجودة في بيانات إكسبو.')
        if requested_id in booths:
            forced_booth = requested_id
        explanation = 'تمت إعادة ترتيب الخطة لإضافة المحطة المطلوبة.'
    if end - start < 30:
        raise PlannerError('الوقت المتبقي قصير جدًا لإعادة التخطيط. مددي الزيارة أو اختاري تعديلًا أصغر.')

    # Previous explicit priorities remain preferred, but never get falsified or
    # shifted to a time different from the immutable event schedule.
    existing_ids = [step.get('kind', {}).get('experience', {}).get('place_id')
                    for step in current['steps'] if isinstance(step.get('kind'), dict)]
    existing_ids = [x for x in existing_ids if isinstance(x, str)]
    old_pinned = [step.get('kind', {}).get('experience', {}).get('place_id')
                  for step in current['steps'] if step.get('is_priority') and 'experience' in step.get('kind', {})]
    new_pref = dict(preferences)
    new_pref['time'] = 'custom'
    new_pref['customStart'] = {'minutes': start}
    new_pref['customEnd'] = {'minutes': end}
    new_pref['mustNotMiss'] = sorted(set(preferences.get('mustNotMiss', preferences.get('must_not_miss', []))) | set(old_pinned))
    if requested_id and requested_id.startswith('E'):
        new_pref['mustNotMiss'].append(requested_id)
    new_pref['_previous_ids'] = existing_ids  # Context passed to Gemini only.

    result = generate_options(new_pref, selector=selector, forced_booth_id=forced_booth)[0]
    generated_steps = result['steps']
    generated_ids = {step['kind']['experience']['place_id'] for step in generated_steps}
    if requested_id and requested_id not in generated_ids:
        raise PlannerError('المحطة المطلوبة تتعارض مع مواعيد الخطة. اختاري محطة أخرى أو غيّري وقت زيارتك.')
    if pause:
        generated_steps.insert(0, {
            'id': 'rest-' + uuid.uuid4().hex[:10],
            'time': {'minutes': start - pause},
            'kind': {'rest': {'minutes': pause}},
            'title': 'استراحة 15 دقيقة',
            'subtitle': 'فترة راحة مقترحة · المكان الفعلي غير محدد',
            'is_priority': False, 'live_state': 'upcoming', 'change': {'none': {}},
        })

    updated = {
        'id': current['id'],
        'name': current['name'],
        'summary': 'تم تحديث الخطة باستخدام Gemini',
        'steps': generated_steps,
        'ends_at': {'minutes': end},
        'visit_start_minutes': start,
        'last_change_description': explanation,
        'undo_available_until': None,
    }
    old_steps = {st['kind']['experience']['place_id']: st for st in current['steps']
                 if 'experience' in st.get('kind', {})}
    new_steps = {st['kind']['experience']['place_id']: st for st in generated_steps
                 if 'experience' in st.get('kind', {})}
    diffs = []
    def diff_item(kind_, step, desc):
        diffs.append({'id': str(uuid.uuid4()), 'kind': kind_, 'title': step['title'], 'detail': desc})
    for identifier, step in old_steps.items():
        if identifier not in new_steps:
            diff_item('removed', step, 'خارج الوقت الجديد أو تم استبدالها بمناسبة أكثر')
        elif step['time'] != new_steps[identifier]['time']:
            diff_item('changed', new_steps[identifier], 'تم تعديل توقيت زيارة البوث حسب الوقت المتاح')
    for identifier, step in new_steps.items():
        if identifier not in old_steps:
            diff_item('added', step, 'اختيار جديد من بيانات إكسبو')
    if pause:
        diff_item('added', generated_steps[0], 'استراحة 15 دقيقة قبل المحطات التالية')
    if not diffs:
        first = generated_steps[0]
        diff_item('kept', first, 'هذه المحطة لا تحتاج تغييرًا')
    diff_count = lambda steps: len([x for x in steps if 'experience' in x.get('kind', {})])
    impact = [
        {'title': 'المحطات', 'before': str(diff_count(current['steps'])), 'after': str(diff_count(generated_steps))},
        {'title': 'وقت النهاية', 'before': _clock(current.get('ends_at', {}).get('minutes', end)), 'after': _clock(end)},
    ]
    return {'id': str(uuid.uuid4()), 'reason': reason, 'diff': diffs[:20],
            'impact': impact, 'after': updated}
