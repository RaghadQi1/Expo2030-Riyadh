"""User-owned persistent SQLite storage; independent of the simulated map dataset.
All queries scope mutable records by the authenticated user_id.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

DEFAULT_DB = Path(__file__).resolve().parents[1] / 'instance' / 'expo_users.sqlite3'
EMAIL = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
PROFILE_KEYS = {'display_name', 'photo', 'job_title', 'bio', 'education', 'experiences', 'skills', 'looking_for', 'linked_in', 'website', 'preferred_contact', 'contact_goal', 'cv'}
SHARE_KEYS = {'jobTitle', 'bio', 'education', 'experiences', 'skills', 'links', 'contact', 'cv'}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def timestamp(dt: datetime | None = None) -> str:
    return (dt or utc_now()).isoformat(timespec='seconds')


def database_path() -> Path:
    return Path(os.getenv('EXPO_USER_DATABASE', str(DEFAULT_DB))).expanduser().resolve()


@contextmanager
def db():
    path = database_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path, timeout=15)
    con.row_factory = sqlite3.Row
    con.execute('PRAGMA foreign_keys=ON')
    con.execute('PRAGMA busy_timeout=15000')
    try:
        yield con
        con.commit()
    except Exception:
        con.rollback()
        raise
    finally:
        con.close()


def initialize() -> None:
    with db() as con:
        con.execute('PRAGMA journal_mode=WAL')
        con.executescript('''
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
                password_hash TEXT NOT NULL, provider TEXT NOT NULL DEFAULT 'email',
                verified INTEGER NOT NULL DEFAULT 0, marketing_opt_in INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                expires_at TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
            CREATE TABLE IF NOT EXISTS profiles (
                user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                payload TEXT NOT NULL, updated_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS share_links (
                slug TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                fields TEXT NOT NULL, validity TEXT NOT NULL, expires_at TEXT NOT NULL,
                active INTEGER NOT NULL DEFAULT 1);
            CREATE INDEX IF NOT EXISTS share_user ON share_links(user_id);
            CREATE TABLE IF NOT EXISTS cv_files (
                user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                file_name TEXT NOT NULL, bytes BLOB NOT NULL, uploaded_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS note_attachments (
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                id TEXT NOT NULL, mimetype TEXT NOT NULL, bytes BLOB NOT NULL,
                created_at TEXT NOT NULL, PRIMARY KEY(user_id,id));
            CREATE TABLE IF NOT EXISTS notes (
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                id TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL,
                PRIMARY KEY(user_id, id));
            CREATE TABLE IF NOT EXISTS saved_places (
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                id TEXT NOT NULL, payload TEXT NOT NULL, saved_at TEXT NOT NULL,
                PRIMARY KEY(user_id, id));
            CREATE TABLE IF NOT EXISTS visits (
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                id TEXT NOT NULL, payload TEXT NOT NULL, saved_at TEXT NOT NULL,
                PRIMARY KEY(user_id, id));
            CREATE TABLE IF NOT EXISTS summaries (
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                id TEXT NOT NULL, payload TEXT NOT NULL, saved_at TEXT NOT NULL,
                PRIMARY KEY(user_id, id));
            CREATE TABLE IF NOT EXISTS follow_ups (
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                id TEXT NOT NULL, payload TEXT NOT NULL, saved_at TEXT NOT NULL,
                PRIMARY KEY(user_id, id));
            CREATE TABLE IF NOT EXISTS user_state (
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                kind TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL,
                PRIMARY KEY(user_id, kind));
            CREATE TABLE IF NOT EXISTS plan_replan_proposals (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                original_hash TEXT NOT NULL,
                original_plan TEXT NOT NULL,
                proposal TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                applied_at TEXT,
                undo_until TEXT,
                undone_at TEXT);
            CREATE INDEX IF NOT EXISTS proposals_owner
                ON plan_replan_proposals(user_id, applied_at);
        ''')


def hash_password(password: str, salt: str | None = None) -> str:
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac('sha256', password.encode('utf8'), bytes.fromhex(salt), 480_000)
    return 'pbkdf2_sha256$480000$' + salt + '$' + digest.hex()


def valid_password(stored: str, password: str) -> bool:
    try:
        algorithm, rounds, salt, digest = stored.split('$')
        if algorithm != 'pbkdf2_sha256' or int(rounds) != 480_000:
            return False
        target = hashlib.pbkdf2_hmac('sha256', password.encode('utf8'), bytes.fromhex(salt), int(rounds))
        return hmac.compare_digest(target, bytes.fromhex(digest))
    except (ValueError, TypeError):
        return False


def strong_password(password: Any, email: str) -> bool:
    return (isinstance(password, str) and 8 <= len(password) <= 512 and
            re.search('[a-z]', password) is not None and re.search('[A-Z]', password) is not None and
            re.search('[0-9]', password) is not None)


def user_response(user: sqlite3.Row) -> dict:
    return {'id': user['id'], 'name': user['name'], 'email': user['email'], 'avatar_asset': None,
            'provider': user['provider'], 'is_email_verified': bool(user['verified']),
            'uses_private_relay_email': False}


def issue_session(con: sqlite3.Connection, user: sqlite3.Row) -> dict:
    token = secrets.token_urlsafe(40)
    con.execute('INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)',
                (hashlib.sha256(token.encode()).hexdigest(), user['id'], timestamp(utc_now() + timedelta(days=14))))
    return {'user': user_response(user), 'access_token': token, 'refresh_token': None}


def authenticate(token: str | None) -> sqlite3.Row | None:
    if not token:
        return None
    digest = hashlib.sha256(token.encode()).hexdigest()
    with db() as con:
        return con.execute('''SELECT u.* FROM users u JOIN sessions s ON u.id=s.user_id
                              WHERE s.token_hash=? AND s.expires_at>?''', (digest, timestamp())).fetchone()


def as_json(item: sqlite3.Row | None) -> Any:
    return json.loads(item['payload']) if item else None


def put_json(con, table: str, user_id: str, item_id: str, value: Any, column: str = 'saved_at'):
    assert table in {'notes','saved_places','visits','summaries','follow_ups'}
    assert column in {'saved_at','updated_at'}
    con.execute(f'''INSERT INTO {table}(user_id,id,payload,{column}) VALUES(?,?,?,?)
                    ON CONFLICT(user_id,id) DO UPDATE SET payload=excluded.payload,
                     {column}=excluded.{column}''',
                (user_id, item_id, json.dumps(value, ensure_ascii=False), timestamp()))


def list_json(con, table, user_id, column='saved_at'):
    assert table in {'notes','saved_places','visits','summaries','follow_ups'}
    assert column in {'saved_at','updated_at'}
    return [json.loads(row['payload']) for row in con.execute(
        f'SELECT payload FROM {table} WHERE user_id=? ORDER BY {column} DESC', (user_id,)).fetchall()]


def get_state(con, user_id, kind):
    assert kind in {'plan','preferences','settings'}
    return as_json(con.execute('SELECT payload FROM user_state WHERE user_id=? AND kind=?', (user_id,kind)).fetchone())


def set_state(con, user_id, kind, value):
    assert kind in {'plan','preferences','settings'}
    con.execute('''INSERT INTO user_state(user_id,kind,payload,updated_at) VALUES(?,?,?,?)
                   ON CONFLICT(user_id,kind) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at''',
                (user_id,kind,json.dumps(value,ensure_ascii=False),timestamp()))
