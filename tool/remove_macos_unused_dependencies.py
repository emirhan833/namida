#!/usr/bin/env python3
from pathlib import Path

p = Path('pubspec.yaml')
text = p.read_text()


def remove_dependency_block(src: str, key: str) -> str:
    lines = src.splitlines(keepends=True)
    out = []
    i = 0
    marker = f'  {key}:'
    while i < len(lines):
        if lines[i].rstrip('\r\n') == marker:
            i += 1
            while i < len(lines):
                line = lines[i]
                stripped = line.strip()
                if line.startswith('  ') and not line.startswith('    ') and stripped and not stripped.startswith('#'):
                    break
                i += 1
            continue
        out.append(lines[i])
        i += 1
    return ''.join(out)

# flutter_sharing_intent is private and only backs the mobile share-target path.
# macOS local library indexing / drag-drop / file playback do not need it.
text = remove_dependency_block(text, 'flutter_sharing_intent')
p.write_text(text)
print('Removed mobile-only private sharing intent dependency')
