"""Replan constraints tested offline with a fake Gemini ranker; NO real API key."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app import storage, user_db
from app.gemini_planner import PlannerError, generate_options, regenerate_plan

PREF = {'axes': ['tech'], 'subInterests': ['الذكاء الاصطناعي'], 'goals': ['learn'],
        'comfort': [], 'time': 'twoHours', 'mustNotMiss': []}


def ranked(pref, items, count):
    return [i['event_id'] for i in items[:count]]


class ReplanningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.mock_storage = patch.object(storage, 'DB_PATH', Path(self.tmp.name) / 'expo.sqlite3')
        self.mock_storage.start()
        storage.initialize()
        option = generate_options(PREF, selector=ranked)[0]
        self.current = {
            'id': 'plan-' + option['id'], 'name': option['name'],
            'summary': '15:00–17:00', 'steps': option['steps'], 'ends_at': {'minutes': 1020},
        }

    def tearDown(self):
        self.mock_storage.stop()
        self.tmp.cleanup()

    def test_late_replans_with_gemini_ranker_and_keeps_event_clocks(self):
        calls = []
        def rank(p, items, count):
            calls.append(items)
            return ranked(p, items, count)
        proposal = regenerate_plan(self.current, PREF, {'late': {'minutes': 20}}, selector=rank)
        self.assertEqual(len(calls), 1)
        self.assertGreater(len(proposal['after']['steps']), 0)
        self.assertTrue(all(s['time']['minutes'] >= 920 for s in proposal['after']['steps']))
        self.assertEqual(proposal['after']['ends_at']['minutes'], 1020)
        self.assertTrue(proposal['diff'])
        self.assertEqual(proposal['reason'], {'late': {'minutes': 20}})

    def test_two_late_requests_are_cumulative(self):
        first = regenerate_plan(self.current, PREF, {'late': {'minutes': 20}}, selector=ranked)['after']
        second = regenerate_plan(first, PREF, {'late': {'minutes': 20}}, selector=ranked)['after']
        self.assertEqual(second['visit_start_minutes'], 940)

    def test_break_places_rest_before_other_activities(self):
        proposal = regenerate_plan(self.current, PREF, {'needBreak': {}}, selector=ranked)
        steps = proposal['after']['steps']
        self.assertEqual(steps[0]['kind'], {'rest': {'minutes': 15}})
        self.assertEqual(steps[0]['time']['minutes'], 900)
        self.assertTrue(all(s['time']['minutes'] >= 915 for s in steps[1:]))

    def test_adding_booth_makes_room_even_if_event_must_be_replaced(self):
        original = {s['kind']['experience']['place_id'] for s in self.current['steps']}
        self.assertNotIn('B001', original)
        proposal = regenerate_plan(self.current, PREF, {'addedItem': {'title': 'B001'}}, selector=ranked)
        after = {s['kind']['experience']['place_id'] for s in proposal['after']['steps']}
        self.assertIn('B001', after)
        self.assertTrue(proposal['after']['steps'])

    def test_adding_existing_event_stays_at_true_time(self):
        # E003 at 16:00 - chosen existing events may already contain E003;
        # E021 is a different-category event with its own immutable schedule.
        current_ids = {s['kind']['experience']['place_id'] for s in self.current['steps']}
        candidates = [e for e in storage.events() if e['event_id'] not in current_ids and
                      900 <= int(e['start_time'][:2]) * 60 + int(e['start_time'][3:]) and
                      int(e['end_time'][:2]) * 60 + int(e['end_time'][3:]) <= 1020]
        for evt in candidates:
            try:
                proposal = regenerate_plan(self.current, PREF, {'addedItem': {'title': evt['event_id']}}, selector=ranked)
            except PlannerError:
                continue
            result = next(s for s in proposal['after']['steps']
                          if s['kind'].get('experience', {}).get('place_id') == evt['event_id'])
            self.assertEqual(result['time']['minutes'], int(evt['start_time'][:2]) * 60 + int(evt['start_time'][3:]))
            break
        else:
            self.fail('Expected at least one feasible new event')

    def test_unknown_place_rejected(self):
        with self.assertRaises(PlannerError):
            regenerate_plan(self.current, PREF, {'addedItem': {'title': 'invented'}}, selector=ranked)

    def test_invalid_reason_rejected(self):
        with self.assertRaises(PlannerError):
            regenerate_plan(self.current, PREF, {'deleteEverything': {}}, selector=ranked)

    def test_user_db_has_proposals_and_per_user_state(self):
        with patch.dict(os.environ, {'EXPO_USER_DATABASE': str(Path(self.tmp.name)/'users.sqlite3')}):
            user_db.initialize()
            with user_db.db() as con:
                con.execute("INSERT INTO users(id,email,name,password_hash,created_at) VALUES ('u1','u1@example.com','User1','hash',?)", (user_db.timestamp(),))
                con.execute("INSERT INTO users(id,email,name,password_hash,created_at) VALUES ('u2','u2@example.com','User2','hash',?)", (user_db.timestamp(),))
                user_db.set_state(con, 'u1', 'plan', self.current)
                self.assertIsNone(user_db.get_state(con, 'u2', 'plan'))
                con.execute("INSERT INTO plan_replan_proposals(id,user_id,original_hash,original_plan,proposal,expires_at) VALUES ('p1','u1','hash','{}','{}',?)", (user_db.timestamp(),))
            with user_db.db() as con:
                self.assertEqual(con.execute("SELECT COUNT(*) FROM plan_replan_proposals WHERE user_id='u1'").fetchone()[0], 1)
                self.assertEqual(user_db.get_state(con, 'u1', 'plan'), self.current)
                self.assertIsNone(user_db.get_state(con, 'u2', 'plan'))

if __name__ == '__main__':
    unittest.main()
