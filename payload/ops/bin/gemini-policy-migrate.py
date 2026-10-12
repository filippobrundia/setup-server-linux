#!/usr/bin/env python3
"""Converti le autorizzazioni shell legacy Gemini in policy TOML, senza credenziali."""
import json
import re
import sys
import tomllib
from pathlib import Path


def migrate(settings, base, old=""):
    rules = base.rstrip() + "\n"
    known = {json.dumps(r, sort_keys=True) for r in tomllib.loads(base).get("rule", [])}
    for rule in tomllib.loads(old).get("rule", []):
        signature = json.dumps(rule, sort_keys=True)
        if signature in known:
            continue
        if set(rule) != {"toolName", "commandPrefix", "decision", "priority"} or rule["toolName"] != "run_shell_command" or rule["decision"] != "allow" or rule["priority"] != 100:
            raise ValueError("Policy Gemini gestita modificata: preservata, confrontare prima di migrare")
        rules += "\n[[rule]]\ntoolName = \"run_shell_command\"\ncommandPrefix = " + json.dumps(rule["commandPrefix"]) + "\ndecision = \"allow\"\npriority = 100\n"
        known.add(signature)
    for entry in settings.get("tools", {}).get("allowed", []):
        if not isinstance(entry, str):
            raise ValueError("Autorizzazione Gemini legacy non testuale: migrazione interrotta")
        match = re.fullmatch(r"run_shell_command\((.+)\)", entry)
        if not match:
            raise ValueError("Autorizzazione Gemini personale non convertibile automaticamente: conservarla e migrare prima del setup")
        rules += "\n[[rule]]\ntoolName = \"run_shell_command\"\ncommandPrefix = " + json.dumps(match[1]) + "\ndecision = \"allow\"\npriority = 100\n"
    return rules


if __name__ == "__main__":
    try:
        settings = json.loads(Path(sys.argv[1]).read_text()) if Path(sys.argv[1]).exists() else {}
        old = Path(sys.argv[3]).read_text() if len(sys.argv) > 3 and Path(sys.argv[3]).exists() else ""
        print(migrate(settings, Path(sys.argv[2]).read_text(), old), end="")
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(3)
