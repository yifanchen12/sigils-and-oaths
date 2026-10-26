# 验证记录

2026-10-25，Godot 4.7.2 stable official Windows x64，Compatibility/OpenGL 3.3，RTX 4060 Laptop GPU。

## 0.12.2 近战人物动作姿态（2026-10-26）

- 步兵、枪兵、骑兵各三帧原创姿态，普攻与反击按独立时间线播放，援护使用枪兵举盾帧。图像按对手方向翻转，血条/状态文字保持正向。规则与数据没有改动。
- 三张2172×724原始PNG与生成输出SHA-256一致，alpha范围0–255。生成图并非精确等宽网格，Godot按透明间隙切片，使用等比例与测量脚底锚点；无像素修改。来源、父图与逐字提示词见assets/art/actions/sources.json。
- `test_action_poses.gd`：最终Windows常速160项通过（action-poses-final-complete.log），首次成功原生录制也通过160项。检查九帧独立/非空/透明、边缘无裁切或串图、锚点、主攻/反击关键时间点、正常目标/援护、左右出手、规则状态与RNG不变、完成后归位、重开清理、致死无反击与有限淡出。先期常速三兵种136项通过（action-poses-final.log），后续增加左右与死亡用例后为160项。
- 整体Windows界面257项通过（ui-action-poses.log），法术/胜负反馈56项通过（feedback-action-poses.log）；本轮最终实机检查共473项。另有接入初期无窗口普攻预估109项通过（action-poses-forecast.log），不将其当作113项图形预估测试或完整AI对局重跑。
- 原生导入/加载成功（import-action-poses-final.log）；项目引用检查198文件，0错误、0警告。一次mipmap试验录制超时，保留原无mipmap导入设置并完成常速160项复测；成功MP4来自试验前相同的无mipmap设置。失败尝试已排除，不计为通过记录。
- Godot原生图集对照图melee-pose-gallery.png及实机姿态截图已查看。原生Movie Maker录制1114帧/60FPS、18.57秒，导出H.264/yuv420p MP4约2.3MB（screenshots/melee-poses.mp4）。这是一组关键姿态动画，尚不是完整行走循环或独立全屏战斗过场；远程/指挥官尚未制作新动作图。

## 0.12.1 数值预估与终结一击（2026-10-26）

- 未改battle.gd或data/规则配置。新增EffectForecast只读展示数值型卡牌、英雄及部队技能：火焰伤害、范围溅射、治疗上限、护盾替换/叠加、驱散与击退。距离、法力、行动状态和合法目标仍取自Battle；范围名单带棋盘坐标，治疗生命条显示绿色预估段，护盾单独标注增减。
- 只读预估134项通过（effect-forecast-final.log）：逐项应用真实action核对生命/护盾/位移，包含三种天气、指挥官火焰牌被动已用/未用、法师技能不消费该被动、工事不减法术伤害、治疗/护盾上限、五格溅射排除友军与范围外目标、受阻击退、驱散与非法目标。预估与格式化不修改单位、玩家、地形、RNG或战报。
- Windows反馈专项56项通过（feedback-polish-final.log）：真实鼠标/Q键预估与出牌一致；取消清空增益条且不扣费；菜单清理表现；范围名单可读；治疗、防护、单体火焰和范围火焰采用不同原生效果，施法起点取合法覆盖友军。
- 胜负仍在规则动作中立即结算。BoardView的有限presentation_remaining只决定何时展示面板，不使用会影响新对局的延迟回调。覆盖普通攻击和法术最后一击、等待期间不重复扣血/推进计时、重开取消旧战果。
- 原有UI257项（ui-feedback-polish.log）、普通攻击预估113项（forecast-feedback-polish.log）、六技能窗口51项（unit-skills-ui-polish.log）均通过。本轮相关检查共611项；没有把0.12的57场规则AI对局当作本轮重跑。
- 两侧人物卡改用原生聚焦裁切，面板降低高度时仍保留脸部；源美术未改像素。已查看治疗、群体预估、范围命中、最终击破前/胜利后截图。
- Godot原生Movie Maker录制1180帧/60FPS，约19.7秒，51项录制模式检查通过（feedback-polish-movie-final.log，跳过取消重选/菜单的5项）；FFmpeg转为H.264/yuv420p MP4，约1.94MB，路径screenshots/spell-feedback.mp4。录制展示预估、治疗/护盾/火环与最后一击完整流程。
- 最终资源导入（import-feedback-polish-final.log）及七份通过日志均无ERROR或SCRIPT ERROR。引用检查185文件，0错误、0警告；新增截图导入前为173文件。启动、原规则和原图源文件保持原有接口。

