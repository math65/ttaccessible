#!/usr/bin/env python3
"""Audit d'accessibilité statique de tt-Accessible.

Cherche les défauts que la compilation ne voit pas et qu'un utilisateur VoiceOver
découvre à l'usage : une annonce qui perd sa priorité, un contrôle sans nom, un
libellé qui fait répéter le lecteur d'écran, une chaîne jamais traduite.

L'app est en AppKit (les préférences en SwiftUI) et se localise par
`L10n.text` / `L10n.format` sur deux `Localizable.strings` — les règles sont
écrites pour ça, pas pour les patrons SwiftUI/xcstrings de DSM Access.

Usage, depuis la racine du dépôt :
    python3 .agents/skills/accessibility/scripts/audit.py
    python3 .agents/skills/accessibility/scripts/audit.py --only announces,priority
    python3 .agents/skills/accessibility/scripts/audit.py --files App/ttaccessible/AppKit/MoveUsersViewController.swift
    python3 .agents/skills/accessibility/scripts/audit.py --diff        # fichiers modifiés seulement

Sortie : une ligne « fichier:ligne  [règle]  message » par constat, puis un décompte.
Code de sortie 1 s'il reste des constats, 0 sinon.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

SOURCES = Path("App/ttaccessible")
CATALOGS = {
    "en": SOURCES / "en.lproj/Localizable.strings",
    "fr": SOURCES / "fr.lproj/Localizable.strings",
}
# Les dossiers qui dessinent une interface. Les règles de contrôle ne
# s'appliquent qu'à eux ; les annonces, elles, peuvent partir de partout.
UI_PREFIXES = (
    str(SOURCES / "AppKit"),
    str(SOURCES / "SwiftUI"),
    str(SOURCES / "AppDelegate.swift"),
)


@dataclass
class Finding:
    path: str
    line: int
    rule: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}  [{self.rule}]  {self.message}"


def swift_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for base in paths:
        if base.is_file() and base.suffix == ".swift":
            files.append(base)
        elif base.is_dir():
            files.extend(sorted(base.rglob("*.swift")))
    return files


def changed_files() -> list[Path]:
    out = subprocess.run(
        ["git", "diff", "--name-only", "HEAD"],
        capture_output=True, text=True, check=False,
    ).stdout.split()
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        capture_output=True, text=True, check=False,
    ).stdout.split()
    return [Path(p) for p in out + untracked if p.endswith(".swift") and Path(p).exists()]


def is_ui(path: Path) -> bool:
    return str(path).startswith(UI_PREFIXES)


ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')


def load_catalog() -> dict[str, dict[str, str]]:
    """clé -> {langue: valeur}. Vide si les catalogues sont introuvables."""
    out: dict[str, dict[str, str]] = {}
    for lang, path in CATALOGS.items():
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8").split("\n"):
            match = ENTRY.match(line)
            if match:
                out.setdefault(match.group(1), {})[lang] = match.group(2)
    return out


def lines_of(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").split("\n")


def call_window(lines: list[str], i: int, limit: int = 20) -> str:
    """Le texte d'un appel ouvert en ligne `i`, jusqu'à sa parenthèse fermante.

    Un `NSAccessibility.post` s'étale sur cinq à dix lignes : lire une fenêtre
    fixe couperait le `userInfo` en deux et ferait croire à une priorité absente.
    """
    depth = 0
    chunk: list[str] = []
    for line in lines[i:i + limit]:
        chunk.append(line)
        depth += line.count("(") - line.count(")")
        if depth <= 0 and len(chunk) > 0 and "(" in "".join(chunk):
            break
    return "\n".join(chunk)


def used_keys(files: list[Path], pattern: re.Pattern[str]) -> dict[str, list[tuple[str, int]]]:
    """Clés littérales capturées par `pattern` (groupe 1), avec leurs emplacements."""
    found: dict[str, list[tuple[str, int]]] = {}
    for path in files:
        for i, line in enumerate(lines_of(path)):
            for key in pattern.findall(line):
                found.setdefault(key, []).append((str(path), i + 1))
    return found


# --- Règles ----------------------------------------------------------------


LITERAL_ANNOUNCE = re.compile(
    r'(?:\bannounce\w*\(\s*"([^"]*)"'
    r'|(?:NSAccessibility\.NotificationUserInfoKey\.)?\.?announcement:\s*"([^"]*)")'
)


def rule_announces(files: list[Path], _catalog) -> list[Finding]:
    """Une annonce écrite en dur compile, part en production, et n'est jamais traduite.

    Le texte est filtré par `looks_like_prose` : plusieurs appels du projet passent
    une **clé** en paramètre nommé `announcement:` (`PushToTalkKeyRecorder.reject`),
    et les signaler ferait crier au loup sur du code correct.
    """
    findings = []
    for path in files:
        for i, line in enumerate(lines_of(path)):
            if line.lstrip().startswith("//"):
                continue
            match = LITERAL_ANNOUNCE.search(line)
            if match and looks_like_prose(match.group(1) or match.group(2) or ""):
                findings.append(Finding(
                    str(path), i + 1, "announces",
                    "annonce avec un littéral : passer par L10n.text / L10n.format",
                ))
    return findings


def rule_priority(files: list[Path], _catalog) -> list[Finding]:
    """`.priority` attend le NSNumber `rawValue` — l'enum se ponte en boîte opaque.

    AppKit ne relit alors pas le niveau et l'annonce perd sa priorité haute, donc
    VoiceOver l'interrompt. Le bug est resté deux versions dans le Channel Mixer.
    """
    findings = []
    for path in files:
        lines = lines_of(path)
        for i, line in enumerate(lines):
            if "NSAccessibility.post(" not in line:
                continue
            window = call_window(lines, i)
            if "announcementRequested" not in window:
                continue
            if ".priority" not in window:
                findings.append(Finding(
                    str(path), i + 1, "priority",
                    "annonce sans .priority : VoiceOver la met en file et peut l'écraser "
                    "— poser NSAccessibilityPriorityLevel.high.rawValue",
                ))
            # Le `\b` est indispensable : sans lui le moteur recule sur « hig » et
            # le lookahead ne voit plus le `.rawValue` d'un appel pourtant correct.
            elif re.search(r"\.priority:\s*NSAccessibilityPriorityLevel\.\w+\b(?!\s*\.rawValue)", window):
                findings.append(Finding(
                    str(path), i + 1, "priority",
                    "priorité passée en enum : ajouter .rawValue, sinon AppKit ne relit "
                    "pas le niveau et l'annonce redevient interruptible",
                ))
    return findings


LITERAL_A11Y = re.compile(
    r'(?:setAccessibility(?:Label|Help|Title|ValueDescription)\(\s*"([^"]*)"'
    r'|\.accessibility(?:Label|Hint|Value)\(\s*"([^"]*)")'
)


def rule_labels(files: list[Path], _catalog) -> list[Finding]:
    """Un nom d'élément écrit en dur ne passe jamais par les deux catalogues.

    Filtré par `looks_like_prose`, qui écarte les valeurs non traduisibles posées en
    `setAccessibilityValueDescription` — un gabarit d'horloge « 00:00 / 00:00 »,
    un pourcentage interpolé — que rien n'oblige à passer par le catalogue.
    """
    findings = []
    for path in files:
        for i, line in enumerate(lines_of(path)):
            if line.lstrip().startswith("//"):
                continue
            match = LITERAL_A11Y.search(line)
            if match and looks_like_prose(match.group(1) or match.group(2) or ""):
                findings.append(Finding(
                    str(path), i + 1, "labels",
                    "nom d'accessibilité littéral : passer par L10n.text / L10n.format",
                ))
    return findings


L10N_KEY = re.compile(r'L10n\.(?:text|format)\(\s*"([^"]+)"')


def rule_missing_keys(files: list[Path], catalog) -> list[Finding]:
    """Une clé absente d'un catalogue s'affiche telle quelle, en dur, à l'écran."""
    if not catalog:
        return []
    findings = []
    for key, places in used_keys(files, L10N_KEY).items():
        langs = catalog.get(key, {})
        missing = [lang for lang in CATALOGS if lang not in langs]
        if missing:
            path, line = places[0]
            where = "absente des deux catalogues" if len(missing) == len(CATALOGS) \
                else f"absente de {', '.join(missing)}.lproj"
            findings.append(Finding(path, line, "missing-keys", f"{key} : {where}"))
    return findings


