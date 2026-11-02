#!/usr/bin/env python3
"""Summarize recorded provider usage without reading SSE deltas as extra calls."""
import json, argparse, collections
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args()
records=[json.loads(l) for l in (a.directory/'events.jsonl').read_text().splitlines() if l.strip()]
summary=collections.defaultdict(lambda:dict(calls=0,input=0,output=0,cached=0,reasoning=0))
requests=0;failures=[];responses=[]
for d in records:
 v=d.get('payload',{})
 if d['kind']=='request-body':requests+=1
 if d['kind']=='event' and v.get('kind')=='error':failures.append({'sequence':d['sequence'],'title':v.get('title'),'detail':v.get('detail')})
 if d['kind']!='response-body':continue
 names=[x['name'] for x in v.get('output',[]) if x.get('type')=='function_call']
 image='seedream' in v.get('model','')
 category='image_generation' if image else '+'.join(sorted(set(names))) or 'no_tool'
 u=v.get('usage',{});row=summary[category];row['calls']+=1
 for out,key in [('input','input_tokens'),('output','output_tokens')]:row[out]+=u.get(key,0)
 row['cached']+=u.get('input_tokens_details',{}).get('cached_tokens',0)
 row['reasoning']+=u.get('output_tokens_details',{}).get('reasoning_tokens',0)
 responses.append({'sequence':d['sequence'],'category':category,'usage':u})
print(json.dumps({'requests':requests,'first':records[0]['time'],'last':records[-1]['time'],'groups':dict(summary),'failures':failures,'responses':responses},ensure_ascii=False,indent=2))
