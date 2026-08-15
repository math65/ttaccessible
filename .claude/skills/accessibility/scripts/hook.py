#!/usr/bin/env python3
"""Hook PostToolUse : audite la vue qui vient d'être écrite.

Claude Code envoie sur l'entrée standard le JSON de l'appel d'outil. On n'audite
que les fichiers d'interface (`AppKit/`, `SwiftUI/`, `AppDelegate.swift`), et
seulement celui qui vient de changer : auditer tout le diff redirait les mêmes
constats à chaque édition d'une série.

Le hook ne bloque jamais. Il rend les constats au modèle, qui décide.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
AUDIT = ROOT / ".agents/skills/accessibility/scripts/audit.py"
WATCHED = (
    "App/ttaccessible/AppKit/",
    "App/ttaccessible/SwiftUI/",
    "App/ttaccessible/AppDelegate.swift",
)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    tool_input = payload.get("tool_input") or {}
    tool_response = payload.get("tool_response") or {}
    raw_path = tool_response.get("filePath") or tool_input.get("file_path")
    if not raw_path:
        return 0

    path = Path(raw_path)
    try:
        relative = path.resolve().relative_to(ROOT)
    except ValueError:
        return 0
    if path.suffix != ".swift" or not str(relative).startswith(WATCHED):
        return 0

    result = subprocess.run(
        [sys.executable, str(AUDIT), "--files", str(relative)],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    findings = result.stdout.strip()
    # The script exits 1 when it has findings, 0 when clean. Anything else is the
    # script itself failing, and a broken audit must not be read as a clean view.
    if result.returncode == 0 or not findings:
        return 0
    if result.returncode != 1:
        print(json.dumps({
            "systemMessage": f"L'audit d'accessibilité a échoué : {result.stderr.strip()[:200]}"
        }))
        return 0

    print(json.dumps({
        "suppressOutput": True,
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": (
                f"Audit d'accessibilité de {relative} :\n{findings}\n"
                "Corriger avant de dire l'écran fini. Un constat `focus` ou "
                "`icon-buttons` peut être légitime : il demande une justification, "
                "pas forcément un changement. Toute chaîne ajoutée part dans "
                "en.lproj ET fr.lproj (skill add-localization)."
            ),
        },
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
