import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import threading
import urllib.request
import urllib.error
from unittest.mock import patch
import desk


class Tests(unittest.TestCase):
    def test_http_session_and_journal(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / 'repo'; repo.mkdir()
            d = desk.Desk(repo, Path(tmp) / 'data')
            server = desk.http.server.ThreadingHTTPServer(('127.0.0.1', 0), desk.handler(d, 'secret'))
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            base = 'http://127.0.0.1:' + str(server.server_port)
            try:
                with urllib.request.urlopen(base) as response:
                    self.assertIn('AEGIS', response.read().decode())
                def post(path, payload, token):
                    req = urllib.request.Request(base + path, data=json.dumps(payload).encode(),
                        headers={'X-Desk-Token': token, 'Content-Type': 'application/json'})
                    return urllib.request.urlopen(req)
                with self.assertRaises(urllib.error.HTTPError) as failure:
                    post('/note', {'text': 'untrusted'}, 'wrong')
                self.assertEqual(failure.exception.code, 403)
                with post('/note', {'text': 'persisted'}, 'secret') as response:
                    self.assertEqual(json.load(response)['text'], 'persisted')
                with post('/bagua', {}, 'secret') as response:
                    self.assertEqual(json.load(response)['ordered_pairs'], 64)
                with self.assertRaises(urllib.error.HTTPError):
                    urllib.request.urlopen(base + '/../desk.py')
            finally:
                server.shutdown(); server.server_close(); thread.join()

    def test_bagua_bijection_and_walsh(self):
        b = desk.bagua()
        self.assertEqual(len({p['hexagram'] for p in b['pairs']}), 64)
        self.assertEqual({p['index'] for p in b['pairs']}, set(range(64)))
        self.assertTrue(b['walsh_HtH_equals_8I'])

    def test_axiom_fail_closed(self):
        for bad in ["'T' depends on axioms: [sorryAx]", "'T' depends on axioms: [Extra]",
                    "'Other' depends on axioms: []", "warning: unused\n'T' depends on axioms: []"]:
            with self.assertRaises(ValueError):
                desk.audit(bad, 'T')
        self.assertEqual(desk.audit("'T' depends on axioms: [propext,\n Classical.choice, Quot.sound]", 'T'),
                         sorted(desk.ALLOWED))

    def test_scope_and_persistence(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / 'repo'; repo.mkdir()
            data = Path(tmp) / 'data'
            (repo / 'T.lean').write_text('theorem T : True := by trivial\n')
            (repo / '.lake').mkdir(); (repo / '.lake' / 'Hidden.lean').write_text('theorem T')
            outside = Path(tmp) / 'outside.lean'; outside.write_text('theorem T')
            (repo / 'link.lean').symlink_to(outside)
            d = desk.Desk(repo, data)
            self.assertEqual(len(d.search('theorem T')), 1)
            d.save('note', {'text': 'Trigram 8 × 8'})
            self.assertEqual(desk.Desk(repo, data).journal()[0]['text'], 'Trigram 8 × 8')
            with self.assertRaises(ValueError):
                d.check('../outside.lean', 'T')
            with self.assertRaises(ValueError):
                d.check('T.lean', 'T\naxiom Bad : False')
            with patch.object(d, 'status', return_value={'head': 'abc', 'dirty': '', 'time': 'x'}):
                with patch('desk.subprocess.run', return_value=subprocess.CompletedProcess([], 0,
                        "'T' depends on axioms: [propext]")):
                    r = d.check('T.lean', 'T')
                    self.assertEqual(r['result'], 'LOCAL_SOURCE_AND_AXIOM_PASS')
                    self.assertIn('NOT audited', r['scope'])
                with patch('desk.subprocess.run', return_value=subprocess.CompletedProcess([], 0,
                        "'T' depends on axioms: [sorryAx]")):
                    self.assertEqual(d.check('T.lean', 'T')['result'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
