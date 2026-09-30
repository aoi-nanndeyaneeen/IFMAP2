# 構内図(PDF 1枚目)の建物名を最上位にした、場所の階層の索引を作る。
#   豊田高専 / 区域 / 建物 / 階 / 部屋
# 出力: ifmap/assets/campus_index.json
import sys, os, json, unicodedata
sys.path.insert(0, os.path.dirname(__file__))
from floors import FLOORS

ASSETS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../ifmap/assets'))

# 構内図に書かれている建物・施設（改行で割れた名前はつなぎ直した）。
# 区域ごとに並べる。maps はその建物の中を描いたフロアのラベル。
AREAS = [
    ('校舎', [
        '一般管理棟', '第1講義棟', '第2講義棟', '新講義棟', '機械工学科棟', '電気・電子システム工学科棟',
        '情報工学科棟', '環境都市工学科棟', '建築学科棟', '専攻科棟', '図書館', '豊田記念会館',
        '創造工房棟', 'ものづくりセンター', '社会連携共創センター', '材料・構造物疲労試験センター']),
    ('学寮', ['友志寮', '輝志寮', '栄志寮', '高志寮', '明志寮', '創志寮', '大志寮']),
    ('福利厚生施設', ['福利施設(食堂)', '福利厚生会館(学生課)', '合宿研修所']),
    ('体育施設', ['第1体育館', '第2体育館', '武道場', '卓球場', '弓道場', '的場', 'プール',
               '陸上競技場', '野球場', 'テニスコート', 'ハンドボールコート']),
    ('その他', ['正門', '守衛室', '第1駐車場', '第2駐車場', '駐輪場', '車庫', '屋外便所', 'ボイラー室',
             '電気室', '廃水処理施設', '倉庫', '器具庫', '噴水', '雙清池']),
]

# 構内図の建物名 → 中の図を作った建物（MapSection.building）
MAP_BUILDING = {
    '友志寮': '友志寮', '輝志寮': '輝志寮', '栄志寮': '栄志寮', '高志寮': '高志寮',
    '明志寮': '明志寮', '創志寮': '創志寮', '大志寮': '大志寮',
    '福利施設(食堂)': '福利厚生会館・食堂', '福利厚生会館(学生課)': '福利厚生会館・食堂',
    '合宿研修所': '合宿研修施設',
    '第1体育館': '第1体育館', '第2体育館': '第2体育館',
    '武道場': '武道場・卓球場', '卓球場': '武道場・卓球場', '弓道場': '弓道場',
}

# 以前からある本棟の地図。部屋名が棟名で始まるものだけその棟に振り分ける
NITTC = [('NITTC_1F', '1F'), ('NITTC_2F', '2F'), ('NITTC_3F', '3F')]


def norm(s):
    return unicodedata.normalize('NFKC', s)


def rooms_of(folder, label):
    d = json.load(open(f'{ASSETS}/{folder}/{label}.json', encoding='utf-8'))
    out = []
    for r in d['_editorData']['rooms']:
        out.append(r['name'])
    return sorted(set(out))


def main():
    floors_by_building = {}
    for fl in FLOORS:
        label, folder, zone, bname, fname = fl[:5]
        rooms = []
        for full in rooms_of(folder, label):
            parts = full.split('_')
            # 建物_階_部屋 / 階段は 建物_階段X
            short = parts[-1] if len(parts) >= 3 else parts[-1]
            rooms.append({'name': short, 'id': full, 'isStairs': '階段' in parts[-1] and len(parts) == 2})
        floors_by_building.setdefault(bname, []).append({'floor': fname, 'label': label, 'rooms': rooms})

    nittc_rooms = {label: rooms_of('NITTC', label) for label, _ in NITTC}

    areas = []
    for area, names in AREAS:
        bs = []
        for n in names:
            b = {'name': n}
            mb = MAP_BUILDING.get(n)
            if mb:
                b['mapBuilding'] = mb
                b['floors'] = floors_by_building[mb]
            elif area == '校舎':
                fls = []
                for label, fname in NITTC:
                    rs = [{'name': norm(r)[len(norm(n)):].lstrip('_') or r, 'id': r}
                          for r in nittc_rooms[label] if norm(r).startswith(norm(n))]
                    if rs:
                        fls.append({'floor': fname, 'label': label, 'rooms': rs})
                if fls:
                    b['floors'] = fls
            bs.append(b)
        areas.append({'name': area, 'buildings': bs})

    # 本棟の地図で、どの棟の部屋か名前からは分からないもの
    claimed = {r['id'] for a in areas for b in a['buildings'] for f in b.get('floors', []) for r in f['rooms']}
    unassigned = [{'floor': fname, 'label': label,
                   'rooms': [{'name': r, 'id': r} for r in nittc_rooms[label] if r not in claimed]}
                  for label, fname in NITTC]

    index = {
        'campus': '豊田高専',
        'note': '場所の階層: 区域 / 建物 / 階 / 部屋。id はマップJSONのノード名(name)と同じ。'
                'label は ifmap の MapSection.label。',
        'areas': areas,
        'unassigned': {'name': '本棟（棟の特定できない部屋）', 'floors': unassigned},
    }
    with open(f'{ASSETS}/campus_index.json', 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
    n = sum(len(fl['rooms']) for a in areas for b in a['buildings'] for fl in b.get('floors', []))
    print('区域', len(areas), '建物', sum(len(a['buildings']) for a in areas), '部屋', n)


if __name__ == '__main__':
    main()