# Une clé nommée `…accessibilityLabel` est un nom d'élément : la nomenclature du
# projet est assez régulière pour s'y fier, en plus des appels directs.
LABEL_KEY = re.compile(
    r'(?:setAccessibilityLabel|\.accessibilityLabel)\(\s*L10n\.(?:text|format)\(\s*"([^"]+)"'
)
HELP_KEY = re.compile(
    r'(?:setAccessibilityHelp|\.accessibilityHint)\(\s*L10n\.(?:text|format)\(\s*"([^"]+)"'
)
# « liste » et « tableau » n'y sont volontairement pas : les cinq tableaux du projet
# s'appellent « Liste des utilisateurs bannis », « Liste des profils »… Ce sont des
# groupes nominaux naturels, pas un rôle répété, et les signaler noyait dix constats
# bons dans un audit qui n'en trouve qu'une poignée (mesuré le 2026-08-02).
CONTROL_TYPES = re.compile(
    r"\b(bouton|boutons|button|buttons|case à cocher|checkbox|menu déroulant|"
    r"pop-?up button|champ de texte|text field|curseur|slider|onglet|tab)\b",
    re.IGNORECASE,
)


def rule_label_style(files: list[Path], catalog) -> list[Finding]:
    """Un libellé nomme la chose, sans point final et sans redire le type du contrôle.

    Le trait d'accessibilité dit déjà « bouton » : le répéter fait entendre
    « Couper le micro bouton, bouton ».
    """
    findings = []
    keys = dict(used_keys(files, LABEL_KEY))
    for key, places in used_keys(files, L10N_KEY).items():
        if key.endswith("accessibilityLabel") and key not in keys:
            keys[key] = places
    for key, places in sorted(keys.items()):
        values = catalog.get(key)
        if not values:
            continue
        path, line = places[0]
        for lang, value in sorted(values.items()):
            if not value or "%" in value:
                # Un libellé à trous se juge sur la chaîne assemblée, pas sur le patron.
                continue
            if value.rstrip().endswith("."):
                findings.append(Finding(
                    path, line, "label-style",
                    f'{key} ({lang}) : un libellé ne prend pas de point final — « {value} »',
                ))
            match = CONTROL_TYPES.search(value)
            if match:
                findings.append(Finding(
                    path, line, "label-style",
                    f'{key} ({lang}) nomme le type de contrôle « {match.group(0)} » : '
                    "le trait le dit déjà",
                ))
            first = value.lstrip()[:1]
            if first and first.isalpha() and not first.isupper():
                findings.append(Finding(
                    path, line, "label-style",
                    f'{key} ({lang}) commence en minuscule : « {value} »',
                ))
    return findings


