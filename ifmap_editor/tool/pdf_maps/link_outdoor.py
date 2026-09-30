# 建物の出入口に接続点を置き、屋外図 (NITTC_ground_1F) とつなぐ。
#   python tool/pdf_maps/link_outdoor.py   … gen.py build のあとに実行する
#
# やること（建物ごと）:
#   1. 平面図の出入口（寮は「玄関」の文字、ほかは入口の矢印の位置）を1Fのマスへ
#   2. 1Fの外形を、構内図(PDF 1ページ目)のその建物の形に重ねる（4方向を試して
#      いちばん重なる向き）。同じ変換で出入口を構内図へ移す
#   3. 屋外図のマスで、そこにいちばん近い歩ける所（道）を接続点にする
#   両方の接続点に同じ名前（例: 大志寮_玄関）を付けて対応づける。
#
# 屋外図は手で作ったものなので、書き換えたマスには元の type を origType に残し、
# 次に実行したときは元へ戻してから置き直す。
import sys, os, json, glob, math, collections, unicodedata
import numpy as np, cv2, pymupdf
sys.path.insert(0, os.path.dirname(__file__))
from floors import FLOORS
from gen import PDF, ASSETS, WORK, geom, lines_page

OUTDOOR = 'NITTC_ground_1F'
OUTDOOR_PATH = f'{ASSETS}/NITTC/{OUTDOOR}.json'

# 屋外図の下絵 = 構内図のページを ZOOM 倍で描いて時計回りに90度回し、
# (OX, OY) から切り出したもの（下絵とページの画像を突き合わせて求めた）。
ZOOM, OX, OY = 1.75, 149, 122

# 構内図で建物名が書いてある文字（その位置から建物の形を拾う）
CAMPUS_NAME = {
    'YUSHI': ['友志寮'], 'KISHI': ['輝志寮'], 'EISHI': ['栄志寮'], 'KOSHI': ['高志寮'],
    'MEISHI': ['明志寮'], 'SOSHI': ['創志寮'], 'TAISHI': ['大志寮'],
    'WELFARE': ['福利施設', '福利厚生会館'], 'TRAINING': ['合宿'],
    'GYM1': ['第1体育館'], 'GYM2': ['第2体育館'], 'BUDO': ['武道場', '卓球場'], 'KYUDO': ['弓道場'],
}

# 寮以外の平面図には「玄関」の文字がないので、入口の矢印の位置(pt)を読み取って置く
ENTRANCES_PT = {
    'WELFARE_1F': [('食堂入口', (99, 562)), ('食堂東口', (263, 535)),
                   ('福利厚生会館西口', (330, 548)), ('福利厚生会館東口', (490, 548))],
    'TRAINING_1F': [('入口', (253, 738))],
    'GYM1_1F': [('入口', (221, 538))],
    'GYM2_1F': [('入口', (398, 173))],
    'BUDO_1F': [('武道場入口', (189, 662)), ('卓球場入口', (261, 664)), ('卓球場東口', (336, 664))],
    'KYUDO_1F': [('入口', (394, 586))],
}


def nfkc(s):
    return unicodedata.normalize('NFKC', s).replace(' ', '').replace('　', '')


def text_lines(page):
    """(文字列, 中心x, 中心y) の行の一覧。"""
    out = []
    for b in page.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            t = nfkc(''.join(c['c'] for s in l['spans'] for c in s['chars']))
            x0, y0, x1, y1 = l['bbox']
            out.append((t, (x0 + x1) / 2, (y0 + y1) / 2))
    return out


def page_to_bg(px, py, page_h):
    """構内図ページの座標(pt) → 屋外図の下絵の画素。"""
    return ZOOM * (page_h - py) - OX, ZOOM * px - OY


def campus_masks(doc):
    page = doc[0]
    H = page.rect.height
    lines = text_lines(page)
    lp = lines_page(pymupdf.open(PDF), 0)
    pix = lp.get_pixmap(matrix=pymupdf.Matrix(ZOOM, ZOOM), colorspace=pymupdf.csGRAY)
    a = np.frombuffer(pix.samples, np.uint8).reshape(pix.h, pix.w)
    a = cv2.rotate(a, cv2.ROTATE_90_CLOCKWISE)[OY:, OX:]
    light = (a > 200).astype(np.uint8)
    masks = {}
    for key, names in CAMPUS_NAME.items():
        m = np.zeros_like(light)
        for name in names:
            hits = [(x, y) for t, x, y in lines if name in t]
            if not hits:
                print('  構内図に見つからない:', name); continue
            bx, by = page_to_bg(hits[0][0], hits[0][1], H)
            seed = (int(bx), int(by))
            # 文字のあった所が白くなければ、近くの白い所から
            if not light[seed[1], seed[0]]:
                ys, xs = np.where(light[seed[1] - 8:seed[1] + 9, seed[0] - 8:seed[0] + 9])
                if len(ys) == 0: continue
                i = np.argmin((ys - 8) ** 2 + (xs - 8) ** 2)
                seed = (seed[0] + xs[i] - 8, seed[1] + ys[i] - 8)
            ff = light.copy()
            fm = np.zeros((ff.shape[0] + 2, ff.shape[1] + 2), np.uint8)
            cv2.floodFill(ff, fm, seed, 2)
            m |= (ff == 2).astype(np.uint8)
        masks[key] = m
    return masks


