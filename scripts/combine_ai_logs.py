#!/usr/bin/env python3
"""Combine exported AI production logs into a readable, offline HTML report.
Usage: python3 scripts/combine_ai_logs.py LOG_DIRECTORY [--output REPORT.html]
Original files are read-only; keep the report beside the log directory for image links.
"""
import argparse
import collections
import html
import json
from pathlib import Path
import os

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
root = args.directory.resolve()
if not root.is_dir():
    parser.error('Log directory does not exist')
output = (args.output or root.parent / (root.name + '-阅读报告.html')).resolve()
rows, failures = [], []
for path in root.glob('*.json'):
    try:
        record = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(record, dict):
            raise ValueError('Expected an object')
        record['_file'] = path.name
        rows.append(record)
    except (ValueError, OSError) as error:
        failures.append(f'{path.name}: {error}')
rows.sort(key=lambda row: (row.get('sequence', 0), row['_file']))
counts = collections.Counter(row.get('kind', 'unknown') for row in rows)
escape = lambda value: html.escape(str(value))

def render(value):
    pictures = []
    def walk(item):
        if isinstance(item, dict):
            for key, child in item.items():
                if key in ('attachment', 'file') and isinstance(child, str) and child.startswith('attachments/'):
                    candidate = (root / child).resolve()
                    if candidate.is_relative_to(root) and candidate.is_file() and candidate.suffix.lower() in ('.png', '.jpg', '.jpeg', '.webp'):
                        url = Path(os.path.relpath(candidate, output.parent)).as_posix()
                        pictures.append(f'<a href="{escape(url)}"><img loading="lazy" src="{escape(url)}"></a>')
                walk(child)
        elif isinstance(item, list):
            for child in item:
                walk(child)
    walk(value)
    return ''.join(dict.fromkeys(pictures)) + '<pre>' + escape(json.dumps(value, ensure_ascii=False, indent=2)) + '</pre>'

parts = ['''<!doctype html><html lang="zh"><meta charset="utf-8"><title>AI 制作日志阅读报告</title>
<style>body{font:16px system-ui;max-width:1100px;margin:40px auto;padding:0 20px;background:#f5f5f3;color:#24342f}details,section{background:white;border-radius:12px;padding:16px;margin:12px 0}summary{cursor:pointer;font-weight:600}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:13px ui-monospace;max-height:650px;overflow:auto}img{max-width:320px;max-height:260px;margin:10px}.error{border-left:5px solid #cc692c}small{color:#68746e}a{color:#26725b}</style>
<h1>AI 制作日志阅读报告</h1>''']
parts.append(f'<p>来源：{escape(root.name)} · {len(rows)} 条记录。原始文件保持不变。</p>')
parts.append('<section><h2>记录统计</h2>' + render(dict(counts)) + '</section>')
errors = [r for r in rows if r.get('kind') == 'event' and isinstance(r.get('payload'), dict) and r['payload'].get('kind') == 'error']
parts.append('<section class="error"><h2>错误汇总</h2>')
for row in errors:
    payload = row['payload']
    parts.append(f'<p><a href="#record-{row.get("sequence")}">#{row.get("sequence")} {escape(payload.get("title", "错误"))}</a><br>{escape(payload.get("detail", ""))}</p>')
parts.append('</section><h2>制作时间线与请求详情</h2>')
stream = []

def flush():
    if not stream:
        return
    types = collections.Counter(r.get('payload', {}).get('type', '协议行') if isinstance(r.get('payload'), dict) else '其他' for r in stream)
    parts.append(f'<details><summary>流式接收：{len(stream)} 条 · #{stream[0].get("sequence")}—#{stream[-1].get("sequence")}</summary>')
    parts.append(render(dict(types)))
    for row in stream:
        parts.append(f'<details id="record-{row.get("sequence")}"><summary>#{row.get("sequence")} {escape(row.get("time", ""))}</summary>{render(row.get("payload"))}</details>')
    parts.append('</details>')
    stream.clear()

for row in rows:
    kind, payload = row.get('kind'), row.get('payload')
    if kind == 'sse':
        stream.append(row)
        continue
    flush()
    title = payload.get('title', kind) if isinstance(payload, dict) else kind
    css = ' class="error"' if row in errors else ''
    parts.append(f'<details{css} id="record-{row.get("sequence")}"><summary>#{row.get("sequence")} · {escape(row.get("time", ""))} · {escape(title)}</summary><small>{escape(row["_file"])}</small>{render(payload)}</details>')
flush()
if failures:
    parts.append('<section><h2>无法读取的文件</h2>' + render(failures) + '</section>')
parts.append('</html>')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(''.join(parts), encoding='utf-8')
print(f'Report: {output}\nRecords: {len(rows)}, errors: {len(errors)}, unreadable: {len(failures)}')
