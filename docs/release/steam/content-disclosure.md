# 内容披露与来源清单

面向 Windows 0.60.0-dev。此表用于核对送审版本实际文件和商店页面。提交内容调查和确定地区评级需要发行方查看最终构建与 Steamworks 表单。Steamworks 把开发期间生成并交付给玩家的内容与运行中生成的内容分别调查。 [Steamworks 内容调查](https://partner.steamgames.com/doc/gettingstarted/contentsurvey)

0.60 新增吊锤透明原画、独立锤击音和两首署名配乐。12 张地形绘制参考、1 张人物草稿和 23 份美术制作记录已从游戏数据包移出，源仓库保留制作材料。 [本版来源和音乐许可](../../../assets/audio/MUSIC-CREDITS.txt) · [美术提示词](../../../assets/art/actions/hollow-hammer.md)

上一版从 0.59 的 Windows 游戏包读出 210 项美术、音频、叙事、游戏数据和制作记录，并逐项对应到发行提交中的源文件和制作依据。灯笼图标既有原图又有导入版本，共读出 211 份资源数据。其中有 12 张地形绘制参考、1 张人物草稿和 23 份美术制作记录。它们包含在这一版下载中。 [实际打包清单与文件校验值](packed-sources-v059.json)

## 可用于填写的说明

> 开发期间使用生成式 AI 辅助部分人物、卡牌、地图、剧情插画及叙事文字的制作。图片和文字在制作期间进入工程，游戏运行时读取本地资源。对局敌人按固定规则选择行动。

> Generative AI assisted the development of character, card, map and narrative illustrations and parts of the narrative text. Shipped illustrations and text are prepared during development and loaded locally. Opponents make gameplay decisions using a rule-based system.

## 文件与来源

| 内容 | 本版使用情况 | 来源及待核对事项 |
| --- | --- | --- |
| Godot 引擎与内含依赖 | 官方 Windows x64 导出模板。游戏包附带引擎许可及第三方版权汇总 | 以保留的 `licenses/Godot-LICENSE.txt` 和 `licenses/Godot-COPYRIGHT.txt` 为准。 [Godot 项目许可证](https://github.com/godotengine/godot/blob/4.7.2-stable/LICENSE.txt) |
| 游戏源码与构建 | 游戏仓库含项目许可证和源码 | 出版者须确认其发行授权覆盖游戏包、美术和叙事。 [项目许可证](../../../LICENSE) |
| 角色、地图、卡面与剧情插画 | 开发期生成的插画、正交渲染的地形及项目绘制的图标随包载入 | 已核对包内资源、提交中的源文件、现有制作记录和七份立体地形渲染的模型来源。发行方仍需确认商业使用授权范围。 [工程美术清单](../../../assets/art/manifest.json) · [逐项核对结果](packed-sources-v059.json) |
| 潮门后备卡面 | 36 张开发期生成插画，由三张固定 PNG 提供，战斗动作沿用原有兵种素材 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/tidegate-source.md) |
| 堤灯军令卡面 | 18 张开发期生成插画，由两张固定 PNG 提供 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/levee-source.md) |
| 回澜契令卡面 | 24 张开发期生成插画，由四张固定 PNG 提供 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/moorings-source.md) |
| 石岭行军卡面 | 36 张开发期生成插画，由四张固定 PNG 提供 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/pilgrim-source.md) |
| 镜道兵书卡面 | 48 张开发期生成插画，由四张固定 PNG 提供，棋盘部队沿用兵种战斗造型 | 保留生成提示、来源文件名和 SHA-256。 [卡面生成记录](../../../assets/art/expansion/glassroad-source.md) |
| 双桥河谷、暮林边境与碧潮港湾底图 | AI 辅助编写建模脚本，在 Blender 中搭建原创地形、树木、桥梁、港口建筑及船只，用正交相机将三张整图渲染到本地。港湾另有四处空泊位图 | 保留可编辑模型、建模脚本和渲染文件 SHA-256。 [美术清单](../../../assets/art/manifest.json) |
| 章节重走背景 | 一张开发期生成的档案室场景图 | 保留生成提示、来源文件名和 SHA-256。 [档案室生成记录](../../../assets/art/narrative/chapter-replay-source.md) |
| 战役军备背景 | 一张开发期生成的港口军备库场景图 | 保留生成提示、来源文件名和 SHA-256。 [军备库生成记录](../../../assets/art/narrative/campaign-armory-source.md) |
| 战前军需的军需桌 | 一张开发期生成插画，选牌后显示原有对应卡图 | 保留生成提示、源图和 SHA-256。 [军需配图来源](../../../assets/art/narrative/quartermaster-desk-source.md) |
| 断脊隘口、日陨遗城、古堡棋庭与新特效 | 三份原创 Blender 模型使用开发期生成的地材，古堡另嵌有风玫瑰纹样。技能和卡牌从一张六幅透明图集取图，运行时由 Godot 按实际行动播放 | 保留三份可编辑工程、两张材质图和透明特效图集，并记录提示词及来源。 [制作记录](../../../assets/art/battlefields/highlands-and-casts-source.md) |
| 河岸指挥官、援护与陷阱的演出 | 开发期生成的第二张六幅透明图集，配合地格、单位和攻击结果绘制。 | [图集、出处及完整提示词](../../../assets/art/actions/river-signatures.md) |
| 兵种与手牌动作 | 第三张六幅透明图集用于骑兵蹄痕、精准箭、火矢、护盾、治疗和冰缚。五种音效由项目合成器产生。 | [图像来源与提示词](../../../assets/art/actions/field-strokes.md) · [音效源码](../../../tools/compose_audio.py) |
| 天气牌 | 雨、雪、日光、雾带、风和纸灯均使用开发期间生成的原创图像。游戏按地格与天气状态绘制雨线、光束、薄雾和灯火，读取本地合成声音。 | [天气原画、提示词与校验值](../../../assets/art/actions/weather-cels.md) |
| 盐布巷地图与对话背景 | 两张开发期生成图，战场地形和可通行范围由游戏规则数据决定 | 保留生成提示、源图编号和 SHA-256。 [盐布巷美术记录](../../../assets/art/narrative/saltlane-source.md) |
| 叙事与翻译 | 十八章剧情、档案、游戏规则和商店文案。部分文字在开发过程中经 AI 辅助编写和场景编辑 | 游戏正文在已提交的叙事数据中。发行方确认最终编辑与公开文案，真人整篇审读仍待开展。 [正文源](../../../data/narrative) |
| 音乐及音效 | 《Evening》和《Angevin》由 Kevin MacLeod 作曲并以 CC BY 4.0 授权。25 个游戏事件音效由项目合成。 | [配乐署名、来源与编辑说明](../../../assets/audio/MUSIC-CREDITS.txt) · [音效源码](../../../tools/compose_audio.py) |
| 字体 | 游戏数据包中没有单独的字体文件，中文使用系统后备字体。商店图片用 Noto Serif SC 成像。Godot 随引擎的第三方声明另列有 Noto Sans 和 Droid Sans 等字体 | Windows 下载附带引擎第三方声明。 [Noto Serif SC 来源和许可证](https://github.com/google/fonts/tree/main/ofl/notoserifsc) · [已分发声明及校验值](packed-sources-v059.json) |
| 商店主视觉与图标 | 原图为开发期图像生成，字标和灯笼图标由本地排版脚本完成 | 图像源、提示词和哈希单独留存。 [主视觉记录](key-art-source.md) |

## 当前可见内容

画面有风格化的刀枪、火焰法术、受击及战败演出。故事涉及战争伤亡、营救、伤病、流离失所和人物关系。商店截图也需要结合各张图的具体内容评估。游戏选择、敌方行动、录制配乐和事件音效均可离线运行。评级、地区选项和最终素材权利由发行方核对后提交。
