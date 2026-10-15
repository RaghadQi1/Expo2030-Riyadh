"""REST endpoints for authenticated, durable user data (not demo map fixtures)."""
from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import sqlite3
from datetime import timedelta
from zoneinfo import ZoneInfo
from functools import wraps
from urllib.parse import quote

from flask import Blueprint, g, jsonify, request, Response

from . import user_db as store

bp = Blueprint('users', __name__)


def error(message, status=422, fields=None):
    return jsonify({'code':'invalid_request' if status == 422 else 'request_failed',
                    'message':message, 'fields':fields or {}}), status


def body_object():
    obj = request.get_json(silent=True)
    return obj if isinstance(obj, dict) else None


def authenticated(fn):
    @wraps(fn)
    def wrapped(*args, **kwargs):
        header = request.headers.get('Authorization', '')
        token = header[7:] if header.startswith('Bearer ') else None
        g.user = store.authenticate(token)
        if g.user is None:
            return error('تحتاج إلى تسجيل الدخول.', 401)
        return fn(*args, **kwargs)
    return wrapped


@bp.post('/auth/register')
def register():
    """Create a usable account immediately; no mail dispatch or verification step."""
    data = body_object()
    if data is None: return error('JSON object required')
    name = str(data.get('name', '')).strip()
    email = str(data.get('email', '')).strip().lower()
    password = data.get('password')
    if not (1 <= len(name) <= 150): return error('الاسم مطلوب (حتى 150 حرف).')
    if len(email) > 250 or not store.EMAIL.fullmatch(email): return error('البريد الإلكتروني غير صالح.')
    if not store.strong_password(password, email): return error('كلمة المرور تحتاج 8 أحرف، حروف كبيرة وصغيرة ورقم.')
    if data.get('accepted_terms') is not True: return error('يلزم الموافقة على الشروط.')
    try:
        with store.db() as con:
            uid = secrets.token_hex(16)
            # Email ownership is NOT confirmed: verified stays 0.
            con.execute("""INSERT INTO users(id,email,name,password_hash,marketing_opt_in,created_at)
                           VALUES(?,?,?,?,?,?)""",
                        (uid,email,name,store.hash_password(password),int(data.get('marketing_opt_in') is True),store.timestamp()))
            user = con.execute('SELECT * FROM users WHERE id=?',(uid,)).fetchone()
            return jsonify(store.issue_session(con,user)), 201
    except sqlite3.IntegrityError:
        return error('البريد مسجّل بالفعل. سجّلي الدخول بحسابك.',409)


@bp.post('/auth/login')
def login():
    data = body_object()
    if not data: return error('البريد وكلمة المرور مطلوبان.')
    email = str(data.get('email','')).strip().lower()
    password = data.get('password')
    if not isinstance(password,str): return error('بيانات الدخول غير صحيحة.',401)
    with store.db() as con:
        user = con.execute('SELECT * FROM users WHERE email=?',(email,)).fetchone()
        if user is None or not store.valid_password(user['password_hash'],password):
            return error('بيانات الدخول غير صحيحة.',401)
        return jsonify(store.issue_session(con,user))


@bp.get('/me')
@authenticated
def me():
    return jsonify(store.user_response(g.user))


@bp.patch('/me')
@authenticated
def update_me():
    data = body_object()
    if data is None: return error('JSON object required')
    name = str(data.get('display_name','')).strip()
    if not 1 <= len(name) <= 150: return error('اسم العرض غير صالح.')
    with store.db() as con:
        con.execute('UPDATE users SET name=? WHERE id=?',(name,g.user['id']))
        user = con.execute('SELECT * FROM users WHERE id=?',(g.user['id'],)).fetchone()
        return jsonify(store.issue_session(con,user))


@bp.post('/auth/logout')
@authenticated
def logout():
    token = request.headers.get('Authorization','')[7:]
    with store.db() as con:
        con.execute('DELETE FROM sessions WHERE token_hash=?',(hashlib.sha256(token.encode()).hexdigest(),))
    return jsonify({})


@bp.get('/me/profile')
@authenticated
def get_profile():
    with store.db() as con:
        row = con.execute('SELECT payload FROM profiles WHERE user_id=?',(g.user['id'],)).fetchone()
    return jsonify(store.as_json(row)) if row else error('Profile not found',404)


