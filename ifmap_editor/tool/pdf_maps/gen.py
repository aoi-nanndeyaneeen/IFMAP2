# 見取り図PDFからフロアJSONを作る。ifmap_editor/ で次の順に実行する。
#   python tool/pdf_maps/gen.py render                        … フロアごとに線画(記号除去)と下絵を作る
#   dart run tool/detect_walls.dart tool/pdf_maps/work/jobs.json … エディタの壁の自動生成
#   python tool/pdf_maps/gen.py build                         … 部屋・通路・扉・階段を決めてJSONを書く
#   python tool/pdf_maps/link_outdoor.py                      … 各建物の出入口と屋外図を接続点でつなぐ
#   python tool/pdf_maps/build_index.py                       … 区域/建物/階/部屋の索引を書く
#   python tool/pdf_maps/viz.py [ラベル...]                    … 確認用の絵 (work/viz/)
#   python tool/pdf_maps/check.py                             … 階段のつながり・到達できない部屋
#
# 必要: pip install pymupdf opencv-python numpy pillow
#
# 自動で決めているので、仕上げはエディタで読み込んで直す前提。
#   - 部屋名は、壁で囲まれた領域に入っている文字をつなげたもの
#   - 名前のない細長い領域が通路。扉は部屋と通路の境目のまん中に1つ
#   - 階段は短い平行線が並ぶ所。同じ建物で位置が近い階段は同じ名前(階をまたぐ対応づけ)
import sys, os, json, glob, math, base64, collections, unicodedata
import numpy as np, cv2, pymupdf
sys.path.insert(0, os.path.dirname(__file__))
from floors import FLOORS

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, 'work')
# 見取り図のPDF（学生便覧の構内図・建物平面図のページ）。環境変数で差し替えられる
PDF = os.environ.get('IFMAP_PDF') or os.path.join(HERE, '..', '..', '豊田高専地図.pdf')
ASSETS = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'ifmap', 'assets'))
CELL_M = 0.5      # 1マス = 0.5m（ifmap の metersPerCell と同じ）
CELL_PX = 8       # 1マスを何pxで描いてから壁検出にかけるか
MARGIN = 2        # 建物のまわりに空けるマス数

os.makedirs(WORK, exist_ok=True)


def geom(fl):
    """フロアの切り出し範囲(pt)・拡大率・マス数。"""
    boxes, mpp = fl[7], fl[8]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[0] + b[2] for b in boxes); y1 = max(b[1] + b[3] for b in boxes)
    cell_pt = CELL_M / mpp
    cols = math.ceil((x1 - x0) / cell_pt) + 2 * MARGIN
    rows = math.ceil((y1 - y0) / cell_pt) + 2 * MARGIN
    ox, oy = x0 - MARGIN * cell_pt, y0 - MARGIN * cell_pt
    clip = pymupdf.Rect(ox, oy, ox + cols * cell_pt, oy + rows * cell_pt)
    return clip, CELL_PX / cell_pt, cols, rows, cell_pt


def lines_page(doc, pno):
    p = doc[pno]
    p.add_redact_annot(p.rect)
    p.apply_redactions(images=0, graphics=0, text=0)
    return p


