"""Validate provenance guards without reading/tuning the locked test split or invoking a judge."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ExportImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='commonplace-eval-import-')
        self.directory = Path(self.temp.name)
        self.queries = self.directory / 'queries.jsonl'
        self.queries.write_text(json.dumps({'id': 'fixture-1', 'query': 'Fixture?', 'category': 'factual'}) + '\n')
        self.answers = self.directory / 'answers.jsonl'
        self.answers.write_text(json.dumps({'id': 'fixture-1', 'answer': 'Fixture [1].', 'segments': [{'Text': 'Fixture '}, {'Cite': 1}]}) + '\n')
        self.metadata = self.directory / 'metadata.json'
        self.base = {'mode': 'accuracy', 'complete': True, 'physical_device': True, 'requested': 1, 'answered': 1,
                     'build': 'fixture-build', 'binary_sha256': 'a' * 64, 'model_sha256': 'b' * 64,
                     'model_file': 'fixture.gguf', 'device': 'FixturePhone'}

    def tearDown(self):
        self.temp.cleanup()

    def run_import(self, changes=None, *, required=True):
        meta = dict(self.base); meta.update(changes or {})
        self.metadata.write_text(json.dumps(meta))
        command = [sys.executable, str(ROOT / 'eval/import.py'), '--answers', str(self.answers), '--queries', str(self.queries),
                   '--run-id', 'fixture', '--system', 'fixture', '--model', 'fixture', '--metadata', str(self.metadata)]
        if required:
            command.append('--require-physical')
        return subprocess.run(command, env={**os.environ, 'EVAL_RUNS': str(self.directory / 'runs')}, capture_output=True, text=True)

    def test_physical_export_preserves_build_and_model(self):
        result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stderr)
        meta = json.loads((self.directory / 'runs/fixture/meta.json').read_text())
        self.assertEqual(meta['git'], 'fixture-build')
        self.assertEqual(meta['model']['sha256'], 'b' * 64)
        self.assertTrue(meta['phone'])

    def test_simulator_cannot_satisfy_physical_gate(self):
        result = self.run_import({'physical_device': False})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('simulator', result.stderr)

    def test_speed_and_incomplete_exports_are_refused(self):
        for changes in ({'mode': 'speed'}, {'complete': False}, {'answered': 0}, {'requested': 2}):
            self.assertNotEqual(self.run_import(changes).returncode, 0)

    def test_duplicate_answers_are_refused(self):
        with self.answers.open('a') as file:
            file.write(json.dumps({'id': 'fixture-1', 'answer': 'duplicate'}) + '\n')
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate', result.stderr)


if __name__ == '__main__':
    unittest.main()
