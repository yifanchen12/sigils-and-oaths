# 纹章与誓约 / Sigils & Oaths

Godot 4.7.2 原创单机卡牌战棋，当前 0.11.0 开发版。通过卡牌召唤部队，在友军身旁延伸阵线，以地形、天气和指挥官技能争夺优势。

## 运行

双击 `play.cmd`，先导入资源，再用 `.tools/godot/` 的便携 Godot 启动。双击 `edit.cmd` 修改工程，或在 Godot 4.7.2 导入 `project.godot`。官方引擎来源见 `docs/engine-download.json`，工程需位于本地可写目录。

## 内容

| 项目 | 当前实现 |
| --- | --- |
| 地图 | 六张完整绘制的原创战场：暮林边境、双桥河谷、日陨遗城、断脊隘口、古堡棋庭、碧潮港湾；12×10 手工布局（原面积的2.5倍） |
| 英雄 | 艾琳：防护光环与赐福；维洛：火焰强化与裁决；赛菈：林地恢复与群体治疗 |
| 卡牌 | 24 种可组牌，另有后手专属战术先机；全部有原创插画 |
| 套牌 | 三套30张预组牌（各18部队）；一个可本地保存的自定义套牌槽 |
| 反制 | 击退、定身、驱散护盾、指挥官换位、再次攻击、清除天气 |
| 地理 | 森林、山地、军道、河流、桥梁、高地、遗迹、工事 |
| 环境 | 暴雨、浓雾、烈日、寒潮；影响双方，持续 4 次回合交接，可替换或驱散 |
| 界面 | 角色立绘主视觉战前页、真实地形缩略图、双方生命条/法力晶石、图像手牌、分类组牌与费用曲线 |
| 表现 | 原创日式赛璐璐人物与全身棋子（成年角色，正常比例），法术插画、连续地貌、路径预览、伤害拆解、移动/受击/天气效果 |

## 操作与规则

- 点击部队牌，再点击青框空格部署；可部署在任意友军上下左右相邻的可通行空格，指挥官和新兵都能作为支点。每方最多 6 支普通部队。
- 点击己方部队后，蓝点为移动、赤框为攻击。悬停可攻击敌军时，人物详情显示双方预计剩余生命、反击和生效修正；棋子生命条的浅金段为预计损失。已计入护盾，目标阵亡或射程不足时不反击。
- 新兵下个己方回合行动。通常每回合移动一次、攻击一次，攻击后不能移动。存活且射程足够的目标反击一次。
- 步兵克枪兵、枪兵克骑兵、骑兵克步兵，伤害 +2。枪兵原地防御 +1；骑兵实际移动至少 3 格后攻击 +1；弓手近战 -1；法师无视 1 防御。
- 森林/高地/工事加防御；高地强化远程和对低地伤害；骑兵从军道或桥梁出发移动 +1；遗迹每个己方回合恢复驻守者 1 生命。
- 指挥官 20 生命，不能主动移动，可攻击射程内敌军或通过换位改变位置；击败敌方指挥官获胜。
- 先手起手 4 张并在回合开始抽 1；后手起手 5 张，额外获得 0 费临时法力牌，首次回合仍正常抽牌。每回合法力上限 +1 并回满，最多 10。每个行动回合 90 秒，超时自动结束。
- 手牌上限 8，超出进入弃牌。弃牌不洗回；空牌库抽牌受到递增疲劳伤害。护盾先抵挡伤害，法术无视防御但不穿护盾。
- 全局天气、抽牌、临时法力牌点击即用；目标型法术限定友军3格内、法师4格内，点击高亮目标；英雄主动技能限制在指挥官附近。英雄技能在左侧按钮，详情含费用与冷却。
- 右键/Esc 取消；空格结束回合；1–8 选牌；方向键与 Enter 操作棋盘。
- 默认展开战场，底部保留图像手牌，地图上方保留技能/结束回合按钮；Tab 切换侧栏布局。滚轮或 +/− 缩放，中键/Alt+左键拖动，Home 适配全图。
- G 或“地形网格”按钮查看精确格子与地形标记；平时隐藏网格，选择/悬停仍显示相应高亮。造路与筑垒会实时替换对应格子的地形外观。
- 全图视野两侧显示人物/卡牌详情与公开战况；悬停单位或紧凑手牌可查看大图。缩放后空间不足会自动隐藏，不遮挡地图。
- 图鉴/规则/战前部署打开时 AI 和本地回合计时暂停；战斗中更换地图、英雄或套牌会开始新对局。
- 战前菜单“编辑军势”可复制预组牌并增减卡牌；30张、每种最多4张、至少1张部队。保存后选择自定义再出征；当前对局保持原套牌。重启后恢复，损坏文件尝试上次有效备份。自定义己方对阵均衡AI。

