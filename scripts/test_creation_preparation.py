#!/usr/bin/env python3
"""Run draft material preparation and submission regressions on an iOS simulator."""
import argparse
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', default='177E75E9-6752-4FFD-B754-666EB5FB7E16')
parser.add_argument('--log', type=Path, default=Path('/tmp/creation-preparation-verification.log'))
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
keep = {'DiaryCreationFlowTests.swift', 'DiaryAIWorkspaceTests.swift', 'DiaryCanvasAITests.swift',
        'DiaryAIBackgroundTests.swift', 'DiaryAIBook8IntegrationTests.swift', 'DiaryAIBook8TextIntegrationTests.swift'}
excluded = [p.name for p in (repo / 'TravelDiaryTests').rglob('*.swift') if p.name not in keep]
command = ['xcodebuild', '-project', 'TravelDiary.xcodeproj', '-scheme', 'TravelDiary',
           '-destination', 'platform=iOS Simulator,id=' + args.device, 'test',
           '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO',
           'EXCLUDED_SOURCE_FILE_NAMES=' + ' '.join(excluded),
           '-only-testing:TravelDiaryTests/DiaryCreationDraftTests',
           'OTHER_LDFLAGS=$(inherited) -framework CoreTelephony -framework SystemConfiguration -lresolv']
with args.log.open('w') as log:
    result = subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
print('Log:', args.log)
raise SystemExit(result.returncode)
