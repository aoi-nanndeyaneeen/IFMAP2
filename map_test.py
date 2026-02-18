import cv2
import math
import heapq
import json

# ==========================================
# 1. JSONデータの読み込み
# ==========================================
with open("map_data.json", "r", encoding="utf-8") as f:
    map_data = json.load(f)

nodes = map_data["nodes"]
edges = map_data["edges"]

# ==========================================
# 2. 距離計算とダイクストラ法（変更なし）
# ==========================================
def get_distance(node1, node2):
    x1, y1 = nodes[node1]["x"], nodes[node1]["y"]
    x2, y2 = nodes[node2]["x"], nodes[node2]["y"]
    return math.hypot(x2 - x1, y2 - y1)

def find_shortest_path(start, goal):
    queue = []
    heapq.heappush(queue, (0, start))
    distances = {node: float('inf') for node in nodes}
    distances[start] = 0
    previous_nodes = {node: None for node in nodes}

    while queue:
        current_distance, current_node = heapq.heappop(queue)

        if current_node == goal:
            break

        if current_distance > distances[current_node]:
            continue

        for neighbor in edges[current_node]:
            distance = current_distance + get_distance(current_node, neighbor)
            if distance < distances[neighbor]:
                distances[neighbor] = distance
                previous_nodes[neighbor] = current_node
                heapq.heappush(queue, (distance, neighbor))

    path = []
    current = goal
    while current is not None:
        path.append(current)
        current = previous_nodes[current]
    path.reverse()
    
    return path if path[0] == start else []

# ==========================================
# 3. アプリの状態管理（グローバル変数）
# ==========================================
start_node = None # 出発地（1回目のクリックで決定）
goal_node = None  # 目的地（2回目のクリックで決定）

image_path = "map.png"
original_img = cv2.imread(image_path)
if original_img is None:
    print("画像が読み込めませんでした。")
    exit()

display_img = original_img.copy()

# ==========================================
# 4. クリックされた場所から一番近いノードを探す関数
# ==========================================
def find_nearest_node(click_x, click_y):
    min_dist = float('inf')
    nearest_node_id = None
    
    for node_id, data in nodes.items():
        # クリックした場所と各ノードの距離を計算
        dist = math.hypot(data["x"] - click_x, data["y"] - click_y)
        if dist < min_dist:
            min_dist = dist
            nearest_node_id = node_id
            
    # クリックした場所から半径50ピクセル以内ならそのノードを選択したとみなす
    if min_dist < 50:
        return nearest_node_id
    return None

# ==========================================
# 5. マウスクリック時の処理（イベントコールバック）
# ==========================================
def mouse_callback(event, x, y, flags, param):
    global start_node, goal_node
    
    # 左クリックされたら
    if event == cv2.EVENT_LBUTTONDOWN:
        clicked_node = find_nearest_node(x, y)
        
        if clicked_node is None:
            return # 何もないところをクリックした場合は無視
            
        if start_node is None:
            # 1回目のクリック：出発地をセット
            start_node = clicked_node
            print(f"出発地を選択: {nodes[start_node]['name']}")
        elif goal_node is None:
            # 2回目のクリック：目的地をセット
            goal_node = clicked_node
            print(f"目的地を選択: {nodes[goal_node]['name']}")
        else:
            # 3回目以降のクリック：リセットして新しい出発地にする
            start_node = clicked_node
            goal_node = None
            print(f"リセット。新しい出発地: {nodes[start_node]['name']}")
            
        update_display() # 画面を描画し直す

# ==========================================
# 6. 画面の描画更新関数
# ==========================================
def update_display():
    global display_img
    display_img = original_img.copy() # まず画像をまっさらに戻す
    
    # クリックできるポイント（ノード）をグレーの小さな丸で表示しておく
    for node_id, data in nodes.items():
        cv2.circle(display_img, (data["x"], data["y"]), 5, (200, 200, 200), -1)

    # 出発地が選ばれていれば赤丸を描画
    if start_node:
        cv2.circle(display_img, (nodes[start_node]["x"], nodes[start_node]["y"]), 10, (0, 0, 255), -1)
        
    # 目的地まで選ばれていればルート計算して描画
    if start_node and goal_node:
        cv2.circle(display_img, (nodes[goal_node]["x"], nodes[goal_node]["y"]), 10, (255, 0, 0), -1)
        
        path = find_shortest_path(start_node, goal_node)
        if len(path) > 1:
            for i in range(len(path) - 1):
                n1 = path[i]
                n2 = path[i+1]
                pt1 = (nodes[n1]["x"], nodes[n1]["y"])
                pt2 = (nodes[n2]["x"], nodes[n2]["y"])
                # 緑の線と黄色の中継ポイント
                cv2.line(display_img, pt1, pt2, (0, 255, 0), 5)
                cv2.circle(display_img, pt1, 5, (0, 255, 255), -1)

    # ウィンドウに反映
    cv2.imshow("infacilityMAP", display_img)

# ==========================================
# 7. メイン実行部分
# ==========================================
cv2.namedWindow("infacilityMAP")
cv2.setMouseCallback("infacilityMAP", mouse_callback) # マウス操作を検知するようにセット

update_display() # 最初の描画
print("マップ上のグレーの点をクリックしてください。（1回目:出発地, 2回目:目的地）")

cv2.waitKey(0)
cv2.destroyAllWindows()