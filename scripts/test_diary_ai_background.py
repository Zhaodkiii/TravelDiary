#!/usr/bin/env python3
"""Run background unit tests; --live explicitly enables one paid Book 8 image generation."""
import argparse
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--design-case', type=int, choices=range(14), help='Rerun a single design case, requires --design-flow')
parser.add_argument('--design-cases', help='Comma-separated case indices, e.g. 0,1,2,3,4,5')
parser.add_argument('--design-flow', action='store_true', help='Run six real coordinated layout/style flows (paid calls)')
parser.add_argument('--regression', action='store_true', help='Run all eight retained AI/editor regression suites without paid API calls')
parser.add_argument('--full-flow', action='store_true', help='Run real relayout, text and background benchmark (paid calls)')
parser.add_argument('--live', action='store_true', help='Generate one real Seedream background and save to simulator Photos')
parser.add_argument('--device', default='728BF62D-9E5A-4B7C-ADB4-97534D0A3BBF')
parser.add_argument('--output', type=Path, default=Path('/tmp/TravelDiaryBackgroundTestResults'))
args = parser.parse_args()
if args.design_case is not None and not args.design_flow: parser.error("--design-case requires --design-flow")
if args.design_flow: args.full_flow = True
repo = Path(__file__).resolve().parents[1]
marker = Path('/tmp/traveldiary-fullflow-benchmark-enabled' if args.full_flow else '/tmp/traveldiary-background-live-enabled')
artifacts = Path('/tmp/TravelDiaryBook8Validation/fullflow-benchmark' if args.full_flow else '/tmp/TravelDiaryBook8Validation/background')
args.output.mkdir(parents=True, exist_ok=True)
keep = {'DiaryAIBackgroundTests.swift', 'DiaryAIWorkspaceTests.swift', 'DiaryCanvasAITests.swift',
        'DiaryAIBook8IntegrationTests.swift', 'DiaryAIBook8TextIntegrationTests.swift',
        'DiaryPhotoCompositeTests.swift', 'DiaryPhotoFrameTests.swift', 'DiaryReadingAnimationTests.swift'}
excluded = [p.name for p in (repo / 'TravelDiaryTests').rglob('*.swift') if p.name not in keep]
command = ['xcodebuild', '-project', 'TravelDiary.xcodeproj', '-scheme', 'TravelDiary',
           '-destination', 'platform=iOS Simulator,id=' + args.device, '-parallel-testing-enabled', 'NO',
           'test', 'CODE_SIGNING_ALLOWED=NO', 'EXCLUDED_SOURCE_FILE_NAMES=' + ' '.join(excluded),
           '-only-testing:TravelDiaryTests/DiaryAIBackgroundTests', '-only-testing:TravelDiaryTests/DiaryAIWorkspaceTests',
           'OTHER_LDFLAGS=$(inherited) -framework CoreTelephony -framework SystemConfiguration -lresolv']
if args.design_flow:
    command = [part for part in command if not part.startswith('-only-testing:')]
    command.append('-only-testing:TravelDiaryTests/DiaryAIBackgroundTests')
if args.regression:
    if args.live or args.full_flow:
        parser.error('--regression cannot enable paid calls')
    if list(Path('/tmp').glob('traveldiary-*-enabled')):
        parser.error('A paid integration marker is active; finish that test first')
    command = [part for part in command if not part.startswith('-only-testing:')]
if args.live or args.full_flow:
    if not any(artifacts.parent.glob('已排版项目-*')):
        parser.error('Run scripts/test_diary_ai_book8.py first to create the arranged Book 8 fixture')
    subprocess.run(['xcrun', 'simctl', 'privacy', args.device, 'grant', 'photos-add', 'cn.zhaodk.TravelDiary'], check=True)
    marker.touch()
    if args.design_flow:
        Path("/tmp/traveldiary-design-flow-enabled").write_text(str(args.design_case) if args.design_case is not None else (args.design_cases or "0,1,2,3,4,5"))
else:
    marker.unlink(missing_ok=True)
try:
    with (args.output / 'xcodebuild.log').open('w') as log:
        result = subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
finally:
    marker.unlink(missing_ok=True)
    if args.design_flow: Path("/tmp/traveldiary-design-flow-enabled").unlink(missing_ok=True)
    if (args.live or args.full_flow) and artifacts.exists():
        for item in artifacts.iterdir():
            if item.is_file():
                shutil.copy2(item, args.output / item.name)
            elif item.name.startswith('design-'):
                shutil.copytree(item, args.output / item.name, dirs_exist_ok=True)
raise SystemExit(result.returncode)
