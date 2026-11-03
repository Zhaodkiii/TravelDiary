#!/usr/bin/env python3
"""Summarize native AI run evidence without exposing request payloads or credentials."""
import argparse,json,re,zipfile,html,shutil
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--root',type=Path,default=Path('/tmp/TravelDiaryBook8Validation/fullflow-benchmark'));a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
rows=[];cards=[];latest={}
for directory in sorted(a.root.glob('design-archive-*')):
    events=json.loads((directory/'events.json').read_text()) if (directory/'events.json').exists() else []
    metrics=json.loads((directory/'metrics.json').read_text()) if (directory/'metrics.json').exists() else {}
    row=dict(name=directory.name,modified=directory.stat().st_mtime,**metrics)
    usage=[re.search(r'输入 (\d+) tokens · 输出 (\d+) tokens',e.get('detail','')) for e in events if e.get('kind')=='response']
    row['workspace_requests']=sum(e.get('kind')=='request' for e in events)
    row['workspace_input_tokens']=sum(int(m[1]) for m in usage if m)
    row['workspace_output_tokens']=sum(int(m[2]) for m in usage if m)
    row['tool_failures']=sum('未执行' in e.get('title','') for e in events)
    row['visual_repair_batches']=sum(e.get('kind')=='revision' and e.get('title')=='已安排局部视觉修复' for e in events)
    native=directory/'production-log.zip'
    if native.exists():
        with zipfile.ZipFile(native) as z:
            name=next((n for n in z.namelist() if n.endswith('events.jsonl')),None)
            entries=[json.loads(x) for x in z.read(name).splitlines()] if name else []
        bodies=[x['payload'] for x in entries if x['kind']=='request-body' and isinstance(x['payload'],dict)]
        row['all_api_requests']=len(bodies)
        row['models']=sorted({str(x.get('model')) for x in bodies if x.get('model')})
        responses=[x['payload'] for x in entries if x['kind']=='response-body' and isinstance(x['payload'],dict) and isinstance(x['payload'].get('usage'),dict)]
        text_responses=[x for x in responses if 'generated_images' not in x['usage']]
        row['reported_api_input_tokens']=sum(x['usage'].get('input_tokens',0) for x in text_responses)
        row['reported_api_output_tokens']=sum(x['usage'].get('output_tokens',0) for x in text_responses)
        row['image_generation_usage']=[x['usage'] for x in responses if 'generated_images' in x['usage']]
        row['request_prompt_chars']=sum(len(json.dumps(x,ensure_ascii=False)) for x in bodies)
        row['response_breakdown']=[dict(tools=[c.get('name') for c in x.get('output',[]) if c.get('type')=='function_call'],usage=x['usage']) for x in responses]
    dest=a.output/directory.name;dest.mkdir(exist_ok=True)
    for name in ['events.json','metrics.json','background.png','composed.jpg','production-log.zip']:
        if (directory/name).exists():shutil.copy2(directory/name,dest/name)
    if metrics and not metrics.get('error') and (directory/'composed.jpg').exists():
        key=metrics.get('dataset',directory.name)
        if key not in latest or row['modified']>latest[key]['modified']: latest[key]=row
    cards.append('<article><h2>'+html.escape(directory.name)+'</h2><pre>'+html.escape(json.dumps(row,ensure_ascii=False,indent=2))+'</pre><img style="max-width:1200px;width:100%" src="'+directory.name+'/composed.jpg"></article>');rows.append(row)
(a.output/'metrics.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
main=[]
for key,row in sorted(latest.items()):
    main.append('<h2>'+html.escape(key)+'</h2><p>'+str(round(row.get('elapsed',0),1))+'秒 · 总API请求 '+str(row.get('all_api_requests','未知'))+' · 文本API输入tokens '+str(row.get('reported_api_input_tokens','未知'))+'</p><img style="width:100%;max-width:1300px" src="'+row['name']+'/composed.jpg">')
(a.output/'index.html').write_text('<meta charset="utf-8"><h1>归档5：最新流程通过样本</h1><p>流程通过不等同于全部视觉标准达标，人工评审与验证边界见验收说明。下方保留全部失败历史。文本API usage与生图usage分列，未知用量不计作免费。</p>'+''.join(main)+'<hr><h1>各轮完整证据与失败历史</h1>'+''.join(cards))
print(json.dumps(rows,ensure_ascii=False,indent=2))