## 0.12 六兵种技能与战斗动画（2026-10-26）

- 用户已批准六技能：步兵护盾、枪兵主动援护、骑兵再机动、弓手精准射击、法师星火、医师急救。均1法力、每单位每回合一次、新兵禁用；除骑兵外结束移动与攻击。实现范围与接口见plans/unit-skills-and-combat-animation.md。
- 部队技能54项通过（unit-skills-final.log）：六种效果、精确费用、行动消耗、非法输入原子性、法力/新兵限制、骑兵加权路程与冲锋、雾天射程、天气火焰与护盾、治疗上限、自疗、援护期限/四邻格/定身/多个守卫/指挥官/阵亡、法术绕过、无溢出与实际反击预估。
- 新增Windows技能窗口51项通过（unit-skills-ui-complete-final.log）：真实鼠标和Q键覆盖六技能、选目标/取消、守卫承伤与生命条预估、技能加伤、近战克制与反击、骑兵移动表现、动画结束不修改单位/玩家/地形/RNG/战报、重开清理、两种布局和1008×700/1440×1000尺寸。窗口坐标以Godot逻辑画布核对，未把缩放后的物理窗口尺寸误当作控件坐标。
- 原有Windows UI257项通过（ui-unit-skills-fixed.log），预估113项通过（forecast-unit-skills.log）。增加技能栏后曾导致右侧战况卡高度不足，现按棋盘高度调整肖像区；场景释放时悬停回调增加退出保护。首轮失败日志ui-unit-skills.log仅作诊断。新增测试的条件数组曾失去Array[Vector2i]类型，改用Array后完整51项通过，旧unit-skills-ui-complete.log不计通过。
- 本轮规则76项/12场AI对局、地形英雄127项/36场、战术65项/9场、施法计时28项、自定义套牌39项和AI场景10项全部通过：battle-unit-skills.log、evolution-unit-skills.log、tactics-unit-skills.log、casting-unit-skills.log、deck-unit-skills.log、opponent-unit-skills.log。不是沿用旧版数字。
- 战斗规则仍即时且只结算一次；普通攻击与精准射击使用同一实际守卫选择和反击计算，UI/AI读取相同forecast。棋子按动作前快照展示出手、命中和反击，阵亡者短暂淡出；动画不更改真实位置。援护由守卫原位判断反击射程，可能无法反击，预估已明确。
- 动画为现有静态角色图的棋盘内突进/接应与原生特效：箭矢、法术光弹、斩击、盾形格挡、克制文字和飘字。尚不是逐帧角色动作或独立战斗过场；未生成新的动作美术。
- Godot原生Movie Maker录制997帧/60FPS，约16.6秒，47项录制模式检查通过（combat-movie.log；录制模式跳过改变窗口大小的4项）。FFmpeg转为H.264/yuv420p MP4约1.64MB，未剪改源美术。演示docs/screenshots/unit-skills-combat.mp4；已查看录制帧与援护预估、近战突进实机截图。
- 最终工程引用检查169文件，0错误、0警告；新增截图导入前为159文件。最终import-unit-skills-complete.log及以上通过日志检查无ERROR或SCRIPT ERROR。较早import-unit-skills.log有沙箱用户目录错误及AI脚本函数插入位置错误，修正后import-unit-skills-ui.log正常；旧日志不计通过。

## 0.11 完整绘制战场（2026-10-26）

- 六张12×10地图均接入完整原创绘制图，战前缩略图同步；默认隐藏网格，G/按钮查看精确地形，水面保留原生动态涟漪。地图PNG保留原样，导入启用mipmaps，缩放/拖动仍使用既有坐标转换。
- 地图专项59项通过（map-art-v011.log，完整素材模式）：六图存在/比例、原始地形对比、动态覆盖/恢复、网格按钮与G同步、菜单热键屏蔽、合法连续增援后筑垒、真实造路及缩放后坐标。覆盖表现层不修改单位、玩家、地形与RNG。
- 原有Windows UI257项通过（ui-v011.log），战斗预估113项通过（forecast-v011.log）。本轮未改规则；battle.gd与maps/cards/heroes/decks.tres对0.10.1检查点逐字节校验相同，没有把历史规则/模拟对局记录当作本轮重跑。
- 六张规则叠图已人工查看；实机查看森林中盘、港湾及遗城，核对部队/数值对比、道路、桥梁与关键地貌。修正森林外缘额外障碍、河谷南岸水格及山隘G10额外高台。详见map-art-audit.md；自然轮廓允许在格边产生树冠/投影，不宣称逐像素重合。
- 工程引用检查145文件，0错误、0警告。最终导入、地图、界面和预估日志均未发现ERROR或SCRIPT ERROR。
- 资产清单记录六图实际采用版本、编辑父图、导图与完整提示词；源文件SHA-256与原生imagegen输出相同。取消的早期长调用未计为交付。
- 检查点.checkpoints/v0.11-illustrated-battlefields.zip；旧0.10.1与0.10检查点保留。

