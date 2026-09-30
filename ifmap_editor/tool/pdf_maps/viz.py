# 生成したJSONを絵にする（下: 元の図、上: 生成結果）
import sys, os, json, glob, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(__file__))
from floors import FLOORS
from gen import ASSETS, WORK
HERE = os.path.dirname(os.path.abspath(__file__))
S = 10
font = ImageFont.truetype('C:/Windows/Fonts/meiryo.ttc', 11)
COL = {1: (170, 200, 255), 3: (255, 225, 150), 4: (140, 220, 140), 0: (255, 255, 255)}
labels = sys.argv[1:] or [f[0] for f in FLOORS]
for fl in FLOORS:
    if fl[0] not in labels: continue
    d = json.load(open(f'{ASSETS}/{fl[1]}/{fl[0]}.json', encoding='utf-8'))
    e = d['_editorData']; R, C = e['rows'], e['cols']
    im = Image.new('RGB', (C * S, R * S), 'white'); dr = ImageDraw.Draw(im)
    for c in e['cells']:
        x, y = c['x'] * S, c['y'] * S
        dr.rectangle([x, y, x + S - 1, y + S - 1], fill=COL.get(c['type'], (200, 200, 200)))
    for c in e['cells']:
        x, y = c['x'] * S, c['y'] * S
        for k, seg in (('Top', (x, y, x + S, y)), ('Bottom', (x, y + S, x + S, y + S)), ('Left', (x, y, x, y + S)), ('Right', (x + S, y, x + S, y + S))):
            if c.get('door' + k): dr.line(seg, fill=(230, 0, 0), width=3)
            elif c.get('wall' + k): dr.line(seg, fill=(0, 0, 0), width=2)
    for r in e['rooms']:
        n = r['name'].split('_', 2)[-1] if '階段' not in r['name'] else r['name'].split('_')[-1]
        dr.text((r['centerX'] / 10 * S, r['centerY'] / 10 * S), n, fill=(0, 0, 160), font=font, anchor='mm')
    bg = Image.open(f'{WORK}/{fl[0]}_bg.png').convert('RGB').resize(im.size)
    out = Image.new('RGB', (im.width, im.height * 2 + 10), 'gray'); out.paste(im, (0, 0)); out.paste(bg, (0, im.height + 10))
    out.save(f'{WORK}/viz/{fl[0]}.png')
