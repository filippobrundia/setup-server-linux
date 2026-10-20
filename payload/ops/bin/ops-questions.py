#!/usr/bin/env python3
"""Registro amministrativo persistente; non esegue comandi né concede permessi."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys

STATES = ['analisi', 'approvazione', 'approvata', 'esecuzione', 'verifica', 'chiusa']
TOPICS = {
    '10': 'Backup: copertura, destinazione, retention, recupero e attivazione',
    '2': 'Storage: layout, dati da conservare e recupero',
    '7.1': 'Rete stabile: indirizzo e accessibilità',
    '10.3': 'Backup: cosa salvare, destinazione, retention, costi e ripristino',
    '11.2': 'Monitoraggio esterno: servizio e dati trasmessi',
    '12.8': 'Finestra: interruzioni consentite e primo riavvio presidiato',
    'finalrd': 'Diagnosticare il fallimento finalrd del precedente spegnimento',
    'kb-sync': 'Ripristinare la sincronizzazione facoltativa della Knowledge Base',
    'journal': 'Analizzare e classificare gli eventi di errore del boot corrente',
}

def observations(runner=subprocess.run):
    """Sola lettura, durata limitata; non deduce guasti dalla mancanza di accesso."""
    result = {}
    try:
        r = runner(['journalctl', '-b', '-1', '-u', 'finalrd.service', '-n', '100', '--no-pager', '-o', 'cat'],
                   capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return {}
    if r.returncode == 0 and ('Failed with result' in r.stdout or 'status=73/CANTCREAT' in r.stdout):
        result['finalrd'] = 'Journal del boot precedente: finalrd fallito; diagnosi necessaria, non certificato innocuo.'
    try:
        current = runner(['journalctl', '-b', '-p', 'err', '-n', '50', '--no-pager', '-q', '-o', 'cat'],
                         capture_output=True, text=True, timeout=5)
        if current.returncode == 0 and current.stdout.strip():
            result['journal'] = 'Eventi del boot corrente da classificare; non dedurre guasti dal solo conteggio.'
    except (OSError, subprocess.TimeoutExpired):
        pass
    return result

def new_record(key):
    technical = key in ('finalrd', 'kb-sync', 'journal')
    return dict(title=TOPICS[key], state='analisi', history=[], kind='attivita' if technical else 'decisione',
                requires_approval=not technical, analysis='', alternatives='', recommendation='',
                approval='', execution='', verification='')

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ops', type=Path, default=Path('/srv/ops'))
    sub = p.add_subparsers(dest='command', required=True)
    sub.add_parser('sync')
    sub.add_parser('next')
    sub.add_parser('report')
    collect = sub.add_parser('collect')
    collect.add_argument('--kb-failed', action='store_true')
    advance = sub.add_parser('advance')
    advance.add_argument('id', choices=TOPICS)
    advance.add_argument('state', choices=STATES + ['sospesa'])
    advance.add_argument('--evidence', required=True, help='Motivo o riferimento non segreto a prova/approvazione')
    args = p.parse_args()
    if args.command == 'advance' and not args.evidence.strip():
        raise ValueError('riferimento alle evidenze vuoto')
    root = args.ops / 'docs' / 'admin-questions'
    # Registro documentale dell'amministratore, mai letto da root come autorizzazione.
    if root.is_symlink() or root.parent.is_symlink() or args.ops.is_symlink():
        raise ValueError('percorso symlink rifiutato')
    root.mkdir(exist_ok=True)
    lock = root / '.lock'
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        path = root / 'register.json'
        if path.is_symlink():
            raise ValueError('registro symlink rifiutato')
        records = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
        dirty = not path.exists()
        if args.command == 'sync':
            conf = (args.ops / 'host.conf').read_text(encoding='utf-8')
            declarations = [line for line in conf.splitlines() if line.startswith('ESCLUSIONI=')]
            if len(declarations) != 1:
                raise ValueError('ESCLUSIONI assente o duplicata')
            found = re.fullmatch(r'ESCLUSIONI="([0-9.b ]*)"[ \t]*(?:#.*)?', declarations[0])
            if found is None:
                raise ValueError('ESCLUSIONI non valida')
            for key in found[1].split():
                key = '10' if key == '10b' else key
                if key not in TOPICS:
                    raise ValueError('questione sconosciuta')
                if key not in records:
                    records[key] = new_record(key)
                    dirty = True
        elif args.command == 'collect':
            detected = observations()
            if args.kb_failed:
                detected['kb-sync'] = 'Sync KB fallita al termine della foundation; copia locale e cron da verificare.'
            for key, evidence in detected.items():
                if key not in records:
                    records[key] = new_record(key)
                    records[key]['history'].append(dict(date=dt.datetime.now(dt.timezone.utc).isoformat(),
                                                        state='analisi', evidence=evidence))
                    dirty = True
        elif args.command == 'advance':
            record = records[args.id]
            previous = record['state']
            suspending = args.state == 'sospesa' and previous not in ('chiusa', 'sospesa')
            resuming = previous == 'sospesa' and args.state == 'analisi'
            if (previous == 'sospesa' or args.state == 'sospesa') and not (suspending or resuming):
                raise ValueError('una questione sospesa riparte solo da analisi con nuove evidenze')
            current = STATES.index(previous) if previous in STATES else -1
            target = STATES.index(args.state) if args.state in STATES else -1
            routine_start = (not record.get('requires_approval', True) and current == 0 and args.state == 'esecuzione')
            if target != current + 1 and not (routine_start or suspending or resuming):
                raise ValueError('transizione non consecutiva')
            if routine_start and not all(record[k].strip() for k in ('analysis', 'recommendation')):
                raise ValueError('analisi e raccomandazione necessarie prima del lavoro ordinario')
            active = [k for k, r in records.items() if r['state'] not in ('analisi', 'chiusa', 'sospesa')]
            if active and active != [args.id] and not suspending:
                raise ValueError('concludere prima la questione attiva: ' + active[0])
            if args.state == 'approvazione' and not all(record[k].strip() for k in ('analysis', 'alternatives', 'recommendation')):
                raise ValueError('compilare analisi, alternative e raccomandazione nel registro prima della proposta')
            record['state'] = args.state
            if resuming:
                # La vecchia approvazione resta nella storia, ma non e riutilizzabile.
                record['approval'] = ''
            field = {'approvata': 'approval', 'esecuzione': 'execution', 'verifica': 'execution', 'chiusa': 'verification'}.get(args.state)
            if field:
                record[field] = args.evidence
            record['history'].append(dict(date=dt.datetime.now(dt.timezone.utc).isoformat(),
                                          state=args.state, evidence=args.evidence))
            dirty = True
        if dirty:
            tmp = root / '.register.tmp'
            with tmp.open('x', encoding='utf-8') as stream:
                json.dump(records, stream, ensure_ascii=False, indent=2)
                stream.write('\n')
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(tmp, path)
        pending = [(k, r) for k, r in records.items() if r['state'] != 'chiusa']
        if args.command == 'next':
            pending = [(k, r) for k, r in pending if r['state'] != 'sospesa']
            priority = {'10': 0, 'finalrd': 1, 'kb-sync': 2}
            pending = sorted(pending, key=lambda pair: (pair[1]['state'] == 'analisi', priority.get(pair[0], 10)))[:1]
        for key, record in pending:
            print(f"{key}: {record['state']} — {record['title']}")
        if not pending:
            print('Nessuna questione selezionabile (verificare anche le sospese con report); non costituisce verifica del server.')
    finally:
        os.close(fd)
        lock.unlink()

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        sys.exit('Registro non aggiornato: ' + str(exc))
