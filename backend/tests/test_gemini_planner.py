"""Offline tests: no real Gemini calls and no live API keys are needed."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app import storage
from app.gemini_planner import PlannerError, generate_options, priority_candidates


PREF = {'axes': ['tech'], 'subInterests': ['الذكاء الاصطناعي'],
        'goals': ['learn'], 'time': 'twoHours', 'comfort': [], 'mustNotMiss': []}


class GeminiPlannerTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_patch = patch.object(storage, 'DB_PATH', Path(self.temp_dir.name) / 'test.sqlite3')
        self.db_patch.start()
        storage.initialize()

    def tearDown(self):
        self.db_patch.stop()
        self.temp_dir.cleanup()

    def test_valid_ids_times_and_swift_fields(self):
        choices = generate_options(PREF, selector=lambda p, c, n: [x['event_id'] for x in c])
        self.assertEqual(len(choices), 1)
        ids = {e['id'] for e in priority_candidates()}
        steps = choices[0]['steps']
        self.assertGreater(len(steps), 0)
        self.assertEqual(len({s['kind']['experience']['place_id'] for s in steps}), len(steps))
        self.assertTrue(all(s['kind']['experience']['place_id'] in ids for s in steps))
        self.assertTrue(all(900 <= s['time']['minutes'] < 1020 for s in steps))
        self.assertTrue(all(s['change'] == {'none': {}} for s in steps))
        self.assertIn('estimated_wait_text', choices[0]['metrics'])
        self.assertTrue(choices[0]['is_recommended'])

    def test_fabricated_id_is_rejected(self):
        with self.assertRaises(PlannerError) as err:
            generate_options(PREF, selector=lambda p, c, n: ['invented-venue'])
        self.assertEqual(err.exception.status, 502)

    def test_fixed_priority_included(self):
        pref = {**PREF, 'mustNotMiss': ['E003']}
        result = generate_options(pref, selector=lambda p, c, n: ['E008'])
        selected = {s['kind']['experience']['place_id'] for s in result[0]['steps']}
        self.assertIn('E003', selected)

    def test_invalid_priority_fails(self):
        with self.assertRaises(PlannerError):
            generate_options({**PREF, 'mustNotMiss': ['BAD-123']}, selector=lambda p, c, n: [])

    def test_pinned_event_outside_time_does_not_fail(self):
        # Regression for the iPhone screenshot: old planner rejected all pins
        # outside the chosen time with status 422.
        pref = {**PREF, 'time': 'oneHour', 'mustNotMiss': ['E001']}
        result = generate_options(pref, selector=lambda p, c, n: [x['event_id'] for x in c])
        steps = result[0]['steps']
        self.assertGreater(len(steps), 0)
        self.assertNotIn('E001', [s['kind']['experience']['place_id'] for s in steps])
        self.assertIn('خارج الوقت', result[0]['tradeoffs'])

    def test_unavailable_events_use_open_booths(self):
        pref = {**PREF, 'time': 'custom', 'customStart': {'minutes': 540},
                'customEnd': {'minutes': 585}, 'mustNotMiss': ['E008']}
        result = generate_options(pref, selector=lambda p, c, n: [x['event_id'] for x in c])
        self.assertTrue(result[0]['steps'])
        self.assertTrue(all(s['kind']['experience']['place_id'].startswith('B')
                            for s in result[0]['steps']))
        self.assertTrue(all(540 <= s['time']['minutes'] <= 565
                            for s in result[0]['steps']))

    def test_window_and_opening_hours_for_all_axes(self):
        for axis in ('tech', 'earth', 'human', 'culture', 'coop'):
            for time in ('oneHour', 'twoHours', 'halfDay'):
                with self.subTest(axis=axis, time=time):
                    pref = {**PREF, 'axes': [axis], 'time': time, 'mustNotMiss': ['E001']}
                    result = generate_options(pref, selector=lambda p, c, n: [x['event_id'] for x in c])
                    steps = result[0]['steps']
                    self.assertTrue(steps)
                    start, end = 900, 900 + {'oneHour': 60, 'twoHours': 120, 'halfDay': 240}[time]
                    events = {e['event_id']: e for e in storage.events()}
                    booths = {b['booth_id']: b for b in storage.source('booths')}
                    busy = []
                    for step in steps:
                        event_or_booth = step['kind']['experience']['place_id']
                        t = step['time']['minutes']
                        if event_or_booth.startswith('E'):
                            evt = events[event_or_booth]
                            self.assertEqual(t, __import__('app.gemini_planner', fromlist=['_minute'])._minute(evt['start_time']))
                            finish = __import__('app.gemini_planner', fromlist=['_minute'])._minute(evt['end_time'])
                        else:
                            booth = booths[event_or_booth]
                            self.assertGreaterEqual(t, __import__('app.gemini_planner', fromlist=['_minute'])._minute(booth['opening_time']))
                            finish = t + 20
                            self.assertLessEqual(finish, __import__('app.gemini_planner', fromlist=['_minute'])._minute(booth['closing_time']))
                        self.assertGreaterEqual(t, start)
                        self.assertLessEqual(finish, end)
                        busy.append((t, finish))
                    for first, second in zip(busy, busy[1:]):
                        self.assertLessEqual(first[1], second[0])

    def test_overlapping_pinned_events_are_handled(self):
        pref = {**PREF, 'time': 'twoHours', 'mustNotMiss': ['E003', 'E011']}
        result = generate_options(pref, selector=lambda p, c, n: [x['event_id'] for x in c])
        selected_ids = [step['kind']['experience']['place_id'] for step in result[0]['steps']]
        self.assertEqual(len(set(['E003', 'E011']).intersection(selected_ids)), 1)
        self.assertIn('تعارض', result[0]['tradeoffs'])

    def test_generated_plan_can_be_persisted_in_user_sqlite(self):
        from app import user_db
        database = Path(self.temp_dir.name) / 'accounts.sqlite3'
        with patch.dict(os.environ, {'EXPO_USER_DATABASE': str(database)}):
            user_db.initialize()
            with user_db.db() as con:
                con.execute('INSERT INTO users(id,email,name,password_hash,created_at) VALUES(?,?,?,?,?)',
                            ('account-A', 'a@test.example', 'Test', 'dummy', user_db.timestamp()))
            options = generate_options({**PREF, 'mustNotMiss': ['E001']},
                                       selector=lambda p, c, n: [x['event_id'] for x in c])
            option = options[0]
            # The app adopts and PUTs a Plan (not the raw PlanOption).
            plan = {'id': 'plan-' + option['id'], 'name': option['name'],
                    'summary': '15:00–17:00 · جدول تجريبي',
                    'steps': option['steps'], 'ends_at': {'minutes': 1020}}
            with user_db.db() as con:
                user_db.set_state(con, 'account-A', 'preferences', PREF)
                user_db.set_state(con, 'account-A', 'plan', plan)
            with user_db.db() as reopened:
                fetched = user_db.get_state(reopened, 'account-A', 'plan')
                self.assertEqual(fetched['id'], plan['id'])
                self.assertEqual(fetched['steps'], option['steps'])
                self.assertEqual(user_db.get_state(reopened, 'account-A', 'preferences'), PREF)
                self.assertIsNone(user_db.get_state(reopened, 'other-user', 'plan'))

    def test_missing_key_does_not_fall_back_to_mock(self):
        with patch.dict(os.environ, {'GEMINI_API_KEY': ''}):
            with self.assertRaises(PlannerError) as err:
                generate_options(PREF)
            self.assertEqual(err.exception.status, 503)

    def test_swift_snake_case_preferences(self):
        pref = {'axes': ['tech'], 'goals': ['learn'],
                'sub_interests': ['الذكاء الاصطناعي'], 'time': 'custom',
                'custom_start': {'minutes': 900}, 'custom_end': {'minutes': 1020},
                'must_not_miss': ['E003']}
        options = generate_options(pref, selector=lambda p, c, n: ['E008'])
        selected = {s['kind']['experience']['place_id'] for s in options[0]['steps']}
        self.assertIn('E003', selected)

    def test_custom_time_and_priority(self):
        pref = {**PREF, 'time': 'custom',
                'customStart': {'minutes': 600}, 'customEnd': {'minutes': 720},
                'mustNotMiss': ['E004']}
        result = generate_options(pref, selector=lambda p, c, n: [])
        self.assertIn('E004', [s['kind']['experience']['place_id'] for s in result[0]['steps']])


if __name__ == '__main__':
    unittest.main()
