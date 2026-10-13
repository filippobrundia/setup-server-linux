#!/usr/bin/env python3
"""Prove documentali senza sistema simulato presentato come macchina reale."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

PKG = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('memoria', PKG / 'payload/ops/bin/memoria-iniziale.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class MemoryTest(unittest.TestCase):
    def test_preserves_custom_and_updates_single_section(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / 'overview.md'
            p.write_text('# Overview\n\nConfigurazione scritta dal proprietario.\n')
            p.write_text(m.section(p, 'Overview', 'prima'))
            second = m.section(p, 'Overview', 'seconda')
            self.assertIn('Configurazione scritta dal proprietario.', second)
            self.assertNotIn('prima', second)
            self.assertEqual(second.count(m.BEGIN), 1)

    def test_bad_markers_refused(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / 'overview.md'
            p.write_text(m.BEGIN + '\n')
            with self.assertRaises(ValueError):
                m.section(p, 'Overview', 'nuova')

    def test_secrets_and_shell_are_not_loaded(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / 'host.conf'
            p.write_text('HOST="test"\nSECRET="NON_DEVE_ENTRARE"\n$(touch /tmp/no)\n')
            self.assertEqual(m.values(p), {'HOST': 'test'})

    def test_duplicate_parameters_refused(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / 'host.conf'
            p.write_text('HOST="one"\nHOST="two"\n')
            with self.assertRaises(ValueError):
                m.values(p)

    def test_complete_memory_and_honest_exclusions(self):
        with tempfile.TemporaryDirectory() as t:
            ops = Path(t)
            agents = (PKG / 'payload/ops/AGENTS.md.tmpl').read_text().replace('@@ADMIN@@', 'test')
            (ops / 'AGENTS.md').write_text(agents)
            data = dict(conf={'HOST': 'test', 'ADMIN': 'test', 'PROFILO': 'docker',
                              'ESCLUSIONI': '7.1 10.3 11.2 12.8', 'SERVICES': 'ssh cron docker'},
                        host='test', os='Ubuntu test', kernel='test', date='test',
                        state='STATO: COMPLETATO CON ESCLUSIONI', units='active', addresses='test',
                        routes='test', mounts='test')
            docs = m.render(ops, data)
            self.assertNotIn('Da compilare al termine', docs[ops / 'AGENTS.md'])
            self.assertIn('Prossimo passo:', docs[ops / 'STATUS.md'])
            self.assertIn('manutenzione bloccati', docs[ops / 'docs/future-improvements.md'])
            self.assertIn('non certificati', docs[ops / 'docs/system.md'])


if __name__ == '__main__':
    unittest.main()
