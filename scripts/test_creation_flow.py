#!/usr/bin/env python3
"""Native creation handoff and retained AI regressions; no paid model requests."""
import subprocess
from pathlib import Path
import argparse
p = argparse.ArgumentParser()
p.add_argument('--device', default='177E75E9-6752-4FFD-B754-666EB5FB7E16')
a = p.parse_args()
repo = Path(__file__).resolve().parents[1]
if list(Path('/tmp').glob('traveldiary-*-enabled')) or Path('/tmp/creation-live-enabled').exists():
    raise SystemExit('Paid integration marker active; finish that run first.')
keep = {'CreationFlowTests.swift', 'TravelCaptureSpreadTests.swift', 'DiaryAIWorkspaceTests.swift', 'DiaryCanvasAITests.swift', 'DiaryAIBackgroundTests.swift'}
excluded = [x.name for x in (repo/'TravelDiaryTests').rglob('*.swift') if x.name not in keep]
cmd = ['xcodebuild', '-project', 'TravelDiary.xcodeproj', '-scheme', 'TravelDiary', '-destination', 'platform=iOS Simulator,id='+a.device, 'test', '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO', 'EXCLUDED_SOURCE_FILE_NAMES='+' '.join(excluded), 'OTHER_LDFLAGS=$(inherited) -framework CoreTelephony -framework SystemConfiguration -lresolv']
with open('/tmp/traveldiary-creation-tests.log', 'w') as log:
    result = subprocess.run(cmd, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
print('Log: /tmp/traveldiary-creation-tests.log')
raise SystemExit(result.returncode)
