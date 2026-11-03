#!/usr/bin/env python3
"""Prepare curated Archive 5 fixtures; --run enables six paid native production flows."""
import argparse,json,subprocess,shutil,re,html
from pathlib import Path
from PIL import Image
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--run',action='store_true')
p.add_argument('--cases',default='8,9,10,11,12,13')
p.add_argument('--output',type=Path,default=Path('/tmp/archive5-production-matrix'))
a=p.parse_args(); repo=Path(__file__).resolve().parents[1]
a.output.mkdir(parents=True,exist_ok=True)
manifest=json.loads((repo/'scripts/fixtures/archive5/manifest.json').read_text())
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container','728BF62D-9E5A-4B7C-ADB4-97534D0A3BBF','cn.zhaodk.TravelDiary','data'],text=True).strip())
for case in manifest:
    dest=container/'Documents/DesignFixtures'/case['name']
    if dest.exists(): shutil.rmtree(dest)
    for kind in ['photos','stickers']:
        (dest/kind).mkdir(parents=True)
        for i,name in enumerate(case[kind]):
            im=Image.open(name)
            if kind=='photos':
                im=im.convert('RGB');im.thumbnail((1800,1800));im.save(dest/kind/f'{i:02}.jpg',quality=90)
            else: im.save(dest/kind/f'{i:02}.png')
shutil.copy2(repo/'scripts/fixtures/archive5/manifest.json',a.output/'manifest.json')
if not a.run:
    print('Fixtures ready; no paid calls. Add --run for native production matrix.');raise SystemExit()
results=[]
for index in map(int,a.cases.split(',')):
    if index not in range(8,14):p.error('cases must be 8..13')
    dest=a.output/f'case-{index}'
    rc=subprocess.run(['python3',str(repo/'scripts/test_diary_ai_background.py'),'--design-flow','--design-case',str(index),'--output',str(dest)],cwd=repo).returncode
    log=(dest/'xcodebuild.log').read_text(errors='replace')
    samples=re.findall(r'BENCHMARK mode=\w+ seconds=([\d.]+) result=(.*)',log)
    results.append(dict(case=index,dataset=manifest[index-8]['name'],exit_code=rc,runs=samples))
    (a.output/'summary.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
print(json.dumps(results,ensure_ascii=False))
raise SystemExit(any(r['exit_code'] for r in results))
