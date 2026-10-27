#!/usr/bin/env python3
"""Run print/payment regression tests independently of legacy XCTest actor errors."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--destination', default='platform=iOS Simulator,name=iPhone 17 Pro')
parser.add_argument('--derived-data', default=str(Path(tempfile.gettempdir()) / 'TravelDiaryPrintBuild'))
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
# -only-testing limits execution, but Xcode still compiles every test source.
# The older XCTest classes do not compile under this target's default MainActor setting.
keep = {'PrintPaymentCoordinatorTests.swift', 'PrintProbeLinkTests.swift', 'DiaryBookPrintExportTests.swift', 'RegionTests.swift'}
excluded = sorted({p.name for p in (root / 'TravelDiaryTests').rglob('*.swift') if p.name not in keep})
command = [
    'xcodebuild', '-project', 'TravelDiary.xcodeproj', '-scheme', 'TravelDiary',
    '-configuration', 'Debug', '-destination', args.destination, '-derivedDataPath', args.derived_data,
    'CODE_SIGNING_ALLOWED=NO', 'EXCLUDED_SOURCE_FILE_NAMES=' + ' '.join(excluded),
    # Alipay's static framework is also autolinked into the hosted test bundle.
    'OTHER_LDFLAGS=$(inherited) -framework CoreTelephony -framework SystemConfiguration',
    '-only-testing:TravelDiaryTests/RegionTests',
    '-only-testing:TravelDiaryTests/PrintPaymentCoordinatorTests',
    '-only-testing:TravelDiaryTests/PrintWorkflowContractTests',
    '-only-testing:TravelDiaryTests/PrintProbeLinkTests',
    '-only-testing:TravelDiaryTests/PrintMultipartHTTPTests',
    '-only-testing:TravelDiaryTests/DiaryBookPrintExportTests', 'test',
]
raise SystemExit(subprocess.call(command, cwd=root))
