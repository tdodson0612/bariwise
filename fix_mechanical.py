#!/usr/bin/env python3
import re
import os

with open('/tmp/analyze_full.txt', 'r') as f:
    raw = f.read()

issues = []
for line in raw.splitlines():
    m = re.match(r'.* • (lib/[^:]+):(\d+):\d+ • (.+)', line)
    if m:
        filepath = m.group(1)
        lineno = int(m.group(2))
        lint = m.group(3)
        issues.append((filepath, lineno, lint))

by_file = {}
for filepath, lineno, lint in issues:
    by_file.setdefault(filepath, []).append((lineno, lint))

for filepath, file_issues in by_file.items():
    if not os.path.exists(filepath):
        continue
    with open(filepath, 'r') as f:
        content_lines = f.readlines()

    # Process descending by line number
    file_issues_sorted = sorted(file_issues, key=lambda x: x[0], reverse=True)
    modified = False
    for lineno, lint in file_issues_sorted:
        idx = lineno - 1
        if idx < 0 or idx >= len(content_lines):
            continue

        line = content_lines[idx]

        if lint == 'empty_catches':
            if 'catch' in line and '{' in line:
                indent = len(line) - len(line.lstrip())
                content_lines[idx] = ' ' * indent + '// ignore: empty_catches\n' + line
                modified = True

        elif lint == 'unused_catch_stack':
            if 'catch' in line and 'stackTrace' in line:
                new_line = re.sub(r',\s*stackTrace', '', line)
                if new_line != line:
                    content_lines[idx] = new_line
                    modified = True

        elif lint == 'unused_field':
            indent = len(line) - len(line.lstrip())
            content_lines[idx] = ' ' * indent + '// ignore: unused_field\n' + line
            modified = True

        # Skip other lints per user request
        # avoid_print: already handled
        # deprecated_member_use: manual
        # use_build_context_synchronously: manual
        # constant_identifier_names: manual
        # library_private_types_in_public_api: manual
        # unused_local_variable: manual
        # unnecessary_import: manual

    if modified:
        with open(filepath, 'w') as f:
            f.writelines(content_lines)
        print(f'Updated: {filepath}')

print('Mechanical fixes applied')