完整规则在游戏“玩法说明”和 `scripts/rules_text.gd`。棋子左下为攻击、右下为生命，金弧为护盾；Z 为新兵，锁为定身。悬停或开启网格后可见地形标记，+ 为恢复遗迹。

## 开发与验证

`data/cards.tres`、`maps.tres`、`heroes.tres`、`decks.tres` 是 Resource 配置；`scripts/battle.gd` 为规则唯一入口，UI 和 AI 都提交相同的合法动作。AI 只用公开棋盘及自己的手牌，使用加权地形寻路。`main.gd`/`main.tscn` 管理原生 UI 和调度，表现层独立于规则。

`assets/art/manifest.json` 记录原创生成素材的来源、图集顺序与处理；`prompts-cel-spells.json`、`prompt-tactics-cel-2-retry.txt` 保存当前赛璐璐法术完整提示词，PNG 原图未改像素，裁切由 Godot 实时完成。

地图原图位于 `assets/art/battlefields/`，`sources.json` 记录实际采用的生成版本、编辑父图与完整提示词路径。地图位置导图来自真实规则数据，核对记录见 `docs/map-art-audit.md`；`tools/export_map_guides.gd` / `export_map_audits.gd` 可重新导出导图与核对图。

```powershell
$tacticsGodot = '.\.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
& $tacticsGodot --headless --path . --editor --quit --log-file import.log
& $tacticsGodot --headless --path . --script res://tests/test_battle.gd --log-file rules-test.log
& $tacticsGodot --headless --path . --script res://tests/test_evolution.gd --log-file evolution-test.log
& $tacticsGodot --headless --path . --script res://tests/test_tactics.gd --log-file tactics-test.log
& $tacticsGodot --headless --path . --script res://tests/test_casting_clock.gd --log-file casting-clock-test.log
& $tacticsGodot --headless --path . --script res://tests/test_opponent.gd --log-file opponent-test.log
& $tacticsGodot --headless --path . --script res://tests/test_deck_store.gd --log-file deck-store-test.log
& $tacticsGodot --path . --script res://tests/test_forecast.gd --resolution 1440x1000 --audio-driver Dummy --log-file forecast-test.log
& $tacticsGodot --path . --script res://tests/test_ui.gd --resolution 1440x1000 --audio-driver Dummy --log-file ui-test.log
& $tacticsGodot --path . --script res://tests/test_map_art.gd --resolution 1440x1000 --audio-driver Dummy --log-file map-art-test.log -- --complete
```

检查覆盖卡牌区域唯一性、非法操作原子性、部署、地形路径、英雄/天气/战术与完整 AI 对局。图形测试发送真实视口鼠标移动和点击，截图见 `docs/screenshots/`，结果见 `docs/validation.md`。

当前面向 Windows 桌面鼠标/键盘。远程不检查视线；尚未实现联机和发行导出。自定义套牌为单个本地槽，存储于Godot的user://custom_deck.json；AI诊断不等同于竞技平衡。未使用参考游戏的角色、卡面、音频或其他素材。
