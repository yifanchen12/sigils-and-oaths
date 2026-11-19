# 内容披露与来源清单

面向 Windows 0.53.0-dev。此表用于核对送审版本实际文件和商店页面。提交内容调查和确定地区评级需要发行方查看最终构建与 Steamworks 表单。Steamworks 把开发期间生成并交付给玩家的内容与运行中生成的内容分别调查。 [Steamworks 内容调查](https://partner.steamgames.com/doc/gettingstarted/contentsurvey)

## 可用于填写的说明

> 开发期间使用生成式 AI 辅助部分人物、卡牌、地图、剧情插画及叙事文字的制作。图片和文字在制作期间进入工程，游戏运行时读取本地资源。对局敌人按固定规则选择行动。

> Generative AI assisted the development of character, card, map and narrative illustrations and parts of the narrative text. Shipped illustrations and text are prepared during development and loaded locally. Opponents make gameplay decisions using a rule-based system.

## 文件与来源

| 内容 | 本版使用情况 | 来源及待核对事项 |
| --- | --- | --- |
| Godot 引擎与内含依赖 | 官方 Windows x64 导出模板。游戏包附带引擎许可及第三方版权汇总 | 以保留的 `licenses/Godot-LICENSE.txt` 和 `licenses/Godot-COPYRIGHT.txt` 为准。 [Godot 项目许可证](https://github.com/godotengine/godot/blob/4.7.2-stable/LICENSE.txt) |
| 游戏源码与构建 | 游戏仓库含项目许可证和源码 | 出版者须确认其发行授权覆盖游戏包、美术和叙事。 [项目许可证](../../../LICENSE) |
| 角色、地图、卡面与剧情插画 | 原生图像生成后保存为本地素材，游戏运行时载入 PNG 及导入资源 | 项目美术清单有生成来源和用途。仍需用实际发行包逐资产复核权利范围与参考来源。 [工程美术清单](../../../assets/art/manifest.json) |
| 潮门后备卡面 | 36 张开发期生成插画，由三张固定 PNG 提供，战斗动作沿用原有兵种素材 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/tidegate-source.md) |
| 堤灯军令卡面 | 18 张开发期生成插画，由两张固定 PNG 提供 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/levee-source.md) |
| 回澜契令卡面 | 24 张开发期生成插画，由四张固定 PNG 提供 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/moorings-source.md) |
| 石岭行军卡面 | 36 张开发期生成插画，由四张固定 PNG 提供 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/pilgrim-source.md) |
| 镜道兵书卡面 | 48 张开发期生成插画，由四张固定 PNG 提供，棋盘部队沿用兵种战斗造型 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/glassroad-source.md) |
| 章节重走背景 | 一张开发期生成的档案室场景图 | 保留生成提示、来源文件名和 SHA-256。 [档案室生成记录](../../../assets/art/narrative/chapter-replay-source.md) |
| 战役军备背景 | 一张开发期生成的港口军备库场景图 | 保留生成提示、来源文件名和 SHA-256。 [军备库生成记录](../../../assets/art/narrative/campaign-armory-source.md) |
| 战前军需的军需桌 | 一张开发期生成插画，选牌后显示原有对应卡图 | 保留生成提示、源图和 SHA-256。 [军需配图来源](../../../assets/art/narrative/quartermaster-desk-source.md) |
| 盐布巷地图与对话背景 | 两张开发期生成图，战场地形和可通行范围由游戏规则数据决定 | 保留生成提示、源图编号和 SHA-256。 [盐布巷美术记录](../../../assets/art/narrative/saltlane-source.md) |
| 叙事与翻译 | 十八章剧情、档案、游戏规则和商店文案。部分文字在开发过程中经 AI 辅助编写和场景编辑 | 游戏正文在已提交的叙事数据中。发行方确认最终编辑与公开文案，真人整篇审读仍待开展。 [正文源](../../../data/narrative) |
| 音乐及音效 | 2 首合成循环、9 个战斗事件音效。小节、声部、包络和音高由本项目脚本编排，素材用软件合成 | 无导入采样或第三方录音。可从同一源重新渲染。 [音乐源码](../../../tools/compose_audio.py) |
| 字体 | 界面使用操作系统字体。商店图片用 Noto Serif SC 成像，素材包与游戏包均不包含字体二进制 | 核对最终排版和字形。 [Noto Serif SC 来源和许可证](https://github.com/google/fonts/tree/main/ofl/notoserifsc) |
| 商店主视觉与图标 | 原图为开发期图像生成，字标和灯笼图标由本地排版脚本完成 | 图像源、提示词和哈希单独留存。 [主视觉记录](key-art-source.md) |

## 当前可见内容

画面有风格化的刀枪、火焰法术、受击及战败演出。故事涉及战争伤亡、营救、伤病、流离失所和人物关系。商店截图也需要结合各张图的具体内容评估。游戏本地选择、敌方行动和脚本合成音乐均可离线运行。评级、地区选项和最终素材权利由发行方核对后提交。
