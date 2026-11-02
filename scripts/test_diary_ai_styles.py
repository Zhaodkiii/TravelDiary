#!/usr/bin/env python3
"""Opt-in paid, native iOS comparison of Skill prompts and app background presets.

No credential is read by this script. Requests use the app's native provider/config.
Original outputs keep each Skill's own poster/container logic; app outputs are pure
background adaptations. These are not pixel-identical output tasks.
"""
import argparse
import fcntl
import json
import shutil
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true', help='Explicitly enable paid API requests')
    parser.add_argument('--round', choices=['reference', 'optimized', 'verify'], default='optimized')
    parser.add_argument('--source', type=Path, required=True, help='One actual source photograph')
    parser.add_argument('--styles', nargs='+', choices=['paper', 'print', 'doodle', 'pastel', 'relic', 'watercolor'], help='Explicit subset; default all available presets')
    parser.add_argument('--device', default='728BF62D-9E5A-4B7C-ADB4-97534D0A3BBF')
    parser.add_argument('--output', type=Path, default=Path('/tmp/DiaryStyleStudyExport'))
    args = parser.parse_args()
    print({'reference': 'Up to 12 image + 6 design + 6 review requests',
           'optimized': 'Up to 6 image + 6 design + 6 review requests',
           'verify': '6 review requests only; requires existing optimized files'}[args.round])
    print('Existing images are reused; failed calls are not automatically retried. A prompt repair can add one request per style.')
    if not args.run:
        print('Dry run. Add --run to execute paid requests.')
        return 0
    repo = Path(__file__).resolve().parents[1]
    work = Path('/tmp/DiaryStyleStudy')
    marker = Path('/tmp/traveldiary-style-study-enabled')
    if not args.source.is_file():
        parser.error('Source image does not exist')
    args.output = args.output.expanduser().resolve()
    if args.output == work or work in args.output.parents:
        parser.error('Output must be outside /tmp/DiaryStyleStudy')
    with Path('/tmp/traveldiary-style-study.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if any(Path('/tmp/' + n).exists() for n in ['traveldiary-fullflow-benchmark-enabled', 'traveldiary-background-live-enabled']):
            parser.error('Disable other paid test markers before the style study')
        work.mkdir(parents=True, exist_ok=True)
        source_bytes = args.source.read_bytes()
        fixture = work / 'source.image'
        if fixture.exists() and fixture.read_bytes() != source_bytes:
            parser.error('Workspace contains a different source. Archive and remove /tmp/DiaryStyleStudy before changing the source; cached outputs must not be mixed.')
        fixture.write_bytes(source_bytes)
        for name in ['skill-prompts.json', 'provenance.json']:
            shutil.copy2(repo / 'scripts/fixtures/diary_background_styles' / name, work / name)
        keep = {'DiaryAIBackgroundTests.swift', 'DiaryAIWorkspaceTests.swift', 'DiaryCanvasAITests.swift',
                'DiaryAIBook8IntegrationTests.swift', 'DiaryAIBook8TextIntegrationTests.swift',
                'DiaryPhotoCompositeTests.swift', 'DiaryPhotoFrameTests.swift', 'DiaryReadingAnimationTests.swift'}
        excluded = [p.name for p in (repo / 'TravelDiaryTests').rglob('*.swift') if p.name not in keep]
        command = ['xcodebuild', '-project', 'TravelDiary.xcodeproj', '-scheme', 'TravelDiary',
                   '-destination', 'platform=iOS Simulator,id=' + args.device, '-parallel-testing-enabled', 'NO',
                   'test', 'CODE_SIGNING_ALLOWED=NO', 'EXCLUDED_SOURCE_FILE_NAMES=' + ' '.join(excluded),
                   '-only-testing:TravelDiaryTests/DiaryAIBackgroundTests',
                   'OTHER_LDFLAGS=$(inherited) -framework CoreTelephony -framework SystemConfiguration -lresolv']
        filter_file = work / 'style-filter.json'
        if args.styles:
            filter_file.write_text(json.dumps(args.styles))
        else:
            filter_file.unlink(missing_ok=True)
        marker.write_text('baseline' if args.round == 'reference' else args.round)
        try:
            with (work / (args.round + '-xcodebuild.log')).open('w') as log:
                result = subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
        finally:
            marker.unlink(missing_ok=True)
            filter_file.unlink(missing_ok=True)
            shutil.copytree(work, args.output, dirs_exist_ok=True)
        print('Results:', args.output)
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
