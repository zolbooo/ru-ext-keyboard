#!/usr/bin/env python3
"""Convert a macOS sample call graph to a standalone, interactive flamegraph."""
import argparse
import collections
import html
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('sample', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
def node(name):
    return {'name': name, 'value': 0, 'children': {}}
roots = {key: node(label) for key, label in [('first', 'First keyboard construction'), ('warm', 'Repeated keyboard construction')]}
folded = {key: collections.Counter() for key in roots}
# sample emits an inclusive-count tree, with two indentation columns per level.
# Convert each node's self count to weighted folded stacks, avoiding double counting.
text = args.sample.read_text()
if 'Call graph:' not in text:
    raise SystemExit('Missing Call graph section in sample output')
graph = text.split('Call graph:', 1)[1].split('Total number in stack', 1)[0]
threads = []
parents = []
for line in graph.splitlines():
    match = re.match(r'^([ +!:|]*)([0-9]+) (.+)$', line)
    if not match:
        continue
    prefix, count, label = match.groups()
    item = {'name': re.sub(r'\s+\(in ([^)]+)\).*$', r' [\1]', label), 'count': int(count), 'children': []}
    indent = len(prefix)
    while parents and parents[-1][0] >= indent:
        parents.pop()
    if parents:
        parents[-1][1]['children'].append(item)
    else:
        threads.append(item)
    parents.append((indent, item))

def visit(item, frames):
    frames = frames + [item['name']]
    own = item['count'] - sum(child['count'] for child in item['children'])
    if own < 0:
        raise SystemExit('Invalid sample tree: children exceed inclusive sample count')
    if own:
        group = None
        for index, name in enumerate(frames):
            if 'profileRepeatedKeyboardStartup' in name:
                group = 'warm'
                break
            if 'profileFirstKeyboardStartup' in name:
                group = 'first'
                break
        if group:
            stack = frames[index:]
            folded[group][tuple(stack)] += own
            current = roots[group]
            current['value'] += own
            for name in stack:
                current = current['children'].setdefault(name, node(name))
                current['value'] += own
    for child in item['children']:
        visit(child, frames)
for thread in threads:
    visit(thread, [])

def compact(root):
    root['children'] = [compact(child) for child in sorted(root['children'].values(), key=lambda child: (-child['value'], child['name']))]
    return root
for key, root in roots.items():
    if not root['value']:
        raise SystemExit(f'No samples for {key}; verify symbols and startup boundary frames before generating a chart')
    compact(root)
    args.output.with_name(key + '.folded').write_text(''.join(';'.join(stack).replace('\n', ' ') + f' {count}\n' for stack, count in folded[key].items()))
args.output.with_suffix('.json').write_text(json.dumps(roots, indent=2))
data = json.dumps(roots).replace('<', '\\u003c')
page = r'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Keyboard startup flamegraph</title>
<style>
body{margin:0;background:#101827;color:#e8edf7;font:14px system-ui,sans-serif}main{max-width:1500px;margin:auto;padding:32px}h1{font-size:28px;margin:0 0 12px}p{color:#b9c6dc;line-height:1.6;max-width:1040px}button,input{font:inherit;padding:9px 13px;border-radius:7px;border:1px solid #526077;background:#1f2d43;color:#edf3ff}button{cursor:pointer}button.active{background:#2563eb;border-color:#60a5fa}nav{display:flex;gap:10px;flex-wrap:wrap;margin:22px 0}#stats{font-variant-numeric:tabular-nums;color:#d9e7ff;margin:12px 0}#graph{background:#172338;border:1px solid #3a4860;border-radius:8px;overflow:auto}svg{display:block;width:100%;min-width:900px}svg text{font:11px ui-monospace,monospace;fill:#201909;pointer-events:none}svg rect{stroke:#101827;stroke-width:.6;cursor:pointer}svg rect:hover{stroke:#fff;stroke-width:1.5}#detail{white-space:pre-wrap;overflow-wrap:anywhere;min-height:60px;color:#deebff;background:#1b2940;border-radius:8px;padding:14px}small{color:#9babc5}
</style><main><h1>Keyboard startup flamegraph</h1>
<p>Actual macOS <code>sample</code> stack samples from the optimized keyboard in the iPhone 17 Pro simulator (iOS 26.5). First-use startup and 500 repeated constructions are separated. Width represents <b>stack sample count (including waits)</b>, not elapsed time or chronological order. Bottom frames call the frames above them.</p>
<p>The boundary includes controller initialization, view loading, and first layout at 393 × 216 points. App launch, teardown, and the profiling harness are excluded. These are main-thread wall-stack samples, not a CPU-only profile. Sampling and profiler overhead mean these counts cannot be used to reproduce the 58.7 ms uninstrumented benchmark.</p>
<nav><button id="first" class="active">First use</button><button id="warm">Repeated construction</button><button id="reset">Reset zoom</button><input id="search" placeholder="Find a function…" aria-label="Find a function"></nav>
<div id="stats"></div><div id="graph"></div><p id="detail">Hover for function details. Click a frame to zoom. Use the tabs to switch profiles.</p><small>Release-style optimized Swift with debug symbols. Raw sampler report and folded stacks accompany this report. A short first-use capture has limited statistical resolution.</small></main>
<script>const profiles=DATA;let selected='first',focus=profiles.first;const ns='http://www.w3.org/2000/svg';
function depth(n){return 1+Math.max(0,...n.children.map(depth))}
function color(name){let h=0;for(const c of name)h=(h*31+c.charCodeAt(0))>>>0;return `hsl(${15+h%38} 88% ${57+h%15}%)`}
function draw(){const full=profiles[selected],levels=depth(focus),height=levels*23+12,width=1440;const svg=document.createElementNS(ns,'svg');svg.setAttribute('viewBox',`0 0 ${width} ${height}`);svg.setAttribute('role','img');svg.setAttribute('aria-label','Interactive sampled startup flamegraph');
const query=document.getElementById('search').value.toLowerCase();document.getElementById('stats').textContent=`${full.value.toLocaleString()} startup stack samples · ${selected==='first'?'1 first-use construction':'500 repeated constructions'} · Showing ${focus.value.toLocaleString()} samples (${(100*focus.value/full.value).toFixed(1)}%)`;
function frame(n,x,w,level){if(w<.4)return;const y=height-(level+1)*23-5;const g=document.createElementNS(ns,'g'),r=document.createElementNS(ns,'rect');for(const[k,v]of Object.entries({x,y,width:w,height:22,fill:query&&n.name.toLowerCase().includes(query)?'#c084fc':color(n.name)}))r.setAttribute(k,v);const detail=`${n.name}\n${n.value} stack samples · ${(100*n.value/full.value).toFixed(2)}% of this profile · Self samples: ${n.value-n.children.reduce((a,c)=>a+c.value,0)}`;const title=document.createElementNS(ns,'title');title.textContent=detail;r.appendChild(title);g.appendChild(r);r.addEventListener('mouseenter',()=>document.getElementById('detail').textContent=detail);r.addEventListener('click',()=>{focus=n;draw()});if(w>35){const t=document.createElementNS(ns,'text');t.setAttribute('x',x+4);t.setAttribute('y',y+15);const cap=Math.floor((w-8)/6.6);t.textContent=n.name.length>cap?n.name.slice(0,Math.max(0,cap-1))+'…':n.name;g.appendChild(t)}svg.appendChild(g);let cx=x;for(const c of n.children){const cw=w*c.value/n.value;frame(c,cx,cw,level+1);cx+=cw}}
frame(focus,0,width,0);document.getElementById('graph').replaceChildren(svg)}
for(const key of ['first','warm'])document.getElementById(key).onclick=()=>{selected=key;focus=profiles[key];document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('active',b.id===key));draw()};document.getElementById('reset').onclick=()=>{focus=profiles[selected];draw()};document.getElementById('search').oninput=draw;draw();</script></html>'''
args.output.write_text(page.replace('DATA', data))
print(json.dumps({key: root['value'] for key, root in roots.items()}))
