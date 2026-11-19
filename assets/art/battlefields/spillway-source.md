# 暗渠分水闸战场图来源

- 原生生成工具：当前可用 `image_gen`；运行时未提供具体模型名；2026-11-07。
- 最终原图：`exec-6f3827ec-a337-4a68-b951-57565f0e859f.png`，1448×1086 RGB，SHA-256 `cf5818b693c4f26a6e6a0daf6db5def8adbbc5a30a6ccaba9b64c82d4517fc94`。原图完整拷贝为 `spillway-v2.png`。
- 迭代底图：`exec-b3a2850a-9594-4144-90db-01096e4ca037.png`，1448×1086 RGB，SHA-256 `c205ca92340ffd9765fe907f9811aa065221e55760064df09be594e326cf1e1a`；第二次原生生成将左侧量位从北岸移到南岸，其他空间布局沿用。
- 参考图一：本项目原创的 `northbank-v2.png`，仅参考暖色赛璐环境画法，不沿用原布局。
- 参考图二：`.tools/spillway-blockout.png`，按 `data/maps.tres` 中 16×12 规则生成的纯色白盒；白盒不打包。
- 用途：战场底图。规则数据决定地格、碰撞、双闸坐标及临桥位置；Godot 叠加棋盘、动态桥、单位和目标标记。

初次原生生成提示词：

> Create ONE original finished 2D tactical battlefield background for Sigils & Oaths, an original East Asian fantasy card-and-grid strategy game. Opaque 4:3 landscape top-down orthographic view matching a logical 16-column x 12-row board. The FIRST reference is this project's already-original northbank art ONLY for clean crisp inked anime environment painting, warm sandstone/terracotta architecture, luminous teal water, sage trees, controlled two-step cel shadows, and material texture. Do not reuse its layout or objects. The SECOND reference is the authoritative geometric blockout for this NEW map. Translate its spatial shapes closely: north quarter a broad ochre gateyard with two separate pale target spots around grid x5 and x10 row3, a low original waterworks intake building at the upper edge; full-width deep teal river band precisely rows4-5, with only TWO existing narrow two-cell-long stone bridges at x3 and x12, both meeting their shore paths. The center river x6-9 MUST remain continuous unobstructed water without any prebuilt crossing because a gameplay card constructs a bridge there. South of river a broad gravel staging ground with two bridge approach roads at x3-4 and x11-12, and central broad command road toward the bottom; small foliage only at four shoulder spots. Preserve clear terrain readability at exact relative locations. Add low distinctive sluice masonry and a few stacked timber bridge supplies near southern shore but never over water. High quality finished native game environment, cohesive original anime cel painting, inviting saturated colors, grounded water engineering. No people, units, moving carts, labels, text, grid lines, runes, logos, UI or borrowed game assets.

最终原生编辑提示词：

> Edit this existing ORIGINAL game battlefield painting with minimal changes. Preserve the exact 4:3 top-down perspective, all colors, texture style, tiled yard, full-width river, two stone bridges at the far left and right, central unbridged open water, north gatehouse, road alignments, trees, sluices, and overall layout exactly. One gameplay objective moved: remove only the left pale circular inlaid target spot on the NORTH yard (around x=5 of 16 columns, y=3 of 12 rows) and seamlessly replace it with ordinary matching sandstone paving. Add a modest clear inlaid measuring-stone ring on the SOUTH yard around x=5 of 16 columns, y=6 of 12 rows, just beside the stacked bridge timber, moving the stack a little to the right if needed. Keep the right/north inlaid circle around x=10,y=3. Thus final art has exactly TWO obvious stand positions, one on south bank and one on north bank. Absolutely no new river crossings, no additional bridges, no text, grid, people, UI, logos, or changes elsewhere. Preserve original anime cel-painted game art style and source resolution.

人工检查：双桥、整段中央未架桥河面、南岸量位、北岸闸位与南岸道路清楚；原生格线与点击命中另由地图测试核验。
