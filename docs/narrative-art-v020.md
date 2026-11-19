# 第四章场景与对白界面 · 0.20.0-dev

第四章改用七张专门绘制的剧情背景，区分港口锁舱与救援后、诊室白天与夜间、炉坊、泵房接管前与接管后。画面为原创动画风格场景，文字、立绘和按钮由 Godot 绘制。前三章仍使用原有地图背景；九名同伴沿用现有战装立绘，尚未制作生活姿态、表情差分或新增配角肖像。

| 场景编号 | 剧情位置与状态 | 原生截图 |
| --- | --- | --- |
| `scene_harbor_locked` | 东岸交涉与救援战前；舱门锁住、跳板移开 | [锁舱](screenshots/v020-harbor-locked.png) |
| `scene_harbor_open` | 救援战后与安置选择；舱门打开、跳板接岸 | [离船](screenshots/v020-harbor-open.png) |
| `scene_clinic_day` | 货棚诊室、安置后的照料 | [洛恩对白](screenshots/v020-clinic-dialogue.png) |
| `scene_clinic_night` | 章末夜间；修门后的诊室 | [夜间](screenshots/v020-clinic-night.png) |
| `scene_foundry` | 炉坊交涉、欠饷选择、泵房节点的前四段 | [小窗口选择](screenshots/v020-foundry-choice-small.png) |
| `scene_pump_closed` | `c04.pump.05`起抵达泵房、交战前 | [铁栅关闭](screenshots/v020-pump-closed.png) |
| `scene_pump_open` | 泵房胜利后，本地工匠接管 | [接管后](screenshots/v020-pump-open.png) |

场景是叙事插画，没有增加水位、机械模拟、开锁或建筑交互玩法；夜间页也不是所有人物同时身在诊室的证明。港口两战仍在原12×10棋盘上进行。现有正文、稳定文本ID、选项和战果条件均未改变，只补入节点及段落背景编号。

## 阅读布局

场景铺满窗口，主体留在对白框上方；同伴立绘放大，下半身自然延伸到深蓝阅读面板后。旁白、配角和选择页不显示无关角色。回看隐藏立绘并展开阅读区，保留原有历史内容与滚动。工具栏、选项、保存与键盘操作保持原有功能。

放大后发现原三人图集的中间格带入相邻旗帜/披风，已为芙蕾和维洛加入独立运行时裁切；不改源PNG和战斗图集。普通对白仍使用单一战装姿态，这不等于已经完成剧情角色演出。

## 来源与验证

七张1536×1024 PNG均由原生image_gen生成并原字节保存。首次港口草稿误把跳板接到船上，经工具编辑修正才采用；开舱、夜间诊室、关闭泵房均由对应已采用场景编辑，保持前后构图。完整实际提示词、参考父图、SHA-256、尺寸与采用记录见[来源](../assets/art/narrative/sources.json)和[提示词](../assets/art/narrative/prompts.json)。源文件与生成输出哈希一致，导入开启mipmap、剧情页使用线性采样。机械结构仅作背景表达，不作为工程图验证。

- 5,667项相关模型检查通过：正文图、512条累计路线、跨章/会话/存储，以及段落背景覆盖、旧游标与旧索引恢复、非法背景值和跨节点不串背景。
- Windows Compatibility原生界面3,455项检查通过，覆盖356段对白、4段章末、真实跨章/选项/出征/保存继续按钮、1008×700小窗口及展开回看。独立九角色显示检查10项通过，并逐张查看实机画面。
- 本页链接的场景截图、安置页、回看页和港口战斗入场截图已逐张查看。测试通过叙事战果夹具到达后续章节；港口只验证正式入场，没有用这些画面宣称七战连续通关。
- 章节源哈希随本轮通过结果更新到[native记录](narrative-native-ui.json)。四章正文仍22,524汉字，连档案28,082字；本轮没有新增正文，不把提示词或说明文档计入十万字目标。

[展开回看](screenshots/v020-backlog.png) · [安置选择](screenshots/v020-shelter.png) · [实际泵房战斗入场](screenshots/v020-pump-battle-opening.png)

```powershell
godot --headless --path . --editor --import
godot --headless --path . --script tests/test_story_cursor.gd
godot --headless --path . --script tests/test_chapter_four.gd
godot --path . --audio-driver Dummy --script tests/test_campaign_ui.gd
python tools/audit_narrative.py --output docs/narrative-audit.json
```
