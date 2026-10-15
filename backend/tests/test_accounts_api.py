"""Full API tests; install requirements-dev.txt then run pytest -q.
Uses a new SQLite file for each test and NEVER writes to the user database.
"""
import pytest
from app.main import create_app

@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('EXPO_USER_DATABASE', str(tmp_path / 'users.sqlite3'))
    from app import storage
    monkeypatch.setattr(storage, 'DB_PATH', tmp_path / 'events.sqlite3')
    return create_app(testing=True).test_client()


def register(client, name, email):
    response = client.post('/auth/register',json={
        'name':name, 'email':email, 'password':'SecurePass44',
        'accepted_terms':True,'marketing_opt_in':False})
    assert response.status_code==201, response.json
    assert response.json['user']['email'] == email
    assert response.json['user']['is_email_verified'] is False
    assert isinstance(response.json['access_token'], str)
    assert len(response.json['access_token']) >= 32
    headers = {'Authorization':'Bearer '+response.json['access_token']}
    assert client.get('/me', headers=headers).status_code == 200
    return headers


def test_user_records_survive_requests_and_are_isolated(client):
    a=register(client,'أمل','amal@example.com')
    b=register(client,'بدر','badr@example.com')
    assert client.get('/me/profile', headers=a).status_code==404
    assert client.get('/me/profile').status_code==401
    profile={'display_name':'أمل','bio':'AI researcher','job_title':'Researcher',
             'education':'KSU','experiences':[], 'skills':['Python'], 'looking_for':['job'],
             'linked_in':'','website':'','preferred_contact':'','contact_goal':''}
    assert client.put('/me/profile',json=profile,headers=a).status_code==200
    assert client.get('/me/profile',headers=a).json['bio']=='AI researcher'
    assert client.get('/me/profile',headers=b).status_code==404
    assert client.put('/plans/current',json={'id':'plan1','steps':[]},headers=a).status_code==200
    assert client.get('/plans/current',headers=a).json['id']=='plan1'
    assert client.get('/plans/current',headers=b).status_code==404
    note={'id':'n1','title':'Test','place_id':'p1'}
    assert client.put('/notes/n1',json=note,headers=a).status_code==200
    assert [n['id'] for n in client.get('/notes',headers=a).json]==['n1']
    assert client.get('/notes',headers=b).json==[]
    assert client.post('/journey/saved/toggle',json={'id':'p1','title':'جناح'},headers=a).json['saved']
    assert client.get('/journey/saved',headers=b).json==[]
    assert len(client.get('/journey/saved',headers=a).json)==1
    assert client.post('/journey/saved/toggle',json={'id':'p1'},headers=a).json['saved'] is False
    assert client.get('/journey/saved',headers=a).json==[]


def test_login_logout_and_wrong_password(client):
    a=register(client,'أمل','amal@example.com')
    bad=client.post('/auth/login',json={'email':'amal@example.com','password':'bad'})
    assert bad.status_code==401
    ok=client.post('/auth/login',json={'email':'amal@example.com','password':'SecurePass44'})
    assert ok.status_code==200
    assert client.get('/me',headers=a).json['name']=='أمل'
    assert client.post('/auth/logout',headers=a).status_code==200
    assert client.get('/me',headers=a).status_code==401
    # Login separately received a distinct token still works.
    assert client.get('/me',headers={'Authorization':'Bearer '+ok.json['access_token']}).status_code==200


def test_share_expiry_scope_and_cv_upload(client):
    a=register(client,'أمل','amal@example.com')
    client.put('/me/profile',json={'display_name':'أمل','bio':'PRIVATE','job_title':'Analyst','skills':['SQL']},headers=a)
    p=client.post('/me/profile/share-link',json={'fields':['jobTitle'],'validity':'oneHour'},headers=a)
    assert p.status_code==201, p.json
    slug=p.json['url'].split('/')[-1]
    exposed=client.get('/p/'+slug).json
    assert 'job_title' in exposed and 'bio' not in exposed
    pdf=b'%PDF-1.7\nmock document\n%%EOF'
    uploaded=client.post('/me/cv',data={'file':( __import__('io').BytesIO(pdf), 'mycv.pdf')},headers=a)
    assert uploaded.status_code==200
    assert client.get('/me/cv',headers=a).data==pdf
    assert client.get('/p/'+slug+'/cv').status_code==404
    new=client.post('/me/profile/share-link',json={'fields':['bio','cv'],'validity':'oneWeek'},headers=a)
    new_slug=new.json['url'].split('/')[-1]
    assert client.get('/p/'+slug).status_code==404
    assert client.get('/p/'+new_slug+'/cv').data==pdf
    assert client.delete('/me/profile/share-link',headers=a).status_code==200
    assert client.get('/p/'+new_slug).status_code==404


def test_photos_private_and_user_owned(client):
    a=register(client,'أمل','amal@example.com')
    b=register(client,'بدر','badr@example.com')
    image=b'photo fake bytes'
    file_name='12345678-photo.jpg'
    assert client.put('/me/note-attachments/'+file_name, data=image,headers=a).status_code==200
    assert client.get('/me/note-attachments/'+file_name,headers=a).data==image
    assert client.get('/me/note-attachments/'+file_name,headers=b).status_code==404


def test_account_created_without_email_and_duplicate_rejected(client):
    account = register(client, 'أمل', 'amal@example.com')
    from app import user_db
    with user_db.db() as con:
        row = con.execute('SELECT verified,password_hash FROM users WHERE email=?',
                          ('amal@example.com',)).fetchone()
        assert row['verified'] == 0  # No claim that mailbox ownership was checked.
        assert row['password_hash'] != 'SecurePass44'
    dup = client.post('/auth/register',json={
        'name':'مستخدم آخر','email':'amal@example.com','password':'SecurePass44',
        'accepted_terms':True})
    assert dup.status_code == 409
    assert client.get('/me',headers=account).status_code == 200
    assert client.post('/auth/verify-email', json={'email':'amal@example.com','code':'000000'}).status_code == 404
    assert client.post('/auth/verify-email/resend', json={'email':'amal@example.com'}).status_code == 404


def test_legacy_pending_account_can_login_without_otp(client):
    from app import user_db
    with user_db.db() as con:
        con.execute('INSERT INTO users(id,email,name,password_hash,verified,created_at) VALUES(?,?,?,?,0,?)',
                    ('legacy-user','pending@example.com','قديمة',
                     user_db.hash_password('SecurePass44'),user_db.timestamp()))
        con.execute('INSERT INTO profiles(user_id,payload,updated_at) VALUES(?,?,?)',
                    ('legacy-user','{"display_name":"قديمة","bio":"محفوظ"}',user_db.timestamp()))
    result = client.post('/auth/login',json={'email':'pending@example.com','password':'SecurePass44'})
    assert result.status_code == 200, result.json
    assert result.json['user']['is_email_verified'] is False
    auth = {'Authorization':'Bearer '+result.json['access_token']}
    assert client.get('/me/profile',headers=auth).json['bio'] == 'محفوظ'


def test_password_policy_and_auth_validation(client):
    assert client.post('/auth/register',json={
        'name':'أمل', 'email':'a@example.com', 'password':'weak',
        'accepted_terms':True}).status_code == 422
    assert client.post('/auth/register',json={
        'name':'أمل', 'email':'a@example.com', 'password':'SecurePass44',
        'accepted_terms':False}).status_code == 422
    assert client.get('/me').status_code == 401
