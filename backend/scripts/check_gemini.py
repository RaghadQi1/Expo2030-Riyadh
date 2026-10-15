"""Test real Gemini API using backend/.env without printing the key.

From backend/ (with venv active): python3 scripts/check_gemini.py
Requires a small Gemini generation request; can incur quota/cost.
"""
from pathlib import Path
import os
import re
import sys

BACKEND = Path(__file__).resolve().parents[1]
try:
    from dotenv import load_dotenv
    load_dotenv(BACKEND / '.env')
except ImportError:
    print('ERROR: python-dotenv missing; run: python3 -m pip install -r requirements.txt')
    sys.exit(1)

key = os.environ.get('GEMINI_API_KEY', '').strip()
model = os.environ.get('GEMINI_MODEL', 'gemini-3.8-flash').strip()
print('backend/.env present:', (BACKEND / '.env').is_file())
print('GEMINI_API_KEY loaded:', 'YES' if key and key != 'YOUR_API_KEY_HERE' else 'NO')
print('GEMINI_MODEL:', model)
if not key or key == 'YOUR_API_KEY_HERE':
    print('Set your actual Gemini key in backend/.env and restart the backend.')
    sys.exit(2)
try:
    from google import genai
    from google.genai import types
    from pydantic import BaseModel, Field
except ImportError as exc:
    print('Library missing:', type(exc).__name__)
    print('Run: python3 -m pip install -r requirements.txt')
    sys.exit(3)

class EventChoices(BaseModel):
    event_ids: list[str] = Field(description='Ordered IDs from candidate list')

try:
    client = genai.Client(api_key=key, http_options={'timeout': 60000})
    response = client.models.generate_content(
        model=model,
        contents='Return event_ids containing only the ID E001. Candidates: ["E001"].',
        config=types.GenerateContentConfig(response_mime_type='application/json',
                                           response_schema=EventChoices, temperature=0.2),
    )
    print('GEMINI TEST: SUCCESS')
    print('Gemini structured result:', (response.text or '').strip()[:200])
except Exception as exc:
    code = getattr(exc, 'code', None)
    message = str(getattr(exc, 'message', str(exc)))
    # Never print credentials in troubleshooting logs.
    message = message.replace(key, '[REDACTED]')
    message = re.sub(r'(?i)([?&]key=)[^&\s]+', r'\1[REDACTED]', message)
    print('GEMINI TEST: FAILED')
    print('HTTP code:', code if code is not None else 'unavailable')
    print('Error type:', type(exc).__name__)
    print('Details (safe to inspect; check before sharing):', message[:650])
    sys.exit(4)
