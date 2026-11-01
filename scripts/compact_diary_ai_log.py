#!/usr/bin/env python3
"""Copy a legacy AI diagnostic package into compact JSONL without changing the source."""
import argparse
import json
import shutil
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('destination', type=Path)
args = parser.parse_args()
if args.destination.exists():
    parser.error('Destination must not exist')
shutil.copytree(args.source, args.destination)
files = sorted(f for f in args.destination.glob('*.json') if f.name[:6].isdigit())
stream = args.destination / 'events.jsonl'
newer = stream.read_bytes() if stream.exists() else b''
with stream.open('wb') as output:
    for file in files:
        record = json.loads(file.read_text())
        output.write(json.dumps(record, ensure_ascii=False, separators=(',', ':')).encode() + b'\n')
    output.write(newer)
for file in files:
    file.unlink()
print('Preserved', len(files), 'legacy records in', stream)
print('Files:', sum(f.is_file() for f in args.destination.rglob('*')))