@bp.put('/me/profile')
@authenticated
def save_profile():
    data = body_object()
    if data is None: return error('JSON object required')
    # Swift JSONEncoder uses convertToSnakeCase; refuse unexpected attributes on public profiles.
    if not set(data).issubset(store.PROFILE_KEYS): return error('Unsupported profile fields')
    if len(json.dumps(data,ensure_ascii=False)) > 100_000: return error('Profile too large',413)
    data['display_name'] = str(data.get('display_name') or g.user['name'])[:150]
    if not isinstance(data.get('experiences',[]),list) or not isinstance(data.get('skills',[]),list):
        return error('experiences/skills must be arrays')
    with store.db() as con:
        con.execute('''INSERT INTO profiles(user_id,payload,updated_at) VALUES(?,?,?)
                       ON CONFLICT(user_id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at''',
                    (g.user['id'],json.dumps(data,ensure_ascii=False),store.timestamp()))
    return jsonify(data)


def public_url(slug):
    root = os.environ.get('EXPO_PUBLIC_BASE_URL','http://127.0.0.1:8001').rstrip('/')
    return f'{root}/p/{quote(slug)}'


def share_response(row):
    expires = row['expires_at']
    active = bool(row['active']) and expires > store.timestamp()
    return {'url': public_url(row['slug']), 'fields':json.loads(row['fields']),
            'validity':row['validity'], 'valid_until_text': 'صالح حتى ' + expires[:16] + ' UTC',
            'is_active':active}


@bp.get('/me/profile/share-link')
@authenticated
def current_share():
    with store.db() as con:
        row = con.execute('SELECT * FROM share_links WHERE user_id=? ORDER BY rowid DESC LIMIT 1',(g.user['id'],)).fetchone()
        return jsonify(share_response(row)) if row else error('Share link not found',404)


@bp.post('/me/profile/share-link')
@authenticated
def create_share():
    data = body_object() or {}
    fields = data.get('fields')
    validity = data.get('validity')
    if not isinstance(fields,list) or not fields or not set(fields).issubset(store.SHARE_KEYS):
        return error('Invalid shared fields')
    if validity not in {'oneHour','today','oneDay','oneWeek'}: return error('Invalid expiry')
    now = store.utc_now()
    if validity == 'today':
        today_riyadh = now.astimezone(ZoneInfo('Asia/Riyadh'))
        until = today_riyadh.replace(hour=23,minute=59,second=59,microsecond=0).astimezone(store.timezone.utc)
    else:
        until = now + timedelta(seconds={'oneHour':3600,'oneDay':86400,'oneWeek':604800}[validity])
    slug = secrets.token_urlsafe(24)
    with store.db() as con:
        con.execute('UPDATE share_links SET active=0 WHERE user_id=?',(g.user['id'],))
        con.execute('INSERT INTO share_links(slug,user_id,fields,validity,expires_at) VALUES(?,?,?,?,?)',
                    (slug,g.user['id'],json.dumps(fields),validity,store.timestamp(until)))
        row=con.execute('SELECT * FROM share_links WHERE slug=?',(slug,)).fetchone()
    return jsonify(share_response(row)),201


@bp.delete('/me/profile/share-link')
@authenticated
def disable_share():
    with store.db() as con:
        con.execute('UPDATE share_links SET active=0 WHERE user_id=?',(g.user['id'],))
    return jsonify({})


@bp.get('/p/<slug>')
def public_profile(slug):
    with store.db() as con:
        link = con.execute('SELECT * FROM share_links WHERE slug=? AND active=1 AND expires_at>?',
                           (slug,store.timestamp())).fetchone()
        if not link: return error('Share link expired or disabled',404)
        row = con.execute('SELECT payload FROM profiles WHERE user_id=?',(link['user_id'],)).fetchone()
        if not row: return error('Profile missing',404)
    source = store.as_json(row)
    allowed = set(json.loads(link['fields']))
    exposed = {'display_name':source.get('display_name','')}
    mapping={'jobTitle':['job_title'],'bio':['bio'],'education':['education'],
             'experiences':['experiences'],'skills':['skills'],'links':['linked_in','website'],
             'contact':['preferred_contact','contact_goal'],'cv':['cv']}
    for group,keys in mapping.items():
        if group in allowed:
            for k in keys: exposed[k]=source.get(k)
    if 'cv' in allowed:
        exposed['cv_url'] = public_url(slug) + '/cv'
    response = jsonify(exposed)
    response.headers['Cache-Control'] = 'private, no-store'
    return response


