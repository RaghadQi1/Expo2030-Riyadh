"""Read original Expo geometry from JSON and persist editable event metadata in SQLite.

IDs/booth assignments are immutable: editing a title or time must never invalidate
Swift's existing navigation graph or pavilion <-> booth <-> event relationships.
"""
import json
import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
DATA = BASE / 'data'
DB_PATH = Path(os.environ.get('EXPO_DB_PATH', str(BASE / 'expo.sqlite3')))


def source(name: str):
    return json.loads((DATA / f'{name}.json').read_text(encoding='utf-8'))


@contextmanager
def connection():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except BaseException:
        conn.rollback()
        raise
    finally:
        conn.close()


def initialize():
    with connection() as conn:
        conn.execute('''CREATE TABLE IF NOT EXISTS event_overrides (
            event_id TEXT PRIMARY KEY,
            title_ar TEXT NOT NULL,
            description_ar TEXT NOT NULL,
            category TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )''')


def events():
    records = source('events')
    with connection() as conn:
        overrides = {r['event_id']: dict(r) for r in
                     conn.execute('SELECT * FROM event_overrides')}
    for record in records:
        changed = overrides.get(record['event_id'])
        if changed:
            for key in ('title_ar', 'description_ar', 'category', 'start_time', 'end_time'):
                record[key] = changed[key]
    return records


def update_event(event_id, values):
    original = next((e for e in source('events') if e['event_id'] == event_id), None)
    if original is None:
        return None
    # Merge with any previous edits; unedited properties always retain seed values.
    existing = next((e for e in events() if e['event_id'] == event_id), original)
    editable = ('title_ar', 'description_ar', 'category', 'start_time', 'end_time')
    updated = {k: values.get(k, existing[k]) for k in editable}
    with connection() as conn:
        conn.execute('''INSERT INTO event_overrides(event_id,title_ar,description_ar,category,start_time,end_time)
                        VALUES (:event_id,:title_ar,:description_ar,:category,:start_time,:end_time)
                        ON CONFLICT(event_id) DO UPDATE SET
                        title_ar=excluded.title_ar, description_ar=excluded.description_ar,
                        category=excluded.category, start_time=excluded.start_time,
                        end_time=excluded.end_time, updated_at=CURRENT_TIMESTAMP''',
                     {'event_id': event_id, **updated})
    return {**original, **updated}


def dataset():
    return {
        'map': source('expo-map-data'),
        'booths': source('booths'),
        'events': events(),
        'assignments': source('assignments'),
        'indoor': source('saudi-pavilion-indoor'),
        'gates': source('gates'),
    }
