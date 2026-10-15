"""Flask map API for the Expo 2030 iOS project.

Use from backend/: python -m app.main
The geographic dataset and routing graph are simulated/prototype data.
"""
from __future__ import annotations

import json
import math
import os
import re
import secrets
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from flask import Flask, jsonify, request
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[1] / ".env")
from werkzeug.exceptions import HTTPException

from . import storage
from . import user_db
from .user_api import bp as user_api_blueprint
from .crowd import predict, predict_edge_request

BASE = Path(__file__).resolve().parents[1]
FIELDS = ('title_ar', 'description_ar', 'category', 'start_time', 'end_time')
TIME_RE = re.compile(r'^(?:[01]\d|2[0-3]):[0-5]\d$')


def create_app(testing: bool = False) -> Flask:
    app = Flask(__name__)
    app.json.ensure_ascii = False
    app.config['TESTING'] = testing
    app.config['MAX_CONTENT_LENGTH'] = 6 * 1024 * 1024
    storage.initialize()
    user_db.initialize()
    app.register_blueprint(user_api_blueprint)

    def fail(message: str, status: int):
        return jsonify({'error': message}), status

    def int_param(name: str, minimum: int, maximum: int, default: int | None = None):
        raw = request.args.get(name)
        if raw is None:
            if default is not None:
                return default
            raise ValueError(f'{name} is required')
        try:
            val = int(raw)
        except (ValueError, TypeError):
            raise ValueError(f'{name} must be an integer') from None
        if not minimum <= val <= maximum:
            raise ValueError(f'{name} must be between {minimum} and {maximum}')
        return val

    @app.errorhandler(ValueError)
    def invalid(error):
        return fail(str(error), 422)

    @app.errorhandler(HTTPException)
    def http_error(error):
        return fail(error.description, error.code or 500)

    @app.get('/health')
    def health():
        return jsonify({'status': 'ok', 'service': 'expo2030-flask-api', 'data': 'simulated'})

    @app.get('/api/v1/dataset')
    def dataset():
        return jsonify(storage.dataset())

    @app.get('/api/v1/pavilions')
    def pavilions():
        return jsonify([p for p in storage.source('expo-map-data')['locations'] if p['kind'] == 'pavilion'])

    @app.get('/api/v1/gates')
    def gates():
        return jsonify(storage.source('gates')['gates'])

    @app.get('/api/v1/booths')
    def booths():
        items = storage.source('booths')
        pavilion = request.args.get('pavilion_id')
        if pavilion:
            assignments = storage.source('assignments')['pavilionBooths']
            if pavilion not in assignments:
                return fail('Pavilion not found', 404)
            allowed = set(assignments[pavilion])
            items = [x for x in items if x['booth_id'] in allowed]
        return jsonify(items)

    @app.get('/api/v1/events')
    def events():
        items = storage.events()
        pavilion = request.args.get('pavilion_id')
        if pavilion:
            assignments = storage.source('assignments')['pavilionBooths']
            if pavilion not in assignments:
                return fail('Pavilion not found', 404)
            allowed = set(assignments[pavilion])
            items = [x for x in items if x['booth_id'] in allowed]
        category = request.args.get('category')
        if category:
            items = [x for x in items if x['category'] == category]
        q = request.args.get('search')
        if q:
            q = q.casefold()
            items = [x for x in items if q in (x['title_ar'] + ' ' + x.get('title_en', '')).casefold()]
        return jsonify(items)

    @app.get('/api/v1/events/<event_id>')
    def event_detail(event_id: str):
        item = next((e for e in storage.events() if e['event_id'] == event_id), None)
        return jsonify(item) if item else fail('Event not found', 404)

    @app.put('/api/v1/admin/events/<event_id>')
    def event_update(event_id: str):
        # Admin-only edits; never use a token embedded inside the Swift client.
        expected = os.environ.get('EXPO_ADMIN_TOKEN', '')
        token = request.headers.get('X-Admin-Token', '')
        if not expected or not token or not secrets.compare_digest(expected, token):
            return fail('Admin token required', 403)
        values = request.get_json(silent=True)
        if not isinstance(values, dict) or not values:
            return fail('Non-empty JSON object required', 422)
        if any(key not in FIELDS for key in values):
            return fail('Unsupported event field', 422)
        for key, value in values.items():
            if not isinstance(value, str) or not value.strip():
                return fail(f'{key} must be a nonempty string', 422)
            if key in ('start_time', 'end_time') and not TIME_RE.fullmatch(value):
                return fail(f'{key} must be HH:MM', 422)
            if len(value) > (2000 if key == 'description_ar' else 160 if key == 'title_ar' else 100):
                return fail(f'{key} is too long', 422)
        item = storage.update_event(event_id, values)
        return jsonify(item) if item else fail('Event not found', 404)

    @app.get('/api/v1/crowd/model-info')
    def model_info():
        info = json.loads((BASE / 'models' / 'evaluation.json').read_text(encoding='utf-8'))
        return jsonify({'model': 'RandomForestRegressor',
                        'training_source': info['source'],
                        'is_real_visitor_data': info['is_real_visitor_data'],
                        'train_rows': info['training_rows'],
                        'test_rows': info['test_rows'],
                        'metrics': info['metrics'],
                        'assumptions': info['assumptions']})

    @app.get('/api/v1/crowd/predict')
    def predict_crowd():
        return jsonify(predict(int_param('hour', 0, 23), int_param('day', 0, 6),
                               int_param('zone', 0, 3), int_param('floor', 1, 2, 1),
                               events_override=storage.events()))

    @app.post('/api/v1/crowd/indoor-edges')
    def predict_indoor():
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict):
            return fail('JSON object required', 422)
        hour, day, edges = payload.get('hour'), payload.get('day'), payload.get('edges')
        if type(hour) is not int or not 0 <= hour <= 23:
            return fail('hour must be 0..23', 422)
        if type(day) is not int or not 0 <= day <= 6:
            return fail('day must be 0..6 (Sun-Sat)', 422)
        if not isinstance(edges, list) or not (1 <= len(edges) <= 256):
            return fail('edges must contain 1..256 corridors', 422)
        parsed = []
        ids = set()
        for edge in edges:
            if not isinstance(edge, dict):
                return fail('Invalid edge', 422)
            key, floor, x, y = (edge.get(k) for k in ('edge_id', 'floor', 'x', 'y'))
            if not isinstance(key, str) or not 3 <= len(key) <= 180 or key in ids:
                return fail('Invalid or duplicate edge_id', 422)
            if type(floor) is not int or not 1 <= floor <= 2:
                return fail('floor must be 1 or 2', 422)
            if any(type(v) not in (int, float) or not math.isfinite(v) or not 0 <= v <= 1000 for v in (x,y)):
                return fail('Invalid corridor coordinates', 422)
            ids.add(key)
            parsed.append(Corridor(key, floor, float(x), float(y)))
        forecast = predict_edge_request(EdgeRequest(hour, day, parsed), events_override=storage.events())
        return jsonify({'hour': hour, 'day': day, 'simulation': True,
                        'model': 'expo-geometry-event-flow-rf-regressor-v9',
                        'predictions': forecast})

    return app


@dataclass(frozen=True)
class Corridor:
    edge_id: str
    floor: int
    x: float
    y: float


@dataclass(frozen=True)
class EdgeRequest:
    hour: int
    day: int
    edges: list[Corridor]


# WSGI entrypoint; run `python -m app.main` on the simulator development Mac.
app = create_app()

if __name__ == '__main__':
    app.run(host=os.environ.get('EXPO_API_HOST', '127.0.0.1'),
            port=int(os.environ.get('EXPO_API_PORT', '8001')), debug=False)
