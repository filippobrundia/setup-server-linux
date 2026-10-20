#!/usr/bin/env python3
"""Consolida dati verificati dopo il setup; nessun segreto, login o modello."""
import datetime
import os
from pathlib import Path
import re
import subprocess
import sys

BEGIN = '<!-- ops:configurazione-verificata -->'
END = '<!-- /ops:configurazione-verificata -->'
KEYS = ('HOST', 'ADMIN', 'PROFILO', 'LAN_CIDR', 'MOUNTS', 'DATA_MOUNT',
        'SERVICES', 'CONTAINERS', 'ESCLUSIONI', 'KB_SCELTA', 'FOUNDATION_ONLY')
REASONS = {
    '2': 'layout dei dischi dedicato non collaudato',
    '7.1': 'rete statica non configurata',
    '10': 'copertura, destinazione e recupero del backup da decidere; backup NON configurato',
    '10b': 'rotazione e ripristino del backup rinviati con la decisione 10',
    '10.3': 'copia remota non configurata: gate e manutenzione bloccati',
    '11.2': 'monitoraggio esterno non configurato',
    '12.8': 'finestra di manutenzione automatica non attivata',
}


def values(path):
    """Legge solo le chiavi ammesse; non esegue configurazioni shell."""
    result = {}
    for line in path.read_text().splitlines():
        m = re.fullmatch(r'([A-Z_]+)=(?:"([^"\n]*)"|([^\s#]*))\s*(?:#.*)?', line)
        if m and m[1] in KEYS:
            if m[1] in result:
                raise ValueError('parametro duplicato: ' + m[1])
            result[m[1]] = m[2] if m[2] is not None else m[3]
    return result


def command(args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=30)
        return '\n'.join(line.rstrip() for line in r.stdout.strip().splitlines()) if r.returncode == 0 else 'non verificato'
    except (OSError, subprocess.TimeoutExpired):
        return 'non verificato'


def code(text):
    # Dati locali, trattati come testo e mai come istruzioni Markdown.
    return '`' + re.sub(r'[\x00-\x1f`<>]', ' ', text) + '`'


def section(path, title, body):
    old = path.read_text() if path.exists() else '# ' + title + '\n'
    # Rimuove soltanto il paragrafo noto dei modelli, mai testo personalizzato.
    old = re.sub(r'(?m)^[^\n]*Da compilare durante la configurazione iniziale con quanto verificato sul sistema\n'
                 r'reale \(checklist in `docs/bootstrap/configurazione-server-base.md`\)\.\n?', '', old)
    if old.count(BEGIN) != old.count(END) or old.count(BEGIN) > 1:
        raise ValueError('marcatori non validi: ' + str(path))
    block = BEGIN + '\n## Configurazione iniziale verificata\n\n' + body + '\n' + END
    if BEGIN in old:
        start, stop = old.index(BEGIN), old.index(END) + len(END)
        new = old[:start] + block + old[stop:]
    else:
        new = old.rstrip() + '\n\n' + block + '\n'
    return new