## 0.10.1 战斗预估（2026-10-26）

- 上次额度中断时尚未运行的预估改动现已补验。首个测试夹具因Array未显式使用Array[Dictionary]而失败，已修正并加入30秒超时；forecast-resume.log仅为修正前诊断。
- 人物详情显示敌我预计剩余生命、生命损失、实际生效的伤害修正及不反击原因；隐藏+0项。常规/展开布局共用内容，底部保留精简提示；两名棋子的浅金生命段表示预计损失。
- Forecast113项通过（forecast-final.log）：13种场景逐一对比真实apply_action的目标/攻击者生命损失，覆盖护盾吸收、击杀、远程安全攻击、三角克制、冲锋、近战弓手、法师穿透、高地、工事、浓雾与寒潮森林。检查预估不修改单位、玩家、RNG与战报。
- 真实窗口覆盖菜单暂停/恢复、取消、刷新、两种布局与不遮挡地图。原有Windows交互257项通过（ui-forecast-final.log）；两份最终日志均无ERROR或SCRIPT ERROR。
- 规则模型battle.gd未改。实际截图attack-forecast.png、attack-forecast-terrain.png已查看。接口和验收见plans/combat-forecast.md。
- 独立检查点.checkpoints/v0.10.1-combat-forecast.zip；保留0.10界面版供回退。

## 0.10 游戏界面与插画统一

- 战前页重做为角色立绘主视觉与作战准备双栏；三指挥官选择、六张真实地形预览、套牌、图鉴、编辑军势和出征保持原有信号。
- 两种战斗布局统一双方头像、生命条、十槽法力晶石（区分未解锁/已花费/可用）与精确法力数字，以及最后15秒变红的倒计时条。菜单入口、技能、计时与结束回合可见。常规详细模式保留情报和战报，移除重复配置顶栏，将空间留给地图。
- 两种模式都使用原生绘制图像手牌；费用菱形、职业徽记、象牙白铭牌、选中描边及不足费用遮罩共用CardView。悬停卡面0.14秒平滑抬起，指挥官切换0.18秒淡入。紧凑卡面重新对准人物脸部，快捷键1–8可见。组牌与图鉴复用卡框。
- 组牌页新增费用曲线、分类筛选和套牌摘要。257项Windows真实窗口交互通过，日志ui-v010-unified-fixed.log，覆盖1440×1000、1008×700、1920×1080，新增三位指挥官实际点击与淡入完成、六地图预览选择、部队筛选/恢复全部及图像卡面边界检查。此前两轮232/243项亦通过，最终日志无ERROR或SCRIPT ERROR。
- 统一顶栏的初次实现将玩法与战前入口留在隐藏容器，ui-v010-unified.log捕获失败；现已将原控件迁入公共工具栏，保留原有焦点/信号与鼠标路径。最终257项通过，失败日志仅作诊断。
- 基础战斗76项（12场完整AI对局）、施法/计时28项、自定义套牌39项回归通过：battle-v010.log、casting-v010.log、deck-v010.log。规则模型没有修改。
- 6张三格赛璐璐法术/天气/战术图集及独立军道插画替换旧厚涂；菜单背景换为明亮动画风河谷城堡。全部源PNG完整保留，文字、费用、曲线、地图缩略图和HUD由Godot原生绘制。manifest记录源图和实际提示词。
- 实际查看war-council.png、expanded-battle.png、full-hand.png、deck-editor.png与图鉴；不是概念稿。检查点.checkpoints/v0.10-interface-cel-cards.zip。

## 0.9 自定义套牌

