#!/usr/bin/env python3
"""Explicit real-model scene tests through the new creation handoff; preserves outputs."""
import argparse, json, subprocess, shutil
from pathlib import Path
from PIL import Image, ImageOps
p=argparse.ArgumentParser();p.add_argument('--run',action='store_true');p.add_argument('--cases',default='0,1,2,3,4,5');p.add_argument('--device',default='177E75E9-6752-4FFD-B754-666EB5FB7E16');a=p.parse_args()
repo=Path(__file__).resolve().parents[1]
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',a.device,'cn.zhaodk.TravelDiary','data'],text=True).strip())
manifest=json.loads((repo/'scripts/fixtures/archive5/manifest.json').read_text())
for case in manifest:
 for kind in ['photos','stickers']:
  dest=container/'Documents/DesignFixtures'/case['name']/kind;dest.mkdir(parents=True,exist_ok=True)
  for i,name in enumerate(case[kind]):
   im=ImageOps.exif_transpose(Image.open(name));im.thumbnail((1800,1800));im.save(dest/f'{i:02}.png')
if not a.run:raise SystemExit('Prepared only; --run enables paid model calls.')
marker=Path('/tmp/creation-live-enabled')
keep={'CreationFlowTests.swift'}
excluded=[x.name for x in (repo/'TravelDiaryTests').rglob('*.swift') if x.name not in keep]
out=Path('/tmp/creation-scene-matrix');out.mkdir(exist_ok=True)
try:
 for index in map(int,a.cases.split(',')):
  assert 0<=index<6
  marker.write_text(str(index))
  cmd=['xcodebuild','-project','TravelDiary.xcodeproj','-scheme','TravelDiary','-destination','platform=iOS Simulator,id='+a.device,'test','-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','EXCLUDED_SOURCE_FILE_NAMES='+' '.join(excluded),'OTHER_LDFLAGS=$(inherited) -framework CoreTelephony -framework SystemConfiguration -lresolv']
  with (out/f'case-{index}.log').open('w') as log:r=subprocess.run(cmd,cwd=repo,stdout=log,stderr=subprocess.STDOUT)
  current=Path(subprocess.check_output(['xcrun','simctl','get_app_container',a.device,'cn.zhaodk.TravelDiary','data'],text=True).strip())
  if (current/'Documents/CreationSceneResults').exists():shutil.copytree(current/'Documents/CreationSceneResults',out/'results',dirs_exist_ok=True)
  print(index,r.returncode,flush=True)
finally:
 marker.unlink(missing_ok=True)
 if (container/'Documents/CreationSceneResults').exists():shutil.copytree(container/'Documents/CreationSceneResults',out/'results',dirs_exist_ok=True)
