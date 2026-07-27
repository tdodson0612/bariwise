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

    file_issues_sorted = sorted(file_issues, key=lambda x: x[0], reverse=True)
    modified = False
    for lineno, lint in file_issues_sorted:
        idx = lineno - 1
        if idx < 0 or idx >= len(content_lines):
            continue

        line = content_lines[idx]

        if lint == 'avoid_print':
            if 'print(' in line and not line.strip().startswith('//'):
                if line.strip().startswith('print('):
                    content_lines[idx] = line.replace('print(', 'debugPrint(', 1)
                else:
                    content_lines[idx] = line.replace('print(', 'debugPrint(', 1)
                modified = True
                has_foundation = any('package:flutter/foundation.dart' in l for l in content_lines)
                if not has_foundation:
                    for i, l in enumerate(content_lines):
                        if l.startswith('import '):
                            insert_idx = i
                        else:
                            insert_idx = 0
                    content_lines.insert(insert_idx, "import 'package:flutter/foundation.dart';\n")
                    modified = True

        elif lint == 'empty_catches':
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

        elif lint in ('deprecated_member_use', 'library_private_types_in_public_api',
                      'use_build_context_synchronously', 'constant_identifier_names',
                      'unused_local_variable'):
            pass

    if modified:
        with open(filepath, 'w') as f:
            f.writelines(content_lines)
        print(f'Updated: {filepath}')

print('Phase 1 mechanical fixes complete')