def plan_entrances(fl, doc):
    """平面図の出入口: [(名前, (x, y)pt)]"""
    label, pno, boxes = fl[0], fl[6], fl[7]
    if label in ENTRANCES_PT:
        return ENTRANCES_PT[label]
    x0 = min(b[0] for b in boxes) - 15; y0 = min(b[1] for b in boxes) - 15
    x1 = max(b[0] + b[2] for b in boxes) + 15; y1 = max(b[1] + b[3] for b in boxes) + 15
    found = [(t, x, y) for t, x, y in text_lines(doc[pno])
             if '玄関' in t and x0 <= x <= x1 and y0 <= y <= y1]
    found.sort(key=lambda f: f[1])
    cnt = collections.Counter(t for t, _, _ in found)
    seen = collections.Counter()
    out = []
    for t, x, y in found:
        name = t
        if cnt[t] > 1:
            seen[t] += 1; name = f'{t}({seen[t]})'
        out.append((name, (x, y)))
    return out


def best_fit(foot, cmask):
    """1Fの外形 foot(マス) を構内図の形 cmask(画素) にいちばん重なる向きで合わせる。
    (回転回数k, 構内図の外接矩形, 重なり度) を返す。"""
    ys, xs = np.where(cmask)
    if len(ys) == 0: return None
    cx0, cy0, cx1, cy1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    crop = cmask[cy0:cy1, cx0:cx1].astype(bool)
    fy, fx = np.where(foot)
    f = foot[fy.min():fy.max() + 1, fx.min():fx.max() + 1].astype(np.uint8)
    best = None
    for k in range(4):
        r = cv2.resize(np.rot90(f, k).astype(np.uint8), (cx1 - cx0, cy1 - cy0),
                       interpolation=cv2.INTER_NEAREST).astype(bool)
        iou = (r & crop).sum() / max((r | crop).sum(), 1)
        # 長方形に近い建物はどの向きでもほぼ同じだけ重なる。そのときは回さない
        if best is None or iou > best[2] + 0.03:
            best = (k, (cx0, cy0, cx1, cy1), iou)
    return best, (fx.min(), fy.min(), fx.max() + 1, fy.max() + 1)


def rot_uv(u, v, k):
    for _ in range(k):  # np.rot90 は反時計回り
        u, v = v, 1 - u
    return u, v


def load(path):
    return json.load(open(path, encoding='utf-8'))


def save(path, d):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False, separators=(',', ':'))


def nearest_node(nodes, gx, gy, types, cells_by_xy, exclude=()):
    best = None
    for k, v in nodes.items():
        if k == '_editorData' or k in exclude: continue
        x, y = v['x'] // 10, v['y'] // 10
        c = cells_by_xy.get((x, y))
        if c is None or c['type'] not in types: continue
        d = (x - gx) ** 2 + (y - gy) ** 2
        if best is None or d < best[0]: best = (d, k, c)
    return best


def make_connector(nodes, key, cell, name, to_label):
    cell.setdefault('origType', cell['type'])
    cell['type'] = 5; cell['name'] = name; cell['connectsToMap'] = to_label
    nodes[key]['isConnector'] = True
    nodes[key]['name'] = name
    nodes[key]['connectsToMap'] = to_label


def main():
    doc = pymupdf.open(PDF)
    ground = load(OUTDOOR_PATH)
    ge = ground['_editorData']
    ours = {fl[0] for fl in FLOORS}
    # 前回置いた接続点を元に戻す
    cells_by_xy = {(c['x'], c['y']): c for c in ge['cells']}
    for c in ge['cells']:
        if c.get('connectsToMap') in ours:
            c['type'] = c.pop('origType', 1)
            for k in ('name', 'connectsToMap'): c.pop(k, None)
            n = ground.get(f"node_{c['y']}-{c['x']}")
            if n:
                for k in ('isConnector', 'name', 'connectsToMap'): n.pop(k, None)
    gR, gC = ge['rows'], ge['cols']
    bg_w, bg_h = 1196, 818   # 下絵の大きさ
    cw, ch = bg_w / gC, bg_h / gR

    masks = campus_masks(doc)
    used = set()
    report = []
    for fl in FLOORS:
        label = fl[0]
        if fl[5] != 1: continue  # 1階だけが外とつながる
        key = label.split('_')[0]
        bname = fl[3]
        path = f'{ASSETS}/{fl[1]}/{label}.json'
        plan = load(path)
        pe = plan['_editorData']
        pcells = {(c['x'], c['y']): c for c in pe['cells']}
        clip, z, cols, rows, cell_pt = geom(fl)
        foot = np.load(f'{WORK}/{label}_foot.npy')
        fit = best_fit(foot, masks.get(key, np.zeros(1)))
        if fit is None or fit[0] is None:
            print(f'  {label}: 構内図で建物の形が取れない'); continue
        (k, (cx0, cy0, cx1, cy1), iou), (fx0, fy0, fx1, fy1) = fit
        for ename, (ex, ey) in plan_entrances(fl, doc):
            name = f'{bname}_{ename}'
            # 平面図: 出入口にいちばん近い歩けるマス
            px, py = (ex - clip.x0) / cell_pt, (ey - clip.y0) / cell_pt
            pn = nearest_node(plan, px, py, (1, 3), pcells)
            if pn is None: continue
            make_connector(plan, pn[1], pn[2], name, OUTDOOR)
            # 構内図へ
            u, v = rot_uv((px - fx0) / (fx1 - fx0), (py - fy0) / (fy1 - fy0), k)
            bx, by = cx0 + u * (cx1 - cx0), cy0 + v * (cy1 - cy0)
            gx, gy = bx / cw, by / ch
            gn = nearest_node(ground, gx, gy, (1, 6, 3), cells_by_xy, exclude=used)
            used.add(gn[1])
            make_connector(ground, gn[1], gn[2], name, label)
            report.append(f'  {name}: 向き{k * 90}° 重なり{iou:.2f} 道まで{math.sqrt(gn[0]):.1f}マス')
        save(path, plan)
    save(OUTDOOR_PATH, ground)
    print('\n'.join(report))


if __name__ == '__main__':
    main()
