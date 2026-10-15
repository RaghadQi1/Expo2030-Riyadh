"""End-to-end account -> Gemini-ranked options -> adoption -> persisted SQLite.
Run after installing backend/requirements-dev.txt: python -m pytest tests/test_plan_generation_api.py -q
No Gemini network or user DB is touched in this test.
"""
from unittest.mock import patch
import pytest
from app.main import create_app
from app import storage


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('EXPO_USER_DATABASE', str(tmp_path / 'accounts.sqlite3'))
    monkeypatch.setattr(storage, 'DB_PATH', tmp_path / 'events.sqlite3')
    return create_app(testing=True).test_client()


def test_out_of_time_priority_generates_and_saves(client):
    response = client.post('/auth/register', json={
        'name': 'Test User', 'email': 'test-user@example.com',
        'password': 'SecurePassword42', 'accepted_terms': True,
    })
    assert response.status_code == 201, response.json
    auth = {'Authorization': 'Bearer ' + response.json['access_token']}
    assert client.get('/plans/current', headers=auth).status_code == 404
    preferences = {'axes': ['tech'], 'goals': ['learn'], 'time': 'oneHour',
                   'sub_interests': ['الذكاء الاصطناعي'], 'comfort': [],
                   'must_not_miss': ['E001']}
    candidates = client.get('/plans/priority-candidates', headers=auth)
    assert candidates.status_code == 200
    assert candidates.json[0]['start_minutes'] == 570

    # Match Swift's convertToSnakeCase and mock Gemini only, not the Flask routes.
    def rank(_, listed, count):
        return [item['event_id'] for item in listed[:count]]

    with patch('app.gemini_planner._choose_ids_with_gemini', side_effect=rank):
        result = client.post('/plans/generate', json=preferences, headers=auth)
    assert result.status_code == 200, result.json
    option = result.json[0]
    assert option['steps'] and 'خارج الوقت' in option['tradeoffs']
    assert client.get('/me/preferences', headers=auth).json['must_not_miss'] == ['E001']

    # User taps "اعتمد" in Swift. This is where the committed plan is saved.
    plan = {'id': 'plan-' + option['id'], 'name': option['name'],
            'summary': '15:00–16:00 · جدول تجريبي',
            'steps': option['steps'], 'ends_at': {'minutes': 960}}
    saved = client.put('/plans/current', json=plan, headers=auth)
    assert saved.status_code == 200, saved.json
    assert saved.json == plan
    assert client.get('/plans/current', headers=auth).json == plan
    # Separate client, same physical sqlite DB.
    again = client.application.test_client()
    assert again.get('/plans/current', headers=auth).json == plan
    assert again.get('/plans/current').status_code == 401