- DeckStore39项通过，包含两种自定义套牌（其中一套仅1张部队）的完整AI对局和卡牌区域唯一性。跨进程写入1项、全新进程读取并启动主界面3项通过，确认卡牌数量及战前菜单选项恢复。
- 基础76/演进127/战术65项回归通过，完整AI对局12/36/9场。Windows UI232项通过，日志ui-custom-deck-fixed.log。测试使用独立res://.tools/路径，未覆盖玩家user://套牌。
- UI覆盖：24种可组牌、排除后手先机、实际鼠标增减、29张禁用保存、4张上限、保存后下局选用、现有对局状态保持、复制预组牌、取消草稿与重新读取。
- 保存拒绝负数/小数/非有限值/布尔/未知牌、未来版本与无效套牌；有效旧文件保留备份，损坏主文件恢复备份，写入失败返回错误。每场独立套牌快照，不修改共享Resource。
- 组牌弹窗初始自动换行曾撑大窗口，等待布局后恢复目标尺寸；嵌入Window鼠标通过父视口坐标注入。修正前日志import-custom-deck-ui.log、ui-custom-deck-first.log保留诊断，最终通过日志不含ERROR或SCRIPT ERROR。
- 截图deck-editor.png，1100×820，实际查看卡面、增减按钮、数量与保存入口。接口与边界见plans/custom-deck.md。

## 0.8 站位与抽牌判断

- 基础76、演进127、战术65、施法/计时28项通过，分别完成12/36/9场完整对局。新增AI场景10项通过：弓手先拉开再攻击且不受近战反击、立即击杀指挥官优先、医师靠近伤兵、抽牌疲劳安全、决策不修改状态、不依赖敌方隐藏手牌/牌序。
- Windows UI217项通过；引用检查93文件无错误/警告。最终日志battle-v08-positioning.log、evolution-v08-positioning.log、tactics-v08-positioning.log、casting_clock-v08-positioning.log、opponent-positioning.log、ui-v08-layout-settle.log。
- 敌方主动技能效果、距离与被动在展开战场中可读。初次容器宽度计算完成后才检查高度，修复过早隐藏详情卡；最终UI日志无ERROR或SCRIPT ERROR。ui-v08-readable-skills.log保留为修正前失败证据，不属于通过版本。
- 同组72场镜像诊断完成，先手32胜；三英雄各48场，艾琳28胜、维洛26胜、赛菈18胜。报告balance-v08-positioning.json。对局回合中位数由32降至30，最长均60；以回合交接结束的对局由19降至16，没有出现不终止。仍是启发式AI诊断，不能代替真人平衡。

## 0.7 画风与战场展示

- 用户要求去掉写实中世纪厚涂AI感，三英雄/六兵种全部替换为原创日式赛璐璐肖像与正常成年比例全身棋子。法师增加银发眼镜、星杖与学者长衣，医师采用粉紫短发，区分身份与职业。
- 展开视野左侧人物/卡牌详情、右侧公开战况使用原生控件；悬停即可更新，缩放后空白不足自动隐藏，不遮挡格子、不显示敌方手牌内容。人物详情高度按内容适配。
- 增加地貌邻接过渡、建筑投影与港口石堤、水面动画；规则数据保持0.6。
- Windows UI 213项全部通过，工程引用88文件0错误0警告。日志ui-v07-cel-complete.log、import-v07-cel-complete.log，无ERROR或SCRIPT ERROR。新增检查包括详情内容更新、只读状态、全图边界、缩放隐藏/适配恢复、公开手牌数量。
- 实际查看war-council.png与expanded-battle.png，确认新版角色和棋盘职业/阵营/数值可见。其余地图、图鉴与布局尺寸由同一UI流程检查。
- 后续地图辨识修订加入松林/金合欢/门楼与灰岩/砂岩/台地，减少道路/森林/桥梁常驻徽记；ui-landforms-native.log 215项通过。实际查看expanded-ridgepass.png和expanded-citadel.png；引用检查92文件无问题。规则地图数据未改。

## 0.6 检查点