def clean_symbols(ink):
    """壁に接している記号も消す。塗りつぶしの塊と、まっすぐな線でない部分を落とし、
    それで壁に空いた小さな切れ目は線の向きに沿ってふさぐ。"""
    px_m = CELL_PX / CELL_M
    orig = ink.copy()
    disk = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    solid = cv2.dilate(cv2.morphologyEx(ink, cv2.MORPH_OPEN, disk), np.ones((5, 5), np.uint8))
    ink = ink & (1 - solid)
    L = int(0.7 * px_m)
    lh = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((1, L), np.uint8))
    lv = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((L, 1), np.uint8))
    lines = lh | lv
    resid = ink & (1 - cv2.dilate(lines, np.ones((3, 3), np.uint8)))
    n, lab, st, _ = cv2.connectedComponentsWithStats(resid, connectivity=8)
    for i in range(1, n):
        if max(st[i][2], st[i][3]) < 2.5 * px_m:
            ink[lab == i] = 0
    G = int(1.5 * px_m)
    ink |= cv2.morphologyEx(lh, cv2.MORPH_CLOSE, np.ones((1, G), np.uint8))
    ink |= cv2.morphologyEx(lv, cv2.MORPH_CLOSE, np.ones((G, 1), np.uint8))
    # 記号の下を通っていた壁: 元の図で2.5m以上まっすぐ続く線は戻す
    Lg = int(2.5 * px_m)
    ink |= cv2.morphologyEx(orig, cv2.MORPH_OPEN, np.ones((1, Lg), np.uint8))
    ink |= cv2.morphologyEx(orig, cv2.MORPH_OPEN, np.ones((Lg, 1), np.uint8))
    return ink


def render():
    doc_lines = pymupdf.open(PDF)
    doc_full = pymupdf.open(PDF)
    stripped = {}
    jobs = []
    for fl in FLOORS:
        label, pno, boxes, mpp = fl[0], fl[6], fl[7], fl[8]
        if pno not in stripped:
            stripped[pno] = lines_page(doc_lines, pno)
        clip, z, cols, rows, cell_pt = geom(fl)
        m = pymupdf.Matrix(z, z)
        pix = stripped[pno].get_pixmap(matrix=m, clip=clip, colorspace=pymupdf.csGRAY)
        a = np.frombuffer(pix.samples, np.uint8).reshape(pix.h, pix.w)
        a = cv2.resize(a, (cols * CELL_PX, rows * CELL_PX), interpolation=cv2.INTER_AREA)
        ink = (a < 160).astype(np.uint8)
        # 指定した塊の外（隣の建物・見出しの枠）は消す
        keep = np.zeros_like(ink)
        for b in boxes:
            bx0 = int((b[0] - clip.x0) * z) - 3; by0 = int((b[1] - clip.y0) * z) - 3
            bx1 = int((b[0] + b[2] - clip.x0) * z) + 3; by1 = int((b[1] + b[3] - clip.y0) * z) + 3
            keep[max(by0, 0):by1, max(bx0, 0):bx1] = 1
        ink &= keep
        ink = clean_symbols(ink)
        # 記号（消火器・担架・トイレの絵など）= 小さく独立した塊を消す
        n, lab, st, _ = cv2.connectedComponentsWithStats(ink, connectivity=8)
        lim = 2.5 / CELL_M * CELL_PX  # 2.5m
        for i in range(1, n):
            if max(st[i][2], st[i][3]) < lim:
                ink[lab == i] = 0
        np.save(f'{WORK}/{label}_ink.npy', ink)
        img = np.where(ink > 0, 0, 255).astype(np.uint8)
        cv2.imwrite(f'{WORK}/{label}_lines.png', img)
        # エディタで下絵として出す見取り図（文字あり）
        bz = min(z, 4.0)
        full = doc_full[pno].get_pixmap(matrix=pymupdf.Matrix(bz, bz), clip=clip)
        full.save(f'{WORK}/{label}_bg.png')
        jobs.append({'image': f'{WORK}/{label}_lines.png', 'cols': cols, 'rows': rows,
                     'sensitivity': 0.5, 'out': f'{WORK}/{label}_walls.json'})
        print(label, cols, 'x', rows)
    json.dump(jobs, open(f'{WORK}/jobs.json', 'w'), ensure_ascii=False)


# ─────────────────────────── build ───────────────────────────

SKIP_WORDS = {'は', '袋', 'ロ', '玄関', '北玄関', '南玄関'}


def norm(s):
    s = unicodedata.normalize('NFKC', s)
    s = s.replace(' ', '').replace('\u3000', '')
    s = s.replace('ｗC', 'WC').replace('wC', 'WC').replace('wc', 'WC')
    return s


