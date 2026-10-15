"""Run: pytest -q  (needs dependencies from requirements-dev.txt)."""
import json
from pathlib import Path
import pytest
from app.main import create_app
from app import storage


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(storage, 'DB_PATH', tmp_path / 'test.sqlite3')
    app = create_app(testing=True)
    return app.test_client()


def test_health_and_dataset(client):
    assert client.get('/health').json['status'] == 'ok'
    body = client.get('/api/v1/dataset').json
    assert set(['map','events','booths','indoor','gates','assignments']) <= body.keys()
    assert len(body['map']['locations']) > 1
    assert client.get('/api/v1/events').status_code == 200
    assert len(client.get('/api/v1/gates').json) == 3


def test_input_errors_and_protected_edits(client):
    assert client.get('/api/v1/crowd/predict?hour=99&day=0&zone=0').status_code == 422
    assert client.post('/api/v1/crowd/indoor-edges', json={'hour':1,'day':1,'edges':[]}).status_code == 422
    event = client.get('/api/v1/events').json[0]
    assert client.put(f'/api/v1/admin/events/{event["event_id"]}', json={'title_ar':'تجربة'}).status_code == 403


def test_sqlite_event_override(client, monkeypatch):
    monkeypatch.setenv('EXPO_ADMIN_TOKEN', 'secret-test-token')
    event = client.get('/api/v1/events').json[0]
    identifier = event['event_id']
    result = client.put(f'/api/v1/admin/events/{identifier}',
                        json={'title_ar':'عنوان محدث'},headers={'X-Admin-Token':'secret-test-token'})
    assert result.status_code == 200
    assert client.get(f'/api/v1/events/{identifier}').json['title_ar'] == 'عنوان محدث'
    assert (storage.DB_PATH).is_file()
    assert result.json['booth_id'] == event['booth_id']


def test_forecast_returns_edge_id_for_each_corridor(client):
    # Coordinates refer to bundled demo graph: preserve identifiers supplied by Swift.
    response = client.post('/api/v1/crowd/indoor-edges', json={
        'hour': 11, 'day': 0, 'edges': [{'edge_id':'f1/example-demo-segment','floor':1,'x':385,'y':290}]})
    assert response.status_code == 200
    forecast = response.json
    assert forecast['simulation'] is True
    assert len(forecast['predictions']) == 1
    assert forecast['predictions'][0]['edge_id'] == 'f1/example-demo-segment'
    assert 1 <= forecast['predictions'][0]['time_factor'] <= 4.25
