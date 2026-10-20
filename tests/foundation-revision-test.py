#!/usr/bin/env python3
"""Test isolati del registro e dei guardrail: nessuna modifica al sistema."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / 'payload/ops/bin/ops-questions.py'

class BackupPreflight(unittest.TestCase):
    def test_missing_repository_stops_before_mutations(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = ROOT / 'payload/ops/docs/bootstrap/passo10b-rotazione-verifica.sh'
            script = base / source.name
            script.write_bytes(source.read_bytes())
            # Solo identita e configurazione simulate; il controllo e lo script sono reali.
            common = base / 'passi-comune.sh'
            for value in ('', str(base / 'nonexistent')):
                common.write_text('TEMPLATES=/unused\nid() { echo 0; }\n'
                                  + 'load_host_conf() { BORG_REPO="' + value + '"; }\n')
                result = subprocess.run(['bash', str(script)], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('BORG_REPO', result.stderr)
                self.assertIn('nessuna modifica', result.stderr)
                self.assertNotIn('== 1. ROTAZIONE', result.stdout)

class Questions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ops = Path(self.tmp.name)
        (self.ops / 'docs').mkdir()
        (self.ops / 'host.conf').write_text('ESCLUSIONI="10.3 12.8"\n')

    def runq(self, *args, ok=True):
        result = subprocess.run([sys.executable, str(TOOL), '--ops', str(self.ops), *args], capture_output=True, text=True, encoding='utf-8', env={**os.environ, 'PYTHONIOENCODING': 'utf-8'})
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def path(self):
        return self.ops / 'docs/admin-questions/register.json'

    def prepared(self):
        self.runq('sync')
        data = json.loads(self.path().read_text(encoding='utf-8'))
        for rec in data.values():
            for field in ('analysis', 'alternatives', 'recommendation'):
                rec[field] = 'Analisi documentata di prova'
        self.path().write_text(json.dumps(data), encoding='utf-8')

    def test_idempotent_resume(self):
        self.runq('sync')
        before = self.path().read_bytes()
        self.runq('sync')
        self.assertEqual(before, self.path().read_bytes())
        self.assertIn('10.3: analisi', self.runq('next').stdout)

    def test_no_skipped_approval(self):
        self.runq('sync')
        self.runq('advance', '10.3', 'chiusa', '--evidence', 'prova', ok=False)
        self.runq('advance', '10.3', 'approvazione', '--evidence', 'proposta', ok=False)

    def test_one_at_time_and_verified_closure(self):
        self.prepared()
        self.runq('advance', '10.3', 'approvazione', '--evidence', 'proposta')
        self.runq('advance', '12.8', 'approvazione', '--evidence', 'proposta', ok=False)
        self.assertIn('10.3:', self.runq('next').stdout)
        for state in ('approvata', 'esecuzione', 'verifica', 'chiusa'):
            self.runq('advance', '10.3', state, '--evidence', 'riferimento prova')
        self.assertNotIn('10.3:', self.runq('report').stdout)
        self.assertEqual(len(json.loads(self.path().read_text())['10.3']['history']), 5)

    def test_suspend_unblocks_next_and_resume_requires_new_approval(self):
        self.prepared()
        self.runq('advance', '10.3', 'approvazione', '--evidence', 'proposta')
        self.runq('advance', '10.3', 'approvata', '--evidence', 'approvazione originale')
        self.runq('advance', '10.3', 'sospesa', '--evidence', 'mandato cambiato')
        self.assertIn('10.3: sospesa', self.runq('report').stdout)
        self.assertIn('12.8:', self.runq('next').stdout)
        self.runq('advance', '12.8', 'approvazione', '--evidence', 'altra proposta')
        self.runq('advance', '10.3', 'esecuzione', '--evidence', 'riuso vietato', ok=False)
        self.runq('advance', '12.8', 'sospesa', '--evidence', 'rinvio')
        self.assertIn('Nessuna questione selezionabile', self.runq('next').stdout)
        self.runq('advance', '10.3', 'analisi', '--evidence', 'nuovo mandato')
        data = json.loads(self.path().read_text(encoding='utf-8'))['10.3']
        self.assertEqual(data['approval'], '')
        self.assertTrue(any(h['evidence'] == 'approvazione originale' for h in data['history']))
        self.runq('advance', '10.3', 'esecuzione', '--evidence', 'salto vietato', ok=False)
        self.runq('advance', '10.3', 'approvazione', '--evidence', 'nuova proposta')
        self.runq('advance', '10.3', 'approvata', '--evidence', 'nuova approvazione')

    def test_suspension_requires_evidence_and_cannot_reopen_closed(self):
        self.prepared()
        self.runq('advance', '10.3', 'sospesa', '--evidence', ' ', ok=False)
        for state in ('approvazione', 'approvata', 'esecuzione', 'verifica', 'chiusa'):
            self.runq('advance', '10.3', state, '--evidence', 'prova')
        self.runq('advance', '10.3', 'sospesa', '--evidence', 'vietato', ok=False)

    def test_lock_and_duplicate_configuration(self):
        self.runq('sync')
        lock = self.path().parent / '.lock'
        lock.touch()
        self.runq('sync', ok=False)
        lock.unlink()
        (self.ops / 'host.conf').write_text('ESCLUSIONI="10.3"\nESCLUSIONI=""\n')
        self.runq('sync', ok=False)

    def test_no_exclusions_writes_empty_register(self):
        (self.ops / 'host.conf').write_text('ESCLUSIONI=""\n')
        self.runq('sync')
        self.assertEqual(json.loads(self.path().read_text()), {})

    def test_real_host_template_preserves_comment_after_parameter_detection(self):
        conf = (ROOT / 'payload/ops/host.conf.tmpl').read_text()
        conf = conf.replace('ESCLUSIONI=""', 'ESCLUSIONI="7.1 10.3 11.2 12.8"')
        (self.ops / 'host.conf').write_text(conf)
        self.runq('sync')
        before = self.path().read_bytes()
        self.runq('sync')
        self.assertEqual(before, self.path().read_bytes())
        self.assertEqual(set(json.loads(before)), {'7.1', '10.3', '11.2', '12.8'})

    def test_duplicate_malformed_declaration_is_rejected(self):
        (self.ops / 'host.conf').write_text('ESCLUSIONI="10.3" # valida\nESCLUSIONI=invalid\n')
        self.runq('sync', ok=False)

    def test_comment_removal_workaround_preserves_parameter_value(self):
        import re
        conf = (ROOT / 'payload/ops/host.conf.tmpl').read_text().replace('ESCLUSIONI=""', 'ESCLUSIONI="7.1 10.3 11.2 12.8"')
        conf = re.sub(r'(?m)^(ESCLUSIONI=.*?)[ \t]*#.*$', r'\1', conf)
        (self.ops / 'host.conf').write_text(conf)
        self.runq('sync')
        self.assertEqual(set(json.loads(self.path().read_text())), {'7.1', '10.3', '11.2', '12.8'})

    def test_backup_dependencies_are_one_decision(self):
        (self.ops / 'host.conf').write_text('ESCLUSIONI="7.1 10 10b 10.3 11.2 12.8" # foundation\n')
        self.runq('sync')
        r=json.loads(self.path().read_text())
        self.assertIn('10', r)
        self.assertNotIn('10b', r)
        self.assertIn('10: analisi', self.runq('next').stdout)

    def test_technical_task_does_not_require_banal_approval(self):
        self.runq('sync')
        self.runq('collect', '--kb-failed')
        r=json.loads(self.path().read_text())
        self.assertFalse(r['kb-sync']['requires_approval'])
        r['kb-sync']['analysis']='Token da rinnovare personalmente; controlli locali autorizzati'
        r['kb-sync']['recommendation']='Verificare stato senza stampare credenziali'
        self.path().write_text(json.dumps(r))
        self.runq('advance','kb-sync','esecuzione','--evidence','Policy lettura ordinaria')

    def test_observations_distinguish_failures_from_unavailable_access(self):
        spec=importlib.util.spec_from_file_location('questions', TOOL)
        mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        self.assertIn('finalrd', mod.observations(lambda *a,**k: subprocess.CompletedProcess(a,0,'status=73/CANTCREAT','')))
        self.assertEqual({}, mod.observations(lambda *a,**k: subprocess.CompletedProcess(a,1,'','access denied')))

class Maintenance(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        script = (ROOT / 'payload/ops/maint/ops-maint').read_text()
        self.lib = self.base / 'lib.sh'
        self.lib.write_text(script.split('\nMODE=${1:-}')[0], newline='\n', encoding='utf-8')
        self.bash = os.environ.get('BASH_TEST_EXE') or shutil.which('bash')
        if not self.bash:
            self.skipTest('Bash assente')

    def shell(self, body, expected=0):
        script = f'''source '{self.lib.as_posix()}'
DRY=1
INBOX='{self.base.as_posix()}'
AUTO_UPGRADES=yes
AUTO_LIST=''
ORIGINS_RE='Ubuntu:26\\.04/resolute-updates[ ,]'
dpkg-query() {{ printf ii; }}
apt-cache() {{ printf 'Candidate: 2.0\\n'; }}
apt-get() {{ printf '%s\\n' "$SIM"; }}
SIM='Inst curl [1.0] (2.0 Ubuntu:26.04/resolute-updates [amd64])'
{body}
'''
        result = subprocess.run([self.bash, '-c', script], capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_auto_plan_is_memory_only(self):
        self.shell('select_routine; validate_list; [[ "${PKGS[*]}" == curl=2.0 ]]')
        self.assertFalse((self.base / 'approved-upgrades').exists())

    def test_health_honours_exit_code(self):
        self.shell('id() { echo 1000; }; QUICK=false; health', expected=1)

    def test_foreign_origin_rejected(self):
        self.shell("SIM='Inst curl [1.0] (2.0 Unknown:stable [amd64])'; select_routine; validate_list", expected=1)

    def test_unplanned_dependency_rejected(self):
        self.shell('select_routine; SIM+=$\'\\nInst extra [1.0] (2.0 Ubuntu:26.04/resolute-updates [amd64])\'; validate_list', expected=1)

    def test_new_package_deferred(self):
        result = self.shell("dpkg-query() { printf 'un'; }; select_routine; echo UNSAFE")
        self.assertIn('RINVIO:', result.stdout)
        self.assertNotIn('UNSAFE', result.stdout)

    def test_removal_deferred(self):
        result = self.shell("SIM='Remv curl [1.0]'; select_routine; echo UNSAFE")
        self.assertIn('RINVIO:', result.stdout)
        self.assertNotIn('UNSAFE', result.stdout)

    def test_legacy_configuration_does_not_auto_select(self):
        self.shell('AUTO_UPGRADES=""; select_routine; [[ -z "$AUTO_LIST" ]]')

    def test_changed_candidate_deferred(self):
        result = self.shell("select_routine; apt-cache() { printf 'Candidate: 3.0\\n'; }; validate_list; echo UNSAFE")
        self.assertIn('RINVIO:', result.stdout)
        self.assertNotIn('UNSAFE', result.stdout)

    def test_rollback_missing_returns_failure(self):
        self.shell(f"ROLLBACK='{self.base.as_posix()}/rollback'; PKGS=(curl=2.0); apt-get() {{ return 1; }}; save_rollback", expected=1)

if __name__ == '__main__':
    unittest.main(verbosity=2)