def find_stairs(ink, cell_px_per_m):
    """短い平行線が狭い間隔で4本以上並ぶ所を階段とみなす。矩形(px)のリスト。"""
    out = []
    H, W = ink.shape
    lmin = int(0.8 * cell_px_per_m)   # 段の線の長さ 0.8m〜
    lmax = int(6.0 * cell_px_per_m)   # 〜6m
    gap = int(0.9 * cell_px_per_m)    # 段の間隔 0.9m 未満
    for horiz in (True, False):
        k_min = np.ones((1, lmin) if horiz else (lmin, 1), np.uint8)
        k_max = np.ones((1, lmax) if horiz else (lmax, 1), np.uint8)
        long_ = cv2.morphologyEx(ink, cv2.MORPH_OPEN, k_min)
        too_long = cv2.morphologyEx(ink, cv2.MORPH_OPEN, k_max)
        short = long_ & (1 - cv2.dilate(too_long, np.ones((3, 3), np.uint8)))
        n, lab, st, _ = cv2.connectedComponentsWithStats(short)
        segs = [st[i] for i in range(1, n) if (st[i][2] if horiz else st[i][3]) >= lmin]
        if len(segs) < 4:
            continue
        m = np.zeros_like(ink)
        for x, y, w, h, _ in segs:
            m[y:y + h, x:x + w] = 1
        grow = cv2.dilate(m, np.ones((gap, 1) if horiz else (1, gap), np.uint8))
        n2, lab2, st2, _ = cv2.connectedComponentsWithStats(grow)
        for j in range(1, n2):
            x, y, w, h, _ = st2[j]
            mem = [s for s in segs if x <= s[0] + s[2] / 2 <= x + w and y <= s[1] + s[3] / 2 <= y + h]
            # 段の線は長さと始まりがそろっている。そろった線がいちばん多い組を採る
            tol = 0.4 * cell_px_per_m
            i0, il = (0, 2) if horiz else (1, 3)
            best = []
            for a in mem:
                grp = [b for b in mem if abs(b[i0] - a[i0]) <= tol and abs(b[il] - a[il]) <= tol]
                if len(grp) > len(best): best = grp
            if len(best) < 4: continue
            bx0 = min(b[0] for b in best); by0 = min(b[1] for b in best)
            bx1 = max(b[0] + b[2] for b in best); by1 = max(b[1] + b[3] for b in best)
            if max(bx1 - bx0, by1 - by0) <= 7 * cell_px_per_m:
                out.append((bx0, by0, bx1, by1))
    return out


def thin_width(cells, R, C):
    m = np.zeros((R + 2, C + 2), np.uint8)
    for y, x in cells: m[y + 1, x + 1] = 1
    return 2 * cv2.distanceTransform(m, cv2.DIST_L2, 3).max()


def thin(cells, R, C):
    """面積 ÷ (いちばん太い所の幅)^2。通路のように細長く伸びた領域ほど大きい。"""
    m = np.zeros((R + 2, C + 2), np.uint8)
    for y, x in cells: m[y + 1, x + 1] = 1
    w = 2 * cv2.distanceTransform(m, cv2.DIST_L2, 3).max()
    return len(cells) / max(w, 1) ** 2


def page_chars(page):
    """1文字ずつの位置。縦書きは文字の枠が1文字ぶん下にずれて出るので戻す。"""
    out = []
    for bi, b in enumerate(page.get_text('rawdict')['blocks']):
        for li, l in enumerate(b.get('lines', [])):
            vertical = abs(l['dir'][1]) > 0.5
            for si, sp in enumerate(l['spans']):
                for ci, ch in enumerate(sp['chars']):
                    if not ch['c'].strip(): continue
                    x0, y0, x1, y1 = ch['bbox']
                    if vertical:
                        y0 -= sp['size']; y1 -= sp['size']
                    out.append((x0, y0, x1, y1, ch['c'], bi, li, si * 1000 + ci))
    return out