def rule_hints(files: list[Path], catalog) -> list[Finding]:
    """Une aide est une phrase : c'est le point final qui donne son intonation à VoiceOver.

    Elle s'écrit à la troisième personne et décrit le résultat (« Ouvre le salon. »),
    jamais l'action (« Ouvrir »).
    """
    findings = []
    for key, places in used_keys(files, HELP_KEY).items():
        values = catalog.get(key)
        if not values:
            continue
        for lang, value in sorted(values.items()):
            if value and not value.rstrip().endswith((".", "!", "?", "…")):
                path, line = places[0]
                findings.append(Finding(
                    path, line, "hints",
                    f'{key} ({lang}) ne finit pas par un point : « {value} »',
                ))
    return findings


# Le suffixe plutôt que le type exact : sept des douze tableaux du projet sont des
# sous-classes (`BansTableView`, `ChatTableView`, `ConnectedServerOutlineView`…), et
# quatre s'assignent après coup à une propriété `!`, sans `let` ni `var` sur la ligne.
TABLE_DECL = re.compile(
    r"(?:(?:let|var)\s+)?(\w+)\s*(?::\s*\w*(?:Table|Outline)View\b[^=\n]*)?=\s*"
    r"(\w*(?:Table|Outline)View)\s*\("
)


def rule_tables(files: list[Path], _catalog) -> list[Finding]:
    """Un tableau sans nom s'annonce « tableau » et rien d'autre.

    Le nom se cherche **par vue**, pas par fichier : un contrôleur qui nomme sa
    table principale peut très bien en laisser une seconde anonyme. Il se pose
    souvent loin de la déclaration, dans le `configure…`, d'où la recherche sur
    tout le fichier — mais bien de `<variable>.setAccessibilityLabel`.
    """
    findings = []
    for path in files:
        if not is_ui(path):
            continue
        text = path.read_text(encoding="utf-8")
        for i, line in enumerate(text.split("\n")):
            match = TABLE_DECL.search(line)
            if not match:
                continue
            var, kind = match.group(1), match.group(2)
            if re.search(rf"\b{re.escape(var)}\.setAccessibility(?:Label|Element\(false\))", text):
                continue
            findings.append(Finding(
                str(path), i + 1, "tables",
                f"{kind} `{var}` sans setAccessibilityLabel : tableau anonyme",
            ))
    return findings