- 基础规则76项、地形/英雄127项、套牌战术65项、局部施法/计时28项，全部0失败；分别完成12、36、9场AI对局。
- Windows真实图形203项，0失败；场景/资源引用79文件，0错误、0警告。
- 日志：battle-v06-mature.log、evolution-v06-mature.log、tactics-v06-mature.log、casting_clock-v06-mature.log、ui-v06-mature.log；导入日志import-v06-mature.log。检查无ERROR或SCRIPT ERROR。
- 六张正式地图12×10，旧8×6布局仅保留隐藏回归。覆盖地图对称/互通、动态边界、完整对局；相同坐标变换下的缩放、滚轮锚点、中键拖动、适配复位与展开布局。布局尺寸覆盖1440×1000、1008×700、1920×1080。
- 每个行动回合90秒，超时只交接一次；手动结束/重开重置，本地图鉴/规则/战前菜单暂停；验证过期AI协程不能操作新回合。
- 目标法术友军3格/法师4格，天气全场。覆盖精确边界、支点死亡范围收缩、非法操作原子性、范围中心与溅射、指挥官附近技能/换位。赛菈技能局部治疗半径4格；AI避免抽牌导致自身致命疲劳。
- 三英雄与六兵种成年肖像及正常比例全身棋子已接入；透明alpha元数据验证通过。原始PNG与来源/顺序见assets/art/manifest.json，旧Q版素材退出生产显示。

最新截图包含expanded-battle.png、expanded-harbor.png、war-council.png、card-library.png及各地图。0.6使用大地图、局部施法、90秒时限和成熟人物；历史检查点仍保留于.checkpoints/。

## 0.6 平衡诊断

六张大地图、三组英雄配对、两个种子与换边，共72场完整对局；先手33胜。英雄各48场：艾琳31胜、维洛25胜、赛菈16胜。相同诊断调整前为35/23/14胜。调整为艾琳赐福冷却2→3、赛菈局部治疗3→4格，并让AI考虑疲劳。

报告balance-v06-large-local-casting.json与balance-v06-before-hero-tuning.json。仍存在英雄胜率偏差，不能把启发式AI表现当作人类竞技平衡结论。

## 0.4 历史检查点

- 基础规则：75 项，0 失败，12 场完整 AI 对局。日志 rules-v04-final.log。
- 地形/天气/英雄/后手补偿：106 项，0 失败，五地图与三英雄组合 15 场完整对局。日志 evolution-five-maps.log。
- 战术/套牌：44 项，0 失败，9 场套牌与地图组合对局。日志 tactics-v04-final.log。
- 真实图形：169 项，0 失败，Windows 后端。日志 ui-v04-input-atomic.log。
- 工程场景引用检查：58 文件，0 错误、0 警告。
- 上述最终日志无 ERROR 或 SCRIPT ERROR。

范围包括：卡牌区域唯一性、非法行动不改变状态、四向相邻部署（新兵可作支点）、部队与手牌上限、加权移动路径、克制/高地/冲锋/枪阵/法师穿透、反击、护盾/恢复、三英雄主动被动、天气替换/到期、六种反制战术、先后手补偿和三套预组牌。

UI 检查发送视口鼠标移动/按下/抬起，覆盖战前菜单、五地图/三英雄/三套牌选择、召唤/移动/攻击/伤害预览、英雄技能、环境牌、图鉴全部 25 张插画映射、规则窗口、胜负/重开与 AI 协程暂停/恢复。模拟一次点击的移动/按下/抬起在同帧注入，以免原生桌面鼠标事件在测试帧之间改变命中控件。布局覆盖 1440×1000、1008×700、1920×1080 和最多 8 张手牌。

截图在 screenshots/：war-council.png、deployment.png、battle.png、full-hand.png、river-snow.png、sunspire.png、ridgepass.png、citadel.png、card-library.png。后续画风迭代会覆盖截图，旧版源码检查点保存在 .checkpoints/。

## 平衡诊断

三地图、三组英雄配对、两个固定种子和换边，36 场启发式 AI 对局。

| 设置 | 先手胜场 | 艾琳/维洛/赛菈胜场（各24场） |
| --- | --- | --- |
| 后手补偿前 | 30/36 | 13/11/12 |
| 增加后手起手与一次性法力 | 21/36 | 11/8/17 |
| 赛菈射程从3降到2 | 20/36 | 12/10/14 |

原始报告见 balance-v0.3-before-compensation.json、balance-v0.3-after-compensation.json 和 balance-baseline.json。诊断可发现方向性偏差，不能代替人类对局的竞技平衡测试。新地图还未纳入这组固定诊断。

## 当前边界

Windows 单机工程；远程不检查视线，未验证联机、触屏与发行导出。自由组牌暂缓，优先响应用户指定的地图与美术参考。

AcceptDialog 的面板皮肤按官方主题属性接入：https://docs.godotengine.org/en/stable/classes/class_acceptdialog.html#theme-property-descriptions 。