def short_walls(ink, R, C, band=3, cover=0.6):
    """マスの境目に沿って線がどれだけ引かれているかで壁を決める。"""
    P = CELL_PX
    wr = np.zeros((R, C), bool); wb = np.zeros((R, C), bool)
    for x in range(1, C):
        col = ink[:, max(x * P - band, 0):x * P + band + 1].any(axis=1)
        for y in range(R):
            if col[y * P:(y + 1) * P].mean() >= cover:
                wr[y, x - 1] = True
    for y in range(1, R):
        row = ink[max(y * P - band, 0):y * P + band + 1, :].any(axis=0)
        for x in range(C):
            if row[x * P:(x + 1) * P].mean() >= cover:
                wb[y - 1, x] = True
    return wr, wb


def build():
    doc = pymupdf.open(PDF)
    words_by_page = {}
    results = {}
    stairs_by_building = collections.defaultdict(list)

    for fl in FLOORS:
        label, folder, zone, bname, fname, flevel, pno, boxes, mpp = fl
        clip, z, cols, rows, cell_pt = geom(fl)
        ink = np.load(f'{WORK}/{label}_ink.npy')
        walls = json.load(open(f'{WORK}/{label}_walls.json'))
        R, C = rows, cols
        wr = np.zeros((R, C), bool)   # マスの右に壁
        wb = np.zeros((R, C), bool)   # マスの下に壁
        for w in walls:
            x, y, d = w.split('_'); x, y = int(x), int(y)
            (wr if d == 'v' else wb)[y, x] = True
        # 壁の自動生成は3.5m未満の壁を捨てるので、トイレ・洗面所の仕切りなど
        # 短い壁は記号を消した線画から直接拾って足す
        swr, swb = short_walls(ink, R, C)
        wr |= swr; wb |= swb

        # 建物の外形: 線を閉じて穴埋め
        k = CELL_PX * 2
        closed = cv2.morphologyEx(ink, cv2.MORPH_CLOSE, np.ones((k, k), np.uint8))
        ff = closed.copy() * 255
        h, w = ff.shape
        mask = np.zeros((h + 2, w + 2), np.uint8)
        cv2.floodFill(ff, mask, (0, 0), 128)
        foot = (ff != 128).astype(np.uint8)
        cellfoot = cv2.resize(foot.astype(np.float32), (C, R), interpolation=cv2.INTER_AREA) > 0.5
        np.save(f'{WORK}/{label}_foot.npy', cellfoot)  # link_outdoor.py が屋外図と重ねるのに使う

        # 外形の境目には必ず壁
        wr[:, :-1] |= cellfoot[:, :-1] != cellfoot[:, 1:]
        wb[:-1, :] |= cellfoot[:-1, :] != cellfoot[1:, :]

        # 階段
        stairs = np.zeros((R, C), bool)
        srects = []
        for (x0, y0, x1, y1) in find_stairs(ink, CELL_PX / CELL_M):
            cx0, cy0 = int(x0 // CELL_PX), int(y0 // CELL_PX)
            cx1, cy1 = int(math.ceil(x1 / CELL_PX)), int(math.ceil(y1 / CELL_PX))
            area = stairs[cy0:cy1, cx0:cx1]
            if area.size == 0:
                continue
            stairs[cy0:cy1, cx0:cx1] = True
            srects.append((cx0, cy0, cx1, cy1))
        stairs &= cellfoot
        # 階段の中の段の線は壁にしない
        wr[:, :-1] &= ~(stairs[:, :-1] & stairs[:, 1:])
        wb[:-1, :] &= ~(stairs[:-1, :] & stairs[1:, :])

        # 壁で区切られた領域に分ける
        reg = -np.ones((R, C), int)
        regions = []
        for sy in range(R):
            for sx in range(C):
                if not cellfoot[sy, sx] or reg[sy, sx] >= 0:
                    continue
                rid = len(regions); cells = []
                st = [(sy, sx)]; reg[sy, sx] = rid
                while st:
                    y, x = st.pop(); cells.append((y, x))
                    for ny, nx, blocked in ((y, x + 1, x + 1 >= C or wr[y, x]), (y, x - 1, x - 1 < 0 or wr[y, x - 1]),
                                            (y + 1, x, y + 1 >= R or wb[y, x]), (y - 1, x, y - 1 < 0 or wb[y - 1, x])):
                        if blocked or not cellfoot[ny, nx] or reg[ny, nx] >= 0:
                            continue
                        reg[ny, nx] = rid; st.append((ny, nx))
                regions.append(cells)

        # 二重線の間などにできる幅1m以下の帯は、接するいちばん大きい領域に吸収し、
        # 間の壁を取り払う（通路と部屋の列が帯で切り離されないように）
        for rid, cells in enumerate(regions):
            if not cells or len(cells) >= 4 and thin_width(cells, R, C) > 2: continue
            nb = collections.Counter()
            for y, x in cells:
                for ny, nx in ((y, x + 1), (y, x - 1), (y + 1, x), (y - 1, x)):
                    if 0 <= ny < R and 0 <= nx < C and reg[ny, nx] >= 0 and reg[ny, nx] != rid:
                        nb[reg[ny, nx]] += 1
            if not nb: continue
            to = max(nb, key=lambda r: len(regions[r]))
            if len(regions[to]) <= len(cells): continue
            for y, x in cells:
                reg[y, x] = to
                if x + 1 < C and reg[y, x + 1] == to: wr[y, x] = False
                if x > 0 and reg[y, x - 1] == to: wr[y, x - 1] = False
                if y + 1 < R and reg[y + 1, x] == to: wb[y, x] = False
                if y > 0 and reg[y - 1, x] == to: wb[y - 1, x] = False
            regions[to].extend(cells); regions[rid] = []

        # 文字を領域へ
        if pno not in words_by_page:
            words_by_page[pno] = page_chars(doc[pno])
        texts = collections.defaultdict(list)
        for wx0, wy0, wx1, wy1, word, b, l, n in words_by_page[pno]:
            cx, cy = (wx0 + wx1) / 2, (wy0 + wy1) / 2
            if not clip.contains(pymupdf.Point(cx, cy)):
                continue
            gx, gy = int((cx - clip.x0) / cell_pt), int((cy - clip.y0) / cell_pt)
            if not (0 <= gx < C and 0 <= gy < R) or reg[gy, gx] < 0 or stairs[gy, gx]:
                continue
            texts[reg[gy, gx]].append((b, l, n, word))

        total = int(cellfoot.sum())
        types = np.zeros((R, C), int)
        names = [None] * len(regions)
        kinds = [None] * len(regions)
        for rid, cells in enumerate(regions):
            if not cells:
                kinds[rid] = 'blank'; continue
            ys = [c[0] for c in cells]; xs = [c[1] for c in cells]
            bw, bh = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
            name = norm(''.join(t[3] for t in sorted(texts.get(rid, []))))
            if name in SKIP_WORDS:
                name = ''
            for s in SKIP_WORDS:
                if len(s) > 1: name = name.replace(s, '')
            n = len(cells)
            if (len(cells) < 4 or thin_width(cells, R, C) <= 2) and not name:
                # 外壁の線とマス目のずれで生まれる幅1m以下の帯
                kinds[rid] = 'blank'
            elif thin(cells, R, C) >= 3 and n >= 0.05 * total:
                # 幅のわりに広い＝通路。談話コーナー等がつながっていても通路とみなす
                kinds[rid] = 'corridor'
            elif name:
                kinds[rid] = 'room'; names[rid] = name
            elif n >= 0.08 * total or (thin(cells, R, C) >= 6 and n >= 30):
                kinds[rid] = 'corridor'
            else:
                kinds[rid] = 'room'
            t = {'blank': 0, 'corridor': 1, 'room': 3}[kinds[rid]]
            for y, x in cells:
                types[y, x] = t
        n_fc0, fc0 = cv2.connectedComponents(cellfoot.astype(np.uint8), connectivity=4)
        for k in range(1, n_fc0):
            rs = {reg[y, x] for y, x in zip(*np.where(fc0 == k))} - {-1}
            if any(kinds[r] == 'corridor' for r in rs): continue
            big = max(rs, key=lambda r: len(regions[r]))
            if thin(regions[big], R, C) >= 2 and len(rs) > 3:
                kinds[big] = 'corridor'; names[big] = None
                for y, x in regions[big]: types[y, x] = 1
        # 通路の中の階段、部屋になった階段室
        types[stairs & (types > 0)] = 4
        for rid, cells in enumerate(regions):
            if kinds[rid] == 'room' and all(stairs[y, x] for y, x in cells):
                kinds[rid] = 'stairs'
            elif kinds[rid] == 'room' and not names[rid] and sum(stairs[y, x] for y, x in cells) > 0.5 * len(cells):
                kinds[rid] = 'stairs'
                for y, x in cells: types[y, x] = 4

        # 同じ階に同じ名前の部屋が複数あれば番号をふる
        cnt = collections.Counter(n for n in names if n)
        seen = collections.Counter()
        order = sorted((r for r in range(len(regions)) if regions[r]), key=lambda r: (min(c[1] for c in regions[r]), min(c[0] for c in regions[r])))
        for rid in order:
            n = names[rid]
            if n and cnt[n] > 1:
                seen[n] += 1; names[rid] = f'{n}({seen[n]})'

        # 扉: 領域どうしの境目
        border = collections.defaultdict(list)   # (a,b) -> [(y,x,dir)]
        for y in range(R):
            for x in range(C):
                a = reg[y, x]
                if a < 0 or kinds[a] == 'blank': continue
                if x + 1 < C:
                    b = reg[y, x + 1]
                    if b >= 0 and b != a and kinds[b] != 'blank':
                        border[tuple(sorted((a, b)))].append((y, x, 'v'))
                if y + 1 < R:
                    b = reg[y + 1, x]
                    if b >= 0 and b != a and kinds[b] != 'blank':
                        border[tuple(sorted((a, b)))].append((y, x, 'h'))
        adj = collections.defaultdict(set)
        for a, b in border: adj[a].add(b); adj[b].add(a)

        doors = []
        parent = list(range(len(regions)))
        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]; i = parent[i]
            return i
        def add_door(a, b):
            es = border[tuple(sorted((a, b)))]
            # 角を避けて境目のまん中に
            es = sorted(es, key=lambda e: (e[2], e[0], e[1]))
            doors.append(es[len(es) // 2])
            parent[find(a)] = find(b)
        walk = lambda r: kinds[r] in ('corridor', 'room', 'stairs')
        # 1) 通路に面した部屋・階段は、いちばん長く接する通路へ
        for r in range(len(regions)):
            if kinds[r] in ('room', 'stairs'):
                cs = [c for c in adj[r] if kinds[c] == 'corridor']
                if cs:
                    add_door(r, max(cs, key=lambda c: len(border[tuple(sorted((r, c)))])))
        for a, b in list(border):
            if kinds[a] == 'corridor' and kinds[b] == 'corridor' and find(a) != find(b):
                add_door(a, b)
        # 2) 残りは、建物の塊ごとに主な領域(最大の通路、なければ最大の部屋)へつなぐ
        n_fc, fc = cv2.connectedComponents(cellfoot.astype(np.uint8), connectivity=4)
        for k in range(1, n_fc):
            rs = sorted({reg[y, x] for y, x in zip(*np.where(fc == k)) if walk(reg[y, x])})
            if not rs: continue
            cor = [r for r in rs if kinds[r] == 'corridor']
            root = max(cor or rs, key=lambda r: len(regions[r]))
            changed = True
            while changed:
                changed = False
                best = None
                for r in rs:
                    if find(r) == find(root): continue
                    for c in adj[r]:
                        if walk(c) and find(c) == find(root):
                            l = len(border[tuple(sorted((r, c)))])
                            if best is None or l > best[2]: best = (r, c, l)
                if best:
                    add_door(best[0], best[1]); changed = True

        # マス
        cells_out = []
        grid = {}
        for y in range(R):
            for x in range(C):
                t = int(types[y, x])
                c = {'x': x, 'y': y, 'type': t}
                grid[(y, x)] = c
        def setw(y, x, k):
            if (y, x) in grid: grid[(y, x)][k] = True
        for y in range(R):
            for x in range(C):
                if wr[y, x] and x + 1 < C and (types[y, x] or types[y, x + 1]):
                    setw(y, x, 'wallRight'); setw(y, x + 1, 'wallLeft')
                if wb[y, x] and y + 1 < R and (types[y, x] or types[y + 1, x]):
                    setw(y, x, 'wallBottom'); setw(y + 1, x, 'wallTop')
        for y, x, d in doors:
            if d == 'v':
                setw(y, x, 'doorRight'); setw(y, x + 1, 'doorLeft')
            else:
                setw(y, x, 'doorBottom'); setw(y + 1, x, 'doorTop')
        for rid, cells in enumerate(regions):
            if names[rid] and kinds[rid] == 'room':
                full = f'{bname}_{fname}_{names[rid]}'
                for y, x in cells:
                    if types[y, x] == 3: grid[(y, x)]['name'] = full

        # 階段は塊ごとに、建物内での位置を覚えておく（階をまたいで同じ名前にする）
        fy, fx = np.where(cellfoot)
        fb = (fx.min(), fy.min(), fx.max() + 1, fy.max() + 1)
        s_lab_n, s_lab = cv2.connectedComponents((types == 4).astype(np.uint8), connectivity=4)
        groups = []
        for k in range(1, s_lab_n):
            yy, xx = np.where(s_lab == k)
            if len(yy) < 3:
                for y, x in zip(yy, xx): grid[(y, x)]['type'] = 3 if types[y, x] == 4 else grid[(y, x)]['type']
                continue
            rel = ((xx.mean() - fb[0]) / (fb[2] - fb[0]), (yy.mean() - fb[1]) / (fb[3] - fb[1]))
            groups.append((rel, list(zip(yy.tolist(), xx.tolist()))))
            stairs_by_building[bname].append((label, rel))

        results[label] = dict(fl=fl, R=R, C=C, grid=grid, stairs=groups, clip=clip, fb=fb)
        nd = sum(1 for d in doors)
        print(f'{label}: {C}x{R} 領域{len(regions)} 部屋名{sum(1 for n in names if n)} 通路{kinds.count("corridor")} 階段{len(groups)} 扉{nd}')

    # 階段の名前: 同じ建物で位置が近いものを同じ階段とみなす
    stair_names = {}
    for bname, lst in stairs_by_building.items():
        clusters = []
        for label, rel in lst:
            for cl in clusters:
                if abs(cl['x'] - rel[0]) < 0.07 and abs(cl['y'] - rel[1]) < 0.35:
                    cl['m'].append((label, rel)); break
            else:
                clusters.append({'x': rel[0], 'y': rel[1], 'm': [(label, rel)]})
        clusters.sort(key=lambda c: c['x'])
        for i, cl in enumerate(clusters):
            nm = f'{bname}_階段' + ('' if len(clusters) == 1 else chr(ord('A') + i))
            for label, rel in cl['m']:
                stair_names[(label, rel)] = nm

    # 上下の階で共通の階段がないときは、片方の階段を同じ位置に置く
    # （図で階段の線が拾えなかった階。建物の階段はふつう全階で同じ位置にある）
    by_b = collections.defaultdict(list)
    for label, r in results.items():
        by_b[r['fl'][3]].append(label)
    for bname, labels in by_b.items():
        labels.sort(key=lambda l: results[l]['fl'][5])
        for lo, hi in zip(labels, labels[1:]):
            names_of = lambda l: {stair_names[(l, rel)]: rel for rel, _ in results[l]['stairs']}
            nlo, nhi = names_of(lo), names_of(hi)
            if set(nlo) & set(nhi) or not (nlo or nhi):
                continue
            src, dst = (hi, lo) if nhi else (lo, hi)
            nm, rel = sorted(names_of(src).items())[0]
            r = results[dst]; fb = r['fb']; grid = r['grid']
            cx = fb[0] + rel[0] * (fb[2] - fb[0]); cy = fb[1] + rel[1] * (fb[3] - fb[1])
            walk = [(y, x) for (y, x), c in grid.items() if c['type'] in (1, 3)]
            y0, x0 = min(walk, key=lambda p: (p[0] - cy) ** 2 + (p[1] - cx) ** 2)
            cells = [(y, x) for y, x in walk if abs(y - y0) <= 1 and abs(x - x0) <= 1]
            r['stairs'].append((('copy', nm), cells))
            stair_names[(dst, ('copy', nm))] = nm
            print(f'  {dst}: {nm} を {src} の位置から補完')

    for label, r in results.items():
        grid = r['grid']
        for rel, cells in r['stairs']:
            for y, x in cells:
                grid[(y, x)]['type'] = 4
                grid[(y, x)]['name'] = stair_names[(label, rel)]
        write_json(label, r)


def write_json(label, r):
    fl = r['fl']; R, C, grid = r['R'], r['C'], r['grid']
    walkable = lambda c: c['type'] in (1, 3, 4, 5, 6)
    opp = {'top': 'bottom', 'bottom': 'top', 'left': 'right', 'right': 'left'}
    cap = lambda s: s[0].upper() + s[1:]
    nodes = {}
    # ifmap_editor の JsonExporter と同じ規則でノードを作る
    for y in range(R):
        for x in range(C):
            c = grid[(y, x)]
            if not walkable(c): continue
            edges = []
            for dy, dx, d in ((-1, 0, 'top'), (1, 0, 'bottom'), (0, -1, 'left'), (0, 1, 'right')):
                if c.get('wall' + cap(d)) and not c.get('door' + cap(d)): continue
                ny, nx = y + dy, x + dx
                if not (0 <= ny < R and 0 <= nx < C): continue
                n = grid[(ny, nx)]
                if not walkable(n): continue
                o = opp[d]
                if n.get('wall' + cap(o)) and not n.get('door' + cap(o)): continue
                edges.append(f'node_{ny}-{nx}')
            node = {'x': x * 10, 'y': y * 10, 'edges': edges}
            if c.get('name'): node['name'] = c['name']
            if c['type'] == 4: node['isStairs'] = True
            for k in ('doorTop', 'doorBottom', 'doorLeft', 'doorRight', 'wallTop', 'wallBottom', 'wallLeft', 'wallRight'):
                if c.get(k): node[k] = True
            nodes[f'node_{y}-{x}'] = node
    cells = [c for c in grid.values() if c['type'] != 0 or len(c) > 3]
    rooms = collections.defaultdict(list)
    for c in grid.values():
        if c.get('name') and c['type'] not in (5, 10):
            rooms[c['name']].append((c['x'], c['y']))
    room_summary = [{'name': n, 'centerX': sum(p[0] for p in ps) / len(ps) * 10 + 5,
                     'centerY': sum(p[1] for p in ps) / len(ps) * 10 + 5} for n, ps in rooms.items()]
    bg = base64.b64encode(open(f'{WORK}/{label}_bg.png', 'rb').read()).decode()
    nodes['_editorData'] = {'bgImageBase64': bg, 'cells': cells, 'rows': R, 'cols': C, 'rooms': room_summary}
    folder = fl[1]
    os.makedirs(f'{ASSETS}/{folder}', exist_ok=True)
    with open(f'{ASSETS}/{folder}/{label}.json', 'w', encoding='utf-8') as f:
        json.dump(nodes, f, ensure_ascii=False, separators=(',', ':'))


if __name__ == '__main__':
    {'render': render, 'build': build}[sys.argv[1]]()