# Ce qui dispense une icône de porter un nom : la vue qui la contient interdit à
# VoiceOver d'y descendre. `PreferencesWindowController` le fait avec un
# `accessibilityChildren() -> []`, sans quoi la ligne s'annonçait
# « Enregistrement, image de cercle, Enregistrement ».
ICON_EXEMPT = ("accessibilityChildren", "setAccessibilityHidden", "setAccessibilityElement(false)")


SCROLL_DECL = re.compile(
    r"(?:(?:let|var)\s+)?(\w+)\s*(?::\s*\w*ScrollView\b[^=\n]*)?=\s*\w*ScrollView\s*\("
)
NAMED_CONTENT = re.compile(r"(?:Table|Outline)View")


def rule_regions(files: list[Path], _catalog) -> list[Finding]:
    """Une zone de défilement s'annonce, et sans nom elle ne dit rien.

    Mesuré dans l'app le 2026-08-02 : entre la fenêtre et le tableau, AppKit expose
    bien un `AXScrollArea` « zone de défilement » sans description.

    **NE JAMAIS la masquer.** `setAccessibilityElement(false)` sur une `NSScrollView`
    ne la rend pas transparente : ses enfants **remontent d'un cran**, et parmi eux
    l'`AXScrollBar` avec ses cinq boutons (flèches, pages). Essayé le 2026-08-02 sur
    les quatorze zones du projet : la fenêtre principale s'est retrouvée avec trois
    barres de défilement en vrac dans l'ordre de navigation, et la traversée au
    clavier reboucle en fin de fenêtre. Régression signalée à l'oreille en une
    minute, annulée aussitôt. Le seul remède sans effet de bord est de **nommer**
    la zone.

    D'où la règle : on ne signale que les zones dont le contenu est anonyme, là où
    un nom apporte quelque chose. Quand le contenu porte déjà le sien — un tableau,
    un `NSTextView` nommé — la zone reste telle quelle : la nommer ferait entendre
    le nom deux fois, la masquer casserait la hiérarchie, et le statu quo marche.
    """
    findings = []
    for path in files:
        if not is_ui(path):
            continue
        text = path.read_text(encoding="utf-8")
        for i, line in enumerate(text.split("\n")):
            match = SCROLL_DECL.search(line)
            if not match:
                continue
            var = match.group(1)
            if re.search(rf"\b{re.escape(var)}\.setAccessibility(?:Label|Element\(false\))", text):
                continue
            document = re.search(rf"\b{re.escape(var)}\.documentView\s*=\s*([\w.]+)", text)
            kind, content_named = "", False
            if document:
                content = document.group(1)
                name = re.escape(content)
                declared = re.search(rf"{name}\s*(?::\s*(\w+))?[^=\n]*=\s*(\w+)\s*\(", text)
                if declared:
                    kind = declared.group(1) or declared.group(2)
                content_named = bool(re.search(rf"\b{name}\.setAccessibilityLabel\(", text))
            if content_named or (kind and NAMED_CONTENT.search(kind)):
                continue
            findings.append(Finding(
                str(path), i + 1, "regions",
                f"zone de défilement `{var}` sans nom, et {kind or 'son contenu'} n'en porte "
                "pas non plus : lui donner un accessibilityLabel qui dit ce qu'elle tient "
                "— surtout PAS setAccessibilityElement(false), qui ferait remonter la barre "
                "de défilement dans l'ordre de navigation",
            ))
    return findings


