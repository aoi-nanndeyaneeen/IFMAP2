# 各フロア: 階段名、部屋への到達率。建物ごと: 上下の階で共通の階段名があるか
import sys, os, json, collections
sys.path.insert(0, os.path.dirname(__file__))
from floors import FLOORS
from gen import ASSETS, WORK
prev = {}
for fl in FLOORS:
    label, folder, bname = fl[0], fl[1], fl[3]
    d = json.load(open(f'{ASSETS}/{folder}/{label}.json', encoding='utf-8'))
    d.pop('_editorData')
    st = sorted({v['name'] for v in d.values() if v.get('isStairs')})
    names = {v['name'] for v in d.values() if v.get('name') and not v.get('isStairs')}
    # 最大の連結成分
    seen = set(); comps = []
    for k in d:
        if k in seen: continue
        c = []; q = [k]; seen.add(k)
        while q:
            u = q.pop(); c.append(u)
            for e in d[u]['edges']:
                if e not in seen: seen.add(e); q.append(e)
        comps.append(c)
    big = max(comps, key=len); bs = set(big)
    reach_n = {d[k]['name'] for k in bs if d[k].get('name')}
    unreached = sorted(n for n in names if n not in reach_n)
    shared = ''
    if bname in prev:
        shared = '共通階段:' + (','.join(n.split('_')[-1] for n in set(prev[bname]) & set(st)) or 'なし!!')
    prev[bname] = st
    print(f"{label:12} 階段{[s.split('_')[-1] for s in st]} 最大成分{len(big)}/{len(d)} 未到達{[u.split('_')[-1] for u in unreached]} {shared}")
