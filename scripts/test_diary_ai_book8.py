#!/usr/bin/env python3
"""Explicit paid real-model integration test using the user's local book ZIP."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', type=Path, default=Path('/Users/dream/Downloads/旅行随记 8.zip'))
parser.add_argument('--output', type=Path, default=Path('/Users/dream/Downloads/旅行随记8-AI验证'))
parser.add_argument('--with-text', action='store_true', help='After layout, run a real editable-text generation test')
parser.add_argument('--device', default='728BF62D-9E5A-4B7C-ADB4-97534D0A3BBF')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
fixture = Path('/tmp/traveldiary-book8-fixture.zip')
marker = Path('/tmp/traveldiary-book8-integration-enabled')
artifacts = Path('/tmp/TravelDiaryBook8Validation')
if not args.input.is_file():
    parser.error('Input ZIP does not exist')
args.output.mkdir(parents=True, exist_ok=True)
shutil.copy2(args.input, fixture)
marker.touch()
text_marker = Path('/tmp/traveldiary-book8-text-enabled')
text_marker.unlink(missing_ok=True)
keep = {'DiaryAIBackgroundTests.swift', 'DiaryCanvasAITests.swift', 'DiaryAIWorkspaceTests.swift', 'DiaryAIBook8IntegrationTests.swift', 'DiaryAIBook8TextIntegrationTests.swift',
        'DiaryPhotoCompositeTests.swift', 'DiaryPhotoFrameTests.swift', 'DiaryReadingAnimationTests.swift'}
excluded = [p.name for p in (repo / 'TravelDiaryTests').rglob('*.swift') if p.name not in keep]
command = ['xcodebuild', '-project', 'TravelDiary.xcodeproj', '-scheme', 'TravelDiary',
           '-destination', 'platform=iOS Simulator,id=' + args.device, '-parallel-testing-enabled', 'NO',
           'test', 'CODE_SIGNING_ALLOWED=NO', 'EXCLUDED_SOURCE_FILE_NAMES=' + ' '.join(excluded),
           'OTHER_LDFLAGS=$(inherited) -framework CoreTelephony -framework SystemConfiguration -lresolv']
try:
    with (args.output / 'xcodebuild.log').open('w') as log:
        result = subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode == 0 and args.with_text:
            marker.unlink(missing_ok=True)
            text_marker.touch()
            text_command = command + ['-only-testing:TravelDiaryTests/DiaryAIBook8TextIntegrationTests']
            result = subprocess.run(text_command, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
finally:
    marker.unlink(missing_ok=True)
    text_marker.unlink(missing_ok=True)
    if artifacts.exists():
        for item in artifacts.iterdir():
            if 'sandbox-' in item.name:
                continue
            if item.is_dir():
                shutil.copytree(item, args.output / item.name, dirs_exist_ok=True)
            else:
                shutil.copy2(item, args.output / item.name)
raise SystemExit(result.returncode)