def rule_icon_buttons(files: list[Path], _catalog) -> list[Finding]:
    """Une icône sans nom s'annonce « image », ou ne s'annonce pas du tout."""
    findings = []
    for path in files:
        if not is_ui(path):
            continue
        lines = lines_of(path)
        text = "\n".join(lines)
        for i, line in enumerate(lines):
            if not re.search(r"NSImage\(systemSymbolName:|Image\(systemName:", line):
                continue
            window = "\n".join(lines[max(0, i - 6):i + 10])
            if "Button" in window and not (
                "ccessibilityLabel" in window or "title" in window or "Text(" in window
            ):
                findings.append(Finding(
                    str(path), i + 1, "icon-buttons",
                    "bouton apparemment sans texte : vérifier qu'il porte un nom d'accessibilité",
                ))
            elif re.search(r"accessibilityDescription:\s*nil", line) and not any(
                token in text for token in ICON_EXEMPT
            ):
                findings.append(Finding(
                    str(path), i + 1, "icon-buttons",
                    "symbole sans accessibilityDescription : le nommer, ou masquer l'image "
                    "à VoiceOver si elle ne fait que doubler un texte voisin",
                ))
    return findings


def rule_heading_role(files: list[Path], _catalog) -> list[Finding]:
    """`AXHeading` se pose par rawValue : la constante typée est macOS 26+, la cible est 12."""
    findings = []
    for path in files:
        for i, line in enumerate(lines_of(path)):
            if re.search(r"setAccessibilityRole\(\s*(?:\.heading|NSAccessibilityHeadingRole)", line):
                findings.append(Finding(
                    str(path), i + 1, "heading-role",
                    "rôle de titre typé : utiliser NSAccessibility.Role(rawValue: \"AXHeading\") "
                    "— la constante n'existe qu'à partir de macOS 26",
                ))
    return findings


def rule_focus(files: list[Path], _catalog) -> list[Finding]:
    """Déplacer le curseur VoiceOver arrache l'utilisateur à ce qu'il lisait.

    Le projet ne le fait qu'à un endroit, `focusChannelMixer` (⌘5), et c'est une
    décision assumée. Tout nouveau déplacement se justifie ou se retire.
    """
    findings = []
    for path in files:
        lines = lines_of(path)
        for i, line in enumerate(lines):
            if "focusedUIElementChanged" not in line or line.lstrip().startswith("//"):
                continue
            context = "\n".join(lines[max(0, i - 25):i + 3])
            if "focusChannelMixer" in context or "MixerVirtual" in str(path):
                continue
            findings.append(Finding(
                str(path), i + 1, "focus",
                "déplacement du curseur VoiceOver hors du chemin du mixer : "
                "à justifier, il interrompt la lecture en cours",
            ))
    return findings


