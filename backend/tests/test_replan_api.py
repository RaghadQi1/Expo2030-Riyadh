"""Flask + SQLite integration tests; Gemini is replaced only at the ranking boundary."""
from unittest.mock import patch
import pytest
from app.main import create_app
from app import storage


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('EXPO_USER_DATABASE', str(tmp_path / 'accounts.sqlite3'))
    monkeypatch.setattr(storage, 'DB_PATH', tmp_path / 'events.sqlite3')
    return create_app(testing=True).test_client()


def rank(_, candidates, count):
    return [c['event_id'] for c in candidates[:count]]


def setup_plan(client, email='a@example.com'):
    created = client.post('/auth/register', json={
        'name': 'Expo Tester', 'email': email, 'password': 'SecurePassword42', 'accepted_terms': True,
    })
    assert created.status_code == 201, created.json
    auth = {'Authorization': 'Bearer ' + created.json['access_token']}
    preferences = {'axes': ['tech'], 'goals': ['learn'], 'time': 'twoHours',
                   'sub_interests': ['الذكاء الاصطناعي'], 'comfort': [], 'must_not_miss': []}
    with patch('app.gemini_planner._choose_ids_with_gemini', side_effect=rank):
        generated = client.post('/plans/generate', headers=auth, json=preferences)
    assert generated.status_code == 200, generated.json
    option = generated.json[0]
    plan = {'id': 'plan-' + option['id'], 'name': option['name'], 'summary': '15:00–17:00',
            'steps': option['steps'], 'ends_at': {'minutes': 1020}}
    saved = client.put('/plans/current', headers=auth, json=plan)
    assert saved.status_code == 200, saved.json
    return auth, plan


def test_gemini_replan_preview_apply_and_undo_are_durable(client):
    auth, original = setup_plan(client)
    candidates = client.get('/plans/add-candidates', headers=auth)
    assert candidates.status_code == 200
    assert any(x['id'].startswith('B') for x in candidates.json)
    with patch('app.gemini_planner._choose_ids_with_gemini', side_effect=rank):
        preview = client.post('/plans/current/replan', headers=auth, json={'needBreak': {}})
    assert preview.status_code == 200, preview.json
    proposal = preview.json
    assert proposal['after']['steps'][0]['kind'] == {'rest': {'minutes': 15}}
    # Explicit preview must NOT silently modify the saved itinerary.
    assert client.get('/plans/current', headers=auth).json == original
    approved = client.post('/plans/current/replan/apply', headers=auth, json={'id': proposal['id']})
    assert approved.status_code == 200, approved.json
    assert approved.json['undo_available_until']
    assert client.get('/plans/current', headers=auth).json == approved.json
    assert client.application.test_client().get('/plans/current', headers=auth).json == approved.json
    second_apply = client.post('/plans/current/replan/apply', headers=auth, json={'id': proposal['id']})
    assert second_apply.status_code == 409
    undone = client.post('/plans/current/undo', headers=auth, json={'id': 'undo'})
    assert undone.status_code == 200, undone.json
    assert undone.json == original
    assert client.get('/plans/current', headers=auth).json == original


def test_adding_booth_with_ai_and_prevent_wrong_user_approval(client):
    auth1, original = setup_plan(client)
    auth2, another = setup_plan(client, email='b@example.com')
    with patch('app.gemini_planner._choose_ids_with_gemini', side_effect=rank):
        preview = client.post('/plans/current/replan', headers=auth1,
                              json={'addedItem': {'title': 'B001'}})
    assert preview.status_code == 200, preview.json
    added = [x['kind'].get('experience', {}).get('place_id') for x in preview.json['after']['steps']]
    assert 'B001' in added
    forbidden = client.post('/plans/current/replan/apply', headers=auth2, json={'id': preview.json['id']})
    assert forbidden.status_code == 409
    assert client.get('/plans/current', headers=auth2).json == another
    assert client.get('/plans/current', headers=auth1).json == original


def test_preview_invalidated_if_current_plan_changes(client):
    auth, original = setup_plan(client)
    with patch('app.gemini_planner._choose_ids_with_gemini', side_effect=rank):
        preview = client.post('/plans/current/replan', headers=auth, json={'late': {'minutes': 20}})
    assert preview.status_code == 200
    edited = dict(original)
    edited['name'] = 'User adjusted plan'
    assert client.put('/plans/current', headers=auth, json=edited).status_code == 200
    stale = client.post('/plans/current/replan/apply', headers=auth, json={'id': preview.json['id']})
    assert stale.status_code == 409
    assert client.get('/plans/current', headers=auth).json == edited
