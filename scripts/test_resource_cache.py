#!/usr/bin/env python3
"""Run cache/storage/template regressions without unrelated legacy XCTest compilation failures.

The exclusions are command-line-only; project settings and test sources are unchanged.
"""
import argparse
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', default='platform=iOS Simulator,name=iPhone 17 Pro')
    parser.add_argument('--include-import-flow', action='store_true', help='Also run import regressions; the working tree currently has an unrelated photo-filter expectation failure.')
    parser.add_argument('--derived-data', default='/tmp/TravelDiaryCacheBuild')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    selected = {'ResourceCacheTests.swift', 'StorageManagementTests.swift',
                'DiaryPresetTemplateLibraryTests.swift', 'DiaryPresetImportFlowTests.swift'}
    suites = ['ResourceCacheTests', 'StorageManagementTests', 'DiaryPresetTemplateLibraryTests']
    if args.include_import_flow:
        suites.append('DiaryPresetImportFlowTests')
    excluded = sorted(p.name for p in (root / 'TravelDiaryTests').rglob('*.swift') if p.name not in selected)
    command = ['xcodebuild', '-project', 'TravelDiary.xcodeproj', '-scheme', 'TravelDiary',
               '-configuration', 'Debug', '-sdk', 'iphonesimulator', '-destination', args.destination,
               '-derivedDataPath', args.derived_data, 'EXCLUDED_SOURCE_FILE_NAMES=' + ' '.join(excluded),
               # The existing test target misses Alipay's transitive system frameworks.
               'OTHER_LDFLAGS=$(inherited) -framework CoreTelephony -framework SystemConfiguration -lresolv',
               *['-only-testing:TravelDiaryTests/' + suite for suite in suites],
               'test', 'CODE_SIGNING_ALLOWED=NO']
    return subprocess.run(command, cwd=root).returncode


if __name__ == '__main__':
    raise SystemExit(main())