def render(ops, data):
    host, conf = data['host'], data['conf']
    state = data['state']
    exclusions = conf.get('ESCLUSIONI', '').split()
    excluded = '\n'.join('- ' + k + ': ' + REASONS.get(k, 'non collaudato') + '.' for k in exclusions)
    stamp = 'Rilevato in UTC: ' + data['date'] + '.\n\n'
    base = (f'Host: {code(host)}. Sistema: {code(data["os"])}; kernel: {code(data["kernel"])}.\n\n'
            f'Amministratore: {code(conf.get("ADMIN", "non registrato"))}. Profilo: {code(conf.get("PROFILO", ""))}.\n\n'
            f'Esito: {state}.\n\n')
    next_step = ('Prossimo passo: scegliere un agente con `agente`, autenticare solo quello e chiedere il resoconto. '
                 'Leggere prima `python3 bin/ops-questions.py next`: un attivita alla volta, autorizzazioni ordinarie gia valide. '
                 'Le esclusioni restano nel registro e non sono prove superate.')
    docs = {
        'docs/overview.md': stamp + base + 'Servizi attesi: ' + code(conf.get('SERVICES', '')) + '.\n\n' + next_step,
        'docs/system.md': stamp + 'Stato dei servizi attesi (ordine: ' + code(conf.get('SERVICES', '')) + '):\n\n'
                          + '```text\n' + data['units'] + '\n```\n\nAgenti installati; login e utilizzo non certificati dalla sola installazione.',
        'docs/network.md': stamp + 'LAN ammessa per SSH: ' + code(conf.get('LAN_CIDR', '')) + '.\n\n'
                           + '```text\n' + data['addresses'] + '\n' + data['routes'] + '\n```\n\n'
                           + ('Rete statica esclusa: indirizzo DHCP variabile; mantenere disponibile la console.' if '7.1' in exclusions
                              else 'Configurazione stabile: esito del passo 7.1 nei log; nessuna credenziale di rete riportata.'),
        'docs/storage-backup.md': stamp + 'Montaggi attesi: ' + code(conf.get('MOUNTS', ''))
                                 + '. Dati: ' + code(conf.get('DATA_MOUNT', '')) + '.\n\n```text\n' + data['mounts']
                                 + '\n```\n\n' + ('Backup locale e ripristino RINVIATI: nessun backup o restore certificato.\n\n' if '10' in exclusions else 'Backup locale e ripristino: consultare esiti 10 e 10b in /var/log/ops-installa/.\n\n')
                                 + ('Copia remota esclusa; non dichiarare disaster recovery completa.' if '10.3' in exclusions
                                    else 'Copia remota: esito e prova nei log, non dedotti dalla sola presenza della configurazione.'),
        'docs/security.md': stamp + 'SSH/firewall: esiti del passo 7 nei log. Sudo conserva la password; '
                            'nessun accesso dell’amministratore ai gruppi docker/lxd previsto dal pacchetto.\n\n'
                            'Le credenziali personali e della KB restano fuori dal repository; non copiarne i valori nei documenti.',
        'docs/future-improvements.md': stamp + ('Parti escluse dalla configurazione:\n\n' + excluded if exclusions
                                               else 'Nessuna esclusione dichiarata nel piano.')
                                      + '\n\nSincronizzazione KB dal cron: verificare un’esecuzione riuscita; '
                                      'la sola presenza della voce cron non la dimostra.',
    }
    updates = {ops / name: section(ops / name, name, body) for name, body in docs.items()}
    agents = ops / 'AGENTS.md'
    original = agents.read_text()
    placeholder = re.compile(r'Da compilare al termine della verifica iniziale \(`docs/bootstrap/configurazione-server-base.md`, sezione 1\):\n'
                             r'hardware, versione di Ubuntu, ruolo della macchina, accesso da Internet e rete ammessa\. Dettagli:\n'
                             r'`docs/overview.md`\. Utente amministratore: `[^`]+`\.')
    summary = (f'- {code(host)}: {code(data["os"])}; profilo {code(conf.get("PROFILO", ""))}.\n'
               f'- LAN SSH: {code(conf.get("LAN_CIDR", ""))}; amministratore {code(conf.get("ADMIN", ""))}.\n'
               f'- {state}. Stato e prossimo passo: `STATUS.md`; dettagli: `docs/overview.md`.')
    updates[agents] = placeholder.sub(lambda _: summary, original)
    status = ops / 'STATUS.md'
    status_text = section(status, 'Stato della macchina', stamp + base + next_step)
    status_text = status_text.replace(
        'Nessuno registrato. Si aggiungono solo i problemi **riscontrati su questa macchina** (la checklist indica cosa\ncontrollare).',
        'Controlli e attenzioni della configurazione: `docs/bootstrap/esito-configurazione.md`.\n'
        'Parti escluse e prove ancora da fare: `docs/future-improvements.md`.\n'
        'Non dedurre l’assenza di problemi dalla sola conclusione dell’installer.')
    updates[status] = status_text
    return updates


def main():
    ops = Path(sys.argv[1]).resolve()
    conf = values(ops / 'host.conf')
    lines = (ops / 'docs/bootstrap/avanzamento.md').read_text().splitlines()
    states = [x for x in lines if x.startswith('STATO:')]
    if len(states) != 1 or not states[0].startswith('STATO: COMPLETATO'):
        raise ValueError('non consolidare una configurazione incompleta')
    # Deve essere eseguito dall'orchestratore sul sistema reale, non nella sandbox di un modello.
    host = command(['hostname', '-s'])
    if host != conf.get('HOST'):
        raise ValueError('hostname reale diverso da host.conf')
    for name in ('AGENTS.md', 'STATUS.md', 'docs/overview.md', 'docs/system.md', 'docs/network.md',
                 'docs/storage-backup.md', 'docs/security.md', 'docs/future-improvements.md'):
        if (ops / name).is_symlink():
            raise ValueError('documento symlink rifiutato: ' + name)
    os_info = {}
    for line in Path('/etc/os-release').read_text().splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            os_info[k] = v.strip('"')
    data = dict(conf=conf, host=host, state=states[0],
                date=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
                os=os_info.get('PRETTY_NAME', 'non verificato'), kernel=command(['uname', '-r']),
                units=command(['systemctl', 'is-active'] + conf.get('SERVICES', '').split()),
                addresses=command(['ip', '-br', '-4', 'addr']), routes=command(['ip', '-4', 'route']),
                mounts=command(['findmnt', '-rn', '-o', 'TARGET,SOURCE,FSTYPE', '/']))
    updates = render(ops, data)  # Valida tutti i documenti prima di scriverne uno.
    for path, text in updates.items():
        if path.is_symlink():
            raise ValueError('documento symlink rifiutato: ' + str(path))
    for path, text in updates.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.read_text() == text:
            continue
        temp = path.with_name(path.name + '.ops-tmp')
        # Non segue file/symlink temporanei preesistenti.
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(text)
            os.replace(temp, path)
        finally:
            if temp.exists():
                temp.unlink()
    print('Memoria iniziale compilata con dati reali; credenziali non lette.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, IndexError) as error:
        sys.exit('Memoria iniziale non consolidata: ' + str(error))
