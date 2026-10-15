"""Run: python -m unittest discover -s tests -p test_user_persistence.py
Uses the stdlib DB layer even when Flask is not installed.
"""
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from app import user_db

class PersistentDBTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.previous = os.environ.get('EXPO_USER_DATABASE')
        os.environ['EXPO_USER_DATABASE'] = str(Path(self.tmp.name)/'accounts.sqlite3')
        user_db.initialize()
        self.a, self.b = 'account-A', 'account-B'
        with user_db.db() as db:
            for identifier in (self.a, self.b):
                db.execute('INSERT INTO users(id,email,name,password_hash,created_at,verified) VALUES(?,?,?,?,?,1)',
                           (identifier,identifier.lower()+'@example.org',identifier,
                            user_db.hash_password('SecureTest8x'),user_db.timestamp()))

    def tearDown(self):
        if self.previous is None: os.environ.pop('EXPO_USER_DATABASE', None)
        else: os.environ['EXPO_USER_DATABASE'] = self.previous
        self.tmp.cleanup()

    def test_durable_isolation_across_connections(self):
        with user_db.db() as db:
            user_db.put_json(db,'notes',self.a,'n1',{'id':'n1','title':'A private note'},'updated_at')
            user_db.put_json(db,'notes',self.b,'n2',{'id':'n2','title':'B private note'},'updated_at')
            user_db.set_state(db,self.a,'plan',{'id':'plan-a','steps':[]})
        with user_db.db() as db:
            self.assertEqual([n['id'] for n in user_db.list_json(db,'notes',self.a,'updated_at')],['n1'])
            self.assertEqual([n['id'] for n in user_db.list_json(db,'notes',self.b,'updated_at')],['n2'])
            self.assertIsNone(user_db.get_state(db,self.b,'plan'))
            self.assertEqual(user_db.get_state(db,self.a,'plan')['id'],'plan-a')
        self.assertTrue(Path(os.environ['EXPO_USER_DATABASE']).is_file())

    def test_password_hashing_and_tokens(self):
        stored=user_db.hash_password('SecretPassword7')
        self.assertNotIn('SecretPassword7',stored)
        self.assertTrue(user_db.valid_password(stored,'SecretPassword7'))
        self.assertFalse(user_db.valid_password(stored,'wrong'))
        with user_db.db() as db:
            user=db.execute('SELECT * FROM users WHERE id=?',(self.a,)).fetchone()
            token=user_db.issue_session(db,user)['access_token']
        self.assertEqual(user_db.authenticate(token)['id'],self.a)
        self.assertIsNone(user_db.authenticate('invalid'))
        with user_db.db() as db:
            db.execute('UPDATE sessions SET expires_at=? WHERE user_id=?',('2020-01-01',self.a))
        self.assertIsNone(user_db.authenticate(token))

    def test_existing_pending_user_can_authenticate_without_mail_code(self):
        # Regression: earlier email-code releases created verified=0 accounts.
        with user_db.db() as db:
            db.execute('UPDATE users SET verified=0 WHERE id=?',(self.a,))
            db.execute('INSERT INTO profiles(user_id,payload,updated_at) VALUES(?,?,?)',
                       (self.a, '{"display_name":"Preserved","bio":"Saved"}',user_db.timestamp()))
            user = db.execute('SELECT * FROM users WHERE id=?',(self.a,)).fetchone()
            token = user_db.issue_session(db,user)['access_token']
        self.assertEqual(user_db.authenticate(token)['id'], self.a)
        with user_db.db() as db:
            self.assertEqual(user_db.as_json(db.execute('SELECT payload FROM profiles WHERE user_id=?',
                                                       (self.a,)).fetchone())['bio'], 'Saved')

    def test_upsert_and_fk_delete(self):
        with user_db.db() as db:
            user_db.put_json(db,'saved_places',self.a,'p1',{'id':'p1','title':'Old'})
            user_db.put_json(db,'saved_places',self.a,'p1',{'id':'p1','title':'New'})
            db.execute('INSERT INTO cv_files(user_id,file_name,bytes,uploaded_at) VALUES(?,?,?,?)',
                       (self.a,'cv.pdf',b'%PDF-test',user_db.timestamp()))
        with user_db.db() as db:
            self.assertEqual(len(user_db.list_json(db,'saved_places',self.a)),1)
            self.assertEqual(user_db.list_json(db,'saved_places',self.a)[0]['title'],'New')
            db.execute('DELETE FROM users WHERE id=?',(self.a,))
            self.assertEqual(db.execute('SELECT COUNT(*) FROM cv_files WHERE user_id=?',(self.a,)).fetchone()[0],0)
            self.assertEqual(len(user_db.list_json(db,'saved_places',self.a)),0)

if __name__=='__main__': unittest.main()
