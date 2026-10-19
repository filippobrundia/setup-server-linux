#!/usr/bin/env python3
"""Registro amministrativo persistente; non esegue comandi né concede permessi."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import sys

STATES = ['analisi', 'approvazione', 'approvata', 'esecuzione', 'verifica', 'chiusa']
TOPICS = {
    '2': 'Storage: layout, dati da conservare e recupero',
    '7.1': 'Rete stabile: indirizzo e accessibilità',
    '10.3': 'Backup: cosa salvare, destinazione, retention, costi e ripristino',
    '11.2': 'Monitoraggio esterno: servizio e dati trasmessi',
    '12.8': 'Finestra: interruzioni consentite e primo riavvio presidiato',
}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ops', type=Path, default=Path('/srv/ops'))
    sub = p.add_subparsers(dest='command', required=True)
    sub.add_parser('sync')
    sub.add_parser('next')
    sub.add_parser('report')
    advance = sub.add_parser('advance')
    advance.add_argument('id', choices=TOPICS)
    advance.add_argument('state', choices=STATES)
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
            found = re.findall(r'^ESCLUSIONI="([0-9. ]*)"\s*$', conf, re.M)
            if len(found) != 1:
                raise ValueError('ESCLUSIONI assente o duplicata')
            for key in found[0].split():
                if key not in TOPICS:
                    raise ValueError('questione sconosciuta')
                if key not in records:
                    records[key] = dict(title=TOPICS[key], state='analisi', history=[],
                                        analysis='', alternatives='', recommendation='',
                                        approval='', execution='', verification='')
                    dirty = True
        elif args.command == 'advance':
            record = records[args.id]
            current, target = STATES.index(record['state']), STATES.index(args.state)
            if target != current + 1:
                raise ValueError('transizione non consecutiva')
            active = [k for k, r in records.items() if r['state'] not in ('analisi', 'chiusa')]
            if active and active != [args.id]:
                raise ValueError('concludere prima la questione attiva: ' + active[0])
            if args.state == 'approvazione' and not all(record[k].strip() for k in ('analysis', 'alternatives', 'recommendation')):
                raise ValueError('compilare analisi, alternative e raccomandazione nel registro prima della proposta')
            record['state'] = args.state
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
            pending = sorted(pending, key=lambda pair: pair[1]['state'] == 'analisi')[:1]
        for key, record in pending:
            print(f"{key}: {record['state']} — {record['title']}")
        if not pending:
            print('Nessuna questione registrata aperta; non costituisce verifica del server.')
    finally:
        os.close(fd)
        lock.unlink()

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        sys.exit('Registro non aggiornato: ' + str(exc))