def looks_like_prose(value: str) -> bool:
    """Distingue un mot destiné à l'utilisateur d'une clé ou d'un nom de symbole.

    Une clé de catalogue (`connectedServer.chat.send`) et un symbole SF
    (`mic.slash.fill`) portent un point sans jamais d'espace ; une phrase affichée
    commence par une capitale ou contient une espace. Le point seul ne suffit pas à
    trancher — « Channel changed. » en a un aussi.

    Les valeurs interpolées sont écartées : le script ne peut pas savoir si
    `"\\(percent)%"` doit rester tel quel ou passer par `L10n.format`.
    """
    stripped = value.strip()
    if not stripped or "\\(" in stripped:
        return False
    if not re.search(r"[A-Za-zÀ-ÿ]", stripped):
        return False
    if " " not in stripped and ("." in stripped or "_" in stripped):
        return False
    return stripped[0].isupper() or " " in stripped


def rule_untranslated(files: list[Path], _catalog) -> list[Finding]:
    """Un mot écrit en dur dans une valeur affichée ne passe jamais par les catalogues.

    Le cas courant est le ternaire `condition ? "Oui" : "Non"` : il compile, il
    s'affiche, et un système en anglais montre quand même le mot français.
    """
    findings = []
    pattern = re.compile(r'\?\s*"([^"]{1,40})"\s*:\s*"([^"]{1,40})"')
    for path in files:
        for i, line in enumerate(lines_of(path)):
            if "L10n." in line or "systemSymbolName" in line or "systemImage" in line:
                continue
            if line.lstrip().startswith("//"):
                continue
            match = pattern.search(line)
            if match and all(looks_like_prose(group) for group in match.groups()):
                findings.append(Finding(
                    str(path), i + 1, "untranslated",
                    f'littéraux affichés « {match.group(1)} » / « {match.group(2)} » : '
                    "passer par L10n.text",
                ))
    return findings


RULES = {
    "announces": rule_announces,
    "priority": rule_priority,
    "labels": rule_labels,
    "label-style": rule_label_style,
    "hints": rule_hints,
    "missing-keys": rule_missing_keys,
    "tables": rule_tables,
    "regions": rule_regions,
    "icon-buttons": rule_icon_buttons,
    "heading-role": rule_heading_role,
    "focus": rule_focus,
    "untranslated": rule_untranslated,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", help="règles à exécuter, séparées par des virgules")
    parser.add_argument("--files", nargs="*", help="fichiers ou dossiers à examiner")
    parser.add_argument("--diff", action="store_true", help="fichiers modifiés seulement")
    parser.add_argument("--list-rules", action="store_true", help="lister les règles")
    args = parser.parse_args()

    if args.list_rules:
        for name, function in RULES.items():
            summary = (function.__doc__ or "").strip().split("\n")[0]
            print(f"{name:14} {summary}")
        return 0

    if args.diff:
        targets = changed_files()
        if not targets:
            print("Aucun fichier Swift modifié.")
            return 0
    elif args.files:
        targets = [Path(p) for p in args.files]
    else:
        targets = [SOURCES]

    files = [p for p in swift_files(targets) if p.exists()]
    if not files:
        print("Aucun fichier Swift à examiner.")
        return 0

    selected = args.only.split(",") if args.only else list(RULES)
    unknown = [name for name in selected if name not in RULES]
    if unknown:
        print(f"Règle inconnue : {', '.join(unknown)}", file=sys.stderr)
        print(f"Disponibles : {', '.join(RULES)}", file=sys.stderr)
        return 2

    catalog = load_catalog()
    findings: list[Finding] = []
    for name in selected:
        findings.extend(RULES[name](files, catalog))

    findings.sort(key=lambda f: (f.rule, f.path, f.line))
    for finding in findings:
        print(finding)

    if not findings:
        print(f"Aucun constat sur {len(files)} fichiers.")
        return 0

    print()
    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.rule] = counts.get(finding.rule, 0) + 1
    detail = ", ".join(f"{rule} {count}" for rule, count in sorted(counts.items()))
    print(f"{len(findings)} constats sur {len(files)} fichiers — {detail}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
