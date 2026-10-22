#!/usr/bin/env python3
"""Prove mirate RC5: processi locali e timer simulato, nessuna modifica al sistema."""
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
AGY = (ROOT / 'payload/ops/maint/ops-agy').read_text()
BOOT = (ROOT / 'bootstrap.sh').read_text()
INSTALL = (ROOT / 'payload/ops/docs/bootstrap/ops-installa').read_text()
UFW = (ROOT / 'payload/ops/docs/bootstrap/passo7-impostazioni.sh').read_text()


def section(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]


class Reliability(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def runbash(self, text):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\n' + text],
                              text=True, capture_output=True, timeout=10)

    def version(self, body, *, verify=False, fast_timeout=False, root_mode=False):
        binary = self.root / 'agy'
        binary.write_text('#!/bin/bash\n' + body + '\n')
        binary.chmod(0o755)
        code = 'id() { echo ' + ('0' if root_mode else '1000') + '; }\n'
        if root_mode:
            code += ('runuser() { [ "$1 $2 $3" = "-u nobody --" ] || return 91; '
                     'shift 3; "$@"; }\n')
        if fast_timeout:
            # Verifica le opzioni effettive, accorciando solo i tempi della prova.
            code += ('timeout() { [ "$1" = --kill-after=5s ] && [ "$2" = 30s ] || return 90; '
                     'shift 2; command timeout --kill-after=0.1s 0.1s "$@"; }\n')
        code += section(AGY, 'version_of() {', 'in_use() {')
        if verify:
            code += section(AGY, 'cmd_verify() {', '\ncase ${1:-}')
            code += ('stat() { echo "root:root 755"; }\nrestriction_active() { return 1; }\n'
                     f'BIN={shlex.quote(str(binary))}; DIR={shlex.quote(str(self.root))}\n'
                     'cmd_verify\necho REACHED_SUCCESS\n')
        else:
            code += 'version_of ' + shlex.quote(str(binary))
        return self.runbash(code)

    def test_version_success_drains_multiple_lines(self):
        r = self.version('echo 1.4.4; for ((i=0;i<10000;i++)); do echo extra; done')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, '1.4.4\n')

    def test_version_failure_keeps_code_and_stderr(self):
        r = self.version('echo VERSION_FAILURE >&2; exit 37')
        self.assertEqual(r.returncode, 37)
        self.assertIn('VERSION_FAILURE', r.stderr)
        self.assertIn('codice 37', r.stderr)

    def test_root_probe_uses_nobody_and_clean_environment(self):
        r = self.version('[ "$HOME" = /tmp ] && [ "$AGY_CLI_DISABLE_AUTO_UPDATE" = true ] || exit 92; echo 1.4.4', root_mode=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, '1.4.4\n')

    def test_root_probe_keeps_error(self):
        r = self.version('echo ROOT_PROBE_FAILURE >&2; exit 37', root_mode=True)
        self.assertEqual(r.returncode, 37)
        self.assertIn('ROOT_PROBE_FAILURE', r.stderr)

    def test_empty_version_fails(self):
        r = self.version('exit 0')
        self.assertEqual(r.returncode, 1)
        self.assertIn('non ha restituito', r.stderr)

    def test_timeout_kills_process_ignoring_term(self):
        r = self.version("trap '' TERM; while :; do sleep 1; done", fast_timeout=True)
        self.assertEqual(r.returncode, 137, r.stderr)
        self.assertIn('codice 137', r.stderr)

    def test_verify_failure_is_explicit_and_stops(self):
        r = self.version('echo VERSION_FAILURE >&2; exit 37', verify=True)
        self.assertEqual(r.returncode, 37)
        self.assertIn('KO ', r.stderr)
        self.assertNotIn('REACHED_SUCCESS', r.stdout)

    def test_verify_success(self):
        r = self.version('echo 1.4.4', verify=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('ok  versione 1.4.4', r.stdout)
        self.assertIn('REACHED_SUCCESS', r.stdout)

    def test_bootstrap_pipeline_stops_with_real_code(self):
        stage = self.root / 'ops/maint'
        stage.mkdir(parents=True)
        pipeline = section(BOOT, 'AGY_RC=0\n', '\nfi\n') + '\nfi\n'
        for rc in (0, 37, 124):
            with self.subTest(rc=rc):
                (stage / 'ops-agy').write_text(f'echo AGY_OUTPUT; exit {rc}\n')
                log = self.root / 'bootstrap.log'
                r = self.runbash(f'STAGE={shlex.quote(str(self.root))}\nLOG={shlex.quote(str(log))}\n'
                                 'log() { printf "%s\\n" "$*" | tee -a "$LOG"; }\n'
                                 + pipeline + 'echo FOUNDATION_STARTED\n')
                self.assertEqual(r.returncode, rc, r.stderr)
                self.assertIn('AGY_OUTPUT', log.read_text())
                self.assertEqual('FOUNDATION_STARTED' in r.stdout, rc == 0)
                if rc:
                    self.assertIn(f'codice {rc}', log.read_text())

    def deadline(self, contents):
        (self.root / 'passo7-ufw.state').write_text(contents)
        return self.runbash(f'LIBDIR={shlex.quote(str(self.root))}\n'
                            + section(INSTALL, 'ufw_deadline() {', '\nact_ufw() {')
                            + 'ufw_deadline\n')

    def test_deadline_reads_persisted_value(self):
        r = self.deadline('rollback_epoch=0\n')
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout.strip(), '1970-01-01 00:00:00 UTC')

    def test_old_or_invalid_state_does_not_invent_deadline(self):
        for value in ('bak_suffix=.bak-2026-10-21\n', 'rollback_epoch=invalid\n',
                      'rollback_epoch=1\nrollback_epoch=2\n'):
            with self.subTest(value=value):
                r = self.deadline(value)
                self.assertEqual(r.returncode, 0)
                self.assertIn('orario non disponibile', r.stdout)

    def test_arm_records_same_deadline_before_enable(self):
        arm = section(UFW, 'RB_EPOCH=', '\necho "== VERIFY"')
        state = self.root / 'passo7-ufw.state'
        r = self.runbash(f'STATE={shlex.quote(str(state))}; ROLLBACK_MIN=10; RB_UNIT=test\n'
                         'systemd-run() { echo ARMED; }\nsystemctl() { return 0; }\n'
                         'die() { echo "$*" >&2; exit 1; }\n'
                         'ufw() { grep -q "^rollback_epoch=" "$STATE"; echo ENABLED; }\n'
                         + arm + '\nLIBDIR=' + shlex.quote(str(self.root)) + '\n'
                         + section(INSTALL, 'ufw_deadline() {', '\nact_ufw() {')
                         + '[ "$(ufw_deadline)" = "$RB_AT" ]\n')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('ARMED\nENABLED', r.stdout)

    def firewall(self, mode):
        # Ripresa reale della funzione; solo rete, stato e systemd sono simulati.
        code = ('RB_UNIT=test; TTY_OK=1; active=1; new=0\n'
                'st_get() { echo attesa-ssh; }\n'
                'systemctl() { [ "$active" = 1 ]; }\n'
                'ufw_active() { return 1; }\n'
                'new_ssh() { if [ "$new" = 1 ]; then echo new-login; fi; }\n'
                'ufw_deadline() { echo SHARED_DEADLINE; }\n'
                'say() { echo "$*"; }\n'
                'st_set() { echo "STATE $*"; }\nst_meta_set() { :; }\n'
                'run_logged() { echo CONFIRMED; }\nP=/unused\n')
        answers = {'success': 'REPLY_TXT=""; new=1',
                   'expired': 'REPLY_TXT=""; active=0',
                   'later': 'REPLY_TXT=dopo'}
        code += 'ask() { ' + answers[mode] + '; }\n'
        code += section(INSTALL, 'act_ufw() {', '\nact_backup() {')
        return self.runbash(code + '\nact_ufw\n')

    def test_new_ssh_confirms(self):
        r = self.firewall('success')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('CONFIRMED', r.stdout)
        self.assertIn('STATE 7 fatto', r.stdout)

    def test_expired_timer_never_confirms(self):
        r = self.firewall('expired')
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertNotIn('CONFIRMED', r.stdout)
        self.assertIn('STATE 7 errore', r.stdout)

    def test_later_waits_without_confirming(self):
        r = self.firewall('later')
        self.assertEqual(r.returncode, 5, r.stderr)
        self.assertNotIn('CONFIRMED', r.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