@bp.get('/notes')
@authenticated
def list_notes():
    with store.db() as con: return jsonify(store.list_json(con,'notes',g.user['id'],'updated_at'))


@bp.put('/notes/<note_id>')
@authenticated
def save_note(note_id):
    data=body_object()
    if data is None or data.get('id')!=note_id or len(json.dumps(data))>250_000:
        return error('Invalid note')
    data['is_pending_sync']=False
    with store.db() as con: store.put_json(con,'notes',g.user['id'],note_id,data,'updated_at')
    return jsonify(data)


@bp.delete('/notes/<note_id>')
@authenticated
def delete_note(note_id):
    with store.db() as con: con.execute('DELETE FROM notes WHERE id=? AND user_id=?',(note_id,g.user['id']))
    return jsonify({})


@bp.get('/journey/saved')
@authenticated
def saved():
    with store.db() as con: return jsonify(store.list_json(con,'saved_places',g.user['id']))


@bp.post('/journey/saved/toggle')
@authenticated
def toggle_saved():
    data=body_object() or {}
    item_id=data.get('id')
    if not isinstance(item_id,str) or not 1<=len(item_id)<=150: return error('Invalid place id')
    with store.db() as con:
        has=con.execute('SELECT 1 FROM saved_places WHERE id=? AND user_id=?',(item_id,g.user['id'])).fetchone()
        if has:
            con.execute('DELETE FROM saved_places WHERE id=? AND user_id=?',(item_id,g.user['id']))
        else:
            value={k:data.get(k) for k in ('id','title','subtitle','photo')}
            value['title'] = value.get('title') or item_id
            value['subtitle'] = value.get('subtitle') or ''
            store.put_json(con,'saved_places',g.user['id'],item_id,value)
    return jsonify({'saved':not bool(has)})


@bp.get('/journey/visits')
@authenticated
def list_visits():
    with store.db() as con: return jsonify(store.list_json(con,'visits',g.user['id']))


@bp.post('/visits')
@authenticated
def confirm_visit():
    data=body_object() or {}
    item_id=data.get('id')
    if not isinstance(item_id,str) or not 1<=len(item_id)<=150: return error('Invalid visit id')
    now=store.utc_now().astimezone(ZoneInfo('Asia/Riyadh'))
    minutes=now.hour*60+now.minute
    # Date/time use the client's existing Codable shapes; real visitor's timezone needed in production.
    visit={'id':'visit-'+item_id, 'place_id':item_id, 'title':data.get('title') or item_id,
           'start':{'minutes':minutes}, 'end':None, 'confirmation':{'confirmed':{}},
           'extras_text':None, 'thumbnail':data.get('photo')}
    with store.db() as con: store.put_json(con,'visits',g.user['id'],visit['id'],visit)
    return jsonify({})


@bp.get('/journey/summaries')
@authenticated
def summaries():
    with store.db() as con: return jsonify(store.list_json(con,'summaries',g.user['id']))


@bp.post('/journey/summaries')
@authenticated
def save_summary():
    data=body_object()
    if data is None or not isinstance(data.get('title'),str): return error('Invalid summary')
    with store.db() as con: store.put_json(con,'summaries',g.user['id'],data['title'],data)
    return jsonify({})


@bp.get('/journey/follow-ups')
@authenticated
def follow_ups():
    with store.db() as con: return jsonify(store.list_json(con,'follow_ups',g.user['id']))


@bp.put('/journey/follow-ups/<item_id>')
@authenticated
def follow_up(item_id):
    data=body_object() or {}
    if not isinstance(data.get('done'),bool): return error('Invalid follow-up')
    with store.db() as con:
        row=con.execute('SELECT payload FROM follow_ups WHERE user_id=? AND id=?',(g.user['id'],item_id)).fetchone()
        if not row: return error('Follow-up not found',404)
        value=json.loads(row['payload']);value['is_done']=data['done']
        store.put_json(con,'follow_ups',g.user['id'],item_id,value)
    return jsonify({})


@bp.post('/journey/summary')
@authenticated
def generate_summary():
    return error('AI summary generation is not configured; existing saved summaries remain available.',501)


