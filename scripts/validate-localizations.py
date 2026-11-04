#!/usr/bin/env python3
"""Validate shipped macOS catalogues without third-party dependencies."""
import collections
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
app = root / 'App' / 'ttaccessible'
catalogues = {}
for path in sorted(app.glob('*.lproj/Localizable.strings')):
    catalogues[path.parent.name] = json.loads(subprocess.check_output(
        ['plutil', '-convert', 'json', '-o', '-', str(path)]))
reference = catalogues['en.lproj']
# Space flags are deliberately excluded: plain UI text includes "50% on reconnect",
# which is not passed to String(format:) and must not be mistaken for "% o".
pattern = re.compile(r'%(?:(\d+)\$)?([-+#0]*\d*(?:\.\d+)?(?:hh|ll|[hlqzjtL])?[@diuoxXfFeEgGcCsSp])|%%')
def placeholders(value):
    tokens = []
    position = 0
    for match in pattern.finditer(value):
        if match.group(0) == '%%':
            tokens.append(('literal', '%'))
        else:
            position += 1
            tokens.append((int(match.group(1)) if match.group(1) else position, match.group(2)))
    return collections.Counter(tokens)
errors = []
for language, catalogue in catalogues.items():
    if set(catalogue) != set(reference):
        errors.append(f'{language}: key mismatch: {set(catalogue) ^ set(reference)}')
    # Existing translations are not rewritten as part of the Chinese contribution.
    if language == 'zh-Hans.lproj':
        for key in reference.keys() & catalogue.keys():
            if placeholders(reference[key]) != placeholders(catalogue[key]):
                errors.append(f'{language}: incompatible format placeholders: {key}')
            if reference[key] and not catalogue[key]:
                errors.append(f'{language}: empty translation: {key}')
if errors:
    sys.exit('\n'.join(errors))
print(f'PASS: {len(catalogues)} catalogues, {len(reference)} matching keys; Chinese placeholders and nonempty values valid.')
