#!/usr/bin/env python3
import re
import os

fix_libs = True  # Set False if you want to skip debugPrint conversion

# Files to skip if they don't need debugPrint (empty catches etc)
files_with_commented_prints = set()
for root, dirs, files in os.walk('lib'):
    for fname in files:
        if fname.endswith('.dart'):
            path = os.path.join(root, fname)
            with open(path, 'r') as f:
                content = f.read()
            if re.search(r'^\s*//\s*print\(', content, re.MULTILINE):
                files_with_commented_prints.add(path)

for filepath in sorted(files_with_commented_prints):
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    
    # Uncomment and convert print -> debugPrint
    # Match // at start of line (after optional whitespace) followed by optional spaces then print(
    # We want to preserve indentation after the comment marker.
    # Pattern: ^(\s*)//\s+(print\() 
    # Replace with: \1\2 but with print -> debugPrint
    def replace_print(m):
        indent = m.group(1)
        print_call = m.group(2)
        debug_call = print_call.replace('print(', 'debugPrint(', 1)
        return indent + debug_call
    
    new_content = re.sub(r'^(\s*)//\s+(print\()', replace_print, content, flags=re.MULTILINE)
    
    if new_content != content:
        content = new_content
    
    # Ensure foundation import exists if we added debugPrint
    if fix_libs and 'debugPrint(' in content:
        if 'package:flutter/foundation.dart' not in content:
            # Find the first import line to insert after, or prepend to file
            lines = content.split('\n')
            last_import_idx = -1
            for i, line in enumerate(lines):
                if line.startswith('import '):
                    last_import_idx = i
            
            if last_import_idx >= 0:
                lines.insert(last_import_idx + 1, "import 'package:flutter/foundation.dart';")
            else:
                # Prepend after any doc blocks
                for i, line in enumerate(lines):
                    if line.startswith('//') or line.strip() == '':
                        continue
                    lines.insert(i, "import 'package:flutter/foundation.dart';\n")
                    break
            content = '\n'.join(lines)
    
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        print(f'Fixed prints: {filepath}')

print('Done')