@bp.get('/plans/priority-candidates')
@authenticated
def ai_priority_candidates():
    from .gemini_planner import priority_candidates
    return jsonify(priority_candidates())


@bp.post('/plans/generate')
@authenticated
def ai_generate_plan():
    from .gemini_planner import PlannerError, generate_options
    pref = body_object()
    try:
        result = generate_options(pref)
    except PlannerError as exc:
        return error(str(exc), exc.status)
    with store.db() as con:
        store.set_state(con, g.user['id'], 'preferences', pref)
    return jsonify(result)


@bp.get('/plans/current')
@authenticated
def current_plan():
    with store.db() as con: value=store.get_state(con,g.user['id'],'plan')
    return jsonify(value) if value is not None else error('Plan not found',404)


@bp.put('/plans/current')
@authenticated
def save_plan():
    data=body_object()
    if data is None or not isinstance(data.get('steps'),list) or not data.get('id'):
        return error('Invalid plan')
    with store.db() as con: store.set_state(con,g.user['id'],'plan',data)
    return jsonify(data)



def _plan_fingerprint(plan):
    return hashlib.sha256(json.dumps(plan, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


@bp.get('/plans/add-candidates')
@authenticated
def ai_add_candidates():
    # Only genuine schedulable Expo IDs.
    from . import storage
    from .gemini_planner import _minute, _validate_preferences, PlannerError, CATEGORIES
    with store.db() as con:
        plan = store.get_state(con, g.user['id'], 'plan')
        pref = store.get_state(con, g.user['id'], 'preferences')
    if not plan or not pref:
        return error('أنشئي الخطة أولًا.', 404)
    try:
        start, end = _validate_preferences(pref)
        start = plan.get('visit_start_minutes', start)
        end = min(end, plan.get('ends_at', {}).get('minutes', end))
    except (PlannerError, TypeError) as exc:
        return error(str(exc), 422)
    selected = {step.get('kind', {}).get('experience', {}).get('place_id')
                for step in plan.get('steps', []) if 'experience' in step.get('kind', {})}
    categories = set().union(*(CATEGORIES[x] for x in pref['axes']))
    results = []
    for e in storage.events():
        if e['event_id'] in selected or not start <= _minute(e['start_time']) < _minute(e['end_time']) <= end:
            continue
        results.append({'id': e['event_id'], 'title': e['title_ar'],
                        'subtitle': f"فعالية {e['start_time']}–{e['end_time']}",
                        'start_minutes': _minute(e['start_time']), 'end_minutes': _minute(e['end_time']),
                        'is_preferred': e['category'] in categories})
    for b in storage.source('booths'):
        if b['booth_id'] in selected or max(start, _minute(b['opening_time'])) + 20 > min(end, _minute(b['closing_time'])):
            continue
        results.append({'id': b['booth_id'], 'title': 'زيارة بوث: ' + b['name_ar'],
                        'subtitle': f"زيارة مقترحة 20 دقيقة · {b['hall']}",
                        'is_preferred': b['category'] in categories})
    results.sort(key=lambda c: (not c['is_preferred'], c['id']))
    for row in results:
        del row['is_preferred']
    return jsonify(results)


@bp.post('/plans/current/replan')
@authenticated
def ai_replan_propose():
    # A new AI preview; does not modify the adopted plan.
    from .gemini_planner import PlannerError, regenerate_plan
    reason = body_object()
    if reason is None:
        return error('JSON object required')
    with store.db() as con:
        before = store.get_state(con, g.user['id'], 'plan')
        prefs = store.get_state(con, g.user['id'], 'preferences')
    if not before:
        return error('ما فيه خطة محفوظة للتعديل.', 404)
    try:
        proposal = regenerate_plan(before, prefs, reason)
    except PlannerError as exc:
        return error(str(exc), exc.status)
    expires = store.timestamp(store.utc_now() + timedelta(minutes=20))
    with store.db() as con:
        # The result is *only a preview* until the visitor explicitly accepts.
        con.execute('''INSERT INTO plan_replan_proposals
                       (id, user_id, original_hash, original_plan, proposal, expires_at)
                       VALUES (?, ?, ?, ?, ?, ?)''',
                    (proposal['id'], g.user['id'], _plan_fingerprint(before),
                     json.dumps(before, ensure_ascii=False), json.dumps(proposal, ensure_ascii=False), expires))
    return jsonify(proposal)


@bp.post('/plans/current/replan/apply')
@authenticated
def ai_replan_apply():
    data = body_object() or {}
    identifier = data.get('id')
    if not isinstance(identifier, str) or len(identifier) > 80:
        return error('معرّف التعديل غير صالح.')
    with store.db() as con:
        con.execute('BEGIN IMMEDIATE')
        row = con.execute('''SELECT * FROM plan_replan_proposals
                             WHERE id=? AND user_id=?''', (identifier, g.user['id'])).fetchone()
        if not row or row['applied_at'] is not None or row['expires_at'] < store.timestamp():
            return error('انتهت صلاحية المقترح. أعيدي إنشاء التعديل.', 409)
        current = store.get_state(con, g.user['id'], 'plan')
        if not current or _plan_fingerprint(current) != row['original_hash']:
            return error('تغيّرت خطتك بعد تجهيز المقترح؛ أعيدي المحاولة.', 409)
        proposal = json.loads(row['proposal'])
        updated = proposal['after']
        now = store.utc_now()
        updated['undo_available_until'] = store.timestamp(now + timedelta(minutes=10)).replace('+00:00', 'Z')
        store.set_state(con, g.user['id'], 'plan', updated)
        con.execute('''UPDATE plan_replan_proposals SET applied_at=?, undo_until=? WHERE id=?''',
                    (store.timestamp(now), store.timestamp(now + timedelta(minutes=10)), identifier))
    return jsonify(updated)


@bp.post('/plans/current/undo')
@authenticated
def ai_replan_undo():
    with store.db() as con:
        con.execute('BEGIN IMMEDIATE')
        row = con.execute('''SELECT * FROM plan_replan_proposals
                             WHERE user_id=? AND applied_at IS NOT NULL AND undone_at IS NULL
                             ORDER BY applied_at DESC, rowid DESC LIMIT 1''', (g.user['id'],)).fetchone()
        if not row or row['undo_until'] < store.timestamp():
            return error('انتهت مهلة التراجع.', 409)
        plan = store.get_state(con, g.user['id'], 'plan')
        proposed = json.loads(row['proposal'])['after']
        if not plan or plan.get('id') != proposed['id'] or not plan.get('undo_available_until'):
            return error('خطة أخرى حلت محل التعديل؛ لا يمكن التراجع.', 409)
        # Check current content against the committed proposed itinerary, not only its ID.
        if plan.get('steps') != proposed['steps']:
            return error('تغيّرت المحطات بعد التعديل. لا يمكن التراجع عن نسخة قديمة.', 409)
        original = json.loads(row['original_plan'])
        store.set_state(con, g.user['id'], 'plan', original)
        con.execute('UPDATE plan_replan_proposals SET undone_at=? WHERE id=?', (store.timestamp(), row['id']))
    return jsonify(original)


@bp.delete('/plans/current')
@authenticated
def remove_plan():
    with store.db() as con:
        con.execute('DELETE FROM user_state WHERE user_id=? AND kind=?',(g.user['id'],'plan'))
    return jsonify({})


@bp.get('/me/preferences')
@authenticated
def preferences():
    with store.db() as con: value=store.get_state(con,g.user['id'],'preferences')
    return jsonify(value) if value is not None else error('Preferences not found',404)


@bp.put('/me/preferences')
@authenticated
def save_preferences():
    data=body_object()
    if data is None: return error('Invalid preferences')
    with store.db() as con: store.set_state(con,g.user['id'],'preferences',data)
    return jsonify(data)


@bp.get('/me/settings')
@authenticated
def settings():
    with store.db() as con: value=store.get_state(con,g.user['id'],'settings')
    return jsonify(value if value is not None else {})


@bp.put('/me/settings')
@authenticated
def save_settings():
    data=body_object()
    if data is None: return error('Invalid settings')
    with store.db() as con: store.set_state(con,g.user['id'],'settings',data)
    return jsonify(data)


@bp.post('/me/merge-guest-data')
@authenticated
def merge_guest_data():
    return error('Guest counts alone cannot migrate actual records. No data was imported.',501)


@bp.post('/auth/password/forgot')
def forgot_password():
    # Do not pretend to send email when no SMTP provider is connected.
    return error('استعادة كلمة المرور غير متاحة حتى يتم إعداد خدمة إرسال البريد.',503)


@bp.post('/auth/password/reset')
def reset_password():
    return error('استعادة كلمة المرور غير متاحة حتى يتم إعداد خدمة إرسال البريد.',503)

@bp.post('/me/cv')
@authenticated
def upload_cv():
    file = request.files.get('file')
    if file is None: return error('PDF required')
    content = file.read(5_000_001)
    if not content.startswith(b'%PDF-') or len(content) > 5_000_000:
        return error('CV must be a PDF smaller than 5 MB')
    name = str(file.filename or 'resume.pdf').replace('\\','/').split('/')[-1][:180]
    if not name.lower().endswith('.pdf'): return error('Filename must end in .pdf')
    with store.db() as con:
        con.execute('''INSERT INTO cv_files(user_id,file_name,bytes,uploaded_at) VALUES(?,?,?,?)
                       ON CONFLICT(user_id) DO UPDATE SET file_name=excluded.file_name,
                         bytes=excluded.bytes,uploaded_at=excluded.uploaded_at''',
                    (g.user['id'],name,content,store.timestamp()))
    return jsonify({'file_name':name,'bytes':len(content)})

@bp.get('/me/cv')
@authenticated
def download_cv():
    with store.db() as con:
        row=con.execute('SELECT * FROM cv_files WHERE user_id=?',(g.user['id'],)).fetchone()
    if not row: return error('CV not found',404)
    return Response(row['bytes'], mimetype='application/pdf',
                    headers={'Content-Disposition': 'attachment; filename="resume.pdf"',
                             'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff'})

@bp.delete('/me/cv')
@authenticated
def remove_cv():
    with store.db() as con: con.execute('DELETE FROM cv_files WHERE user_id=?',(g.user['id'],))
    return jsonify({})

@bp.put('/journey/visits/<visit_id>')
@authenticated
def put_visit(visit_id):
    data=body_object()
    if data is None or data.get('id') != visit_id or len(json.dumps(data)) > 50_000:
        return error('Invalid visit')
    with store.db() as con:
        store.put_json(con,'visits',g.user['id'],visit_id,data)
    return jsonify(data)

@bp.put('/me/note-attachments/<attachment_id>')
@authenticated
def upload_note_attachment(attachment_id):
    if not re.fullmatch(r'[A-Za-z0-9_-]{8,90}\.jpg',attachment_id):
        return error('Invalid filename')
    photo = request.get_data(cache=False)
    # PhotosPicker may return JPEG, PNG or HEIC bytes; all stored opaque and returned as-is.
    if not photo or len(photo) > 5_000_000: return error('Image must be <= 5 MB')
    with store.db() as con:
        con.execute('''INSERT INTO note_attachments(user_id,id,mimetype,bytes,created_at) VALUES(?,?,?,?,?)
                       ON CONFLICT(user_id,id) DO UPDATE SET bytes=excluded.bytes''',
                    (g.user['id'],attachment_id,'application/octet-stream',photo,store.timestamp()))
    return jsonify({})

@bp.get('/me/note-attachments/<attachment_id>')
@authenticated
def get_note_attachment(attachment_id):
    if not re.fullmatch(r'[A-Za-z0-9_-]{8,90}\.jpg',attachment_id): return error('Invalid filename')
    with store.db() as con:
        row=con.execute('SELECT bytes FROM note_attachments WHERE user_id=? AND id=?',
                        (g.user['id'],attachment_id)).fetchone()
    if not row: return error('Attachment not found',404)
    return Response(row['bytes'],mimetype='application/octet-stream',
                    headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'})


@bp.get('/p/<slug>/cv')
def public_cv(slug):
    with store.db() as con:
        link=con.execute('SELECT * FROM share_links WHERE slug=? AND active=1 AND expires_at>?',
                         (slug,store.timestamp())).fetchone()
        if not link or 'cv' not in json.loads(link['fields']):
            return error('Share link expired or CV not shared',404)
        row=con.execute('SELECT bytes FROM cv_files WHERE user_id=?',(link['user_id'],)).fetchone()
    if not row: return error('CV not uploaded',404)
    return Response(row['bytes'], mimetype='application/pdf',
                    headers={'Content-Disposition':'attachment; filename="resume.pdf"',
                             'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'})
