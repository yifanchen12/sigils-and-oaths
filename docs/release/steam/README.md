# 《纹章与誓约》Steam 商店素材候选包

当前 Windows 预览为 0.51.0-dev。界面和剧情为简体中文，以下中英文文案供商店语言版本使用。本目录保留高分辨率游戏画面、商店及库用图片和内容披露底稿。

## 中文简介

在友军身旁部署部队，把手牌打进战棋地图。在桥头伏设陷阱，让枪卫援护友军，用局部法术改变阵势。率领一支战后仍要回家的军队，穿过十八章战役，决定同伴、城镇和旧誓言的去向。

### 关于游戏

在《纹章与誓约》中，牌从哪里打出和手上有什么同样重要。每名友军都能成为增援点。相邻格能接上新兵，森林和高地会改变防御、射程和移动费用。战线推进后，更多地格进入法师的施法范围。走得太紧凑，也给了对面的范围法术机会。

- 在 200 种可组牌中挑选部队、法术、手牌陷阱与地形天气牌。用十九套预组开局，或编辑自己的 30 张牌组。先打低费牌启动连携，部署会在阵亡时反击的枪卫，再用高费军令重整阵线。
- 攻下桥头、在盐布巷护送担架队，或按序接应撤离处。六种兵种各有主动技能，指挥官也有独立的主动与被动。
- 在河门来信开始十八章单人战役。故事记录关于救济、修渠和同伴去留的选择，通向三个结局。随战役推进开放三个军备位，战前挑选哪几张牌随军。第四章起有 20 场简报可另选一张起手军需。
- 从四节不限时教程入门。自由对战使用 90 秒行动回合。战役支持中途保存、剧情回看和可调阅读字号，并能用独立存档重走已完成章节。

## English store copy

Play cards onto a tactical battlefield. Deploy beside allies, hide traps at crossings, and use spearmen to intercept attacks. Lead a war-weary company through an eighteen-chapter campaign and decide what its surviving promises will cost.

### About this game

In *Sigils & Oaths*, the ground determines what your hand can do. Every ally can anchor reinforcements. Forests and hills change defense, range, and movement. Advance a mage to extend your casting reach, or spread your forces before an enemy spell catches them together.

- Build a thirty-card deck from 200 collectible cards or start with one of nineteen presets. Chain cards played in the same turn, set traps from hand, deploy troops that retaliate when defeated, and mark the ground with delayed orders.
- Fight over crossings, escort a stretcher crew across Saltcloth Lane, and reach evacuation points in order. Six unit roles have their own active abilities, and each commander has active and passive powers.
- Begin with a letter from Rivergate and finish one of three endings in the eighteen-chapter solo campaign. Your choices affect relief, repairs, and the future of the company. Unlock three armory slots to bring chosen cards into upcoming battles. Requisition one opening-hand replacement in twenty engagements from chapter four onward.
- Practice in four untimed drills. Skirmishes use ninety-second turns. Save campaign progress mid-battle, replay completed chapters in a separate save, and adjust story text size.

Game interface and story text are in Simplified Chinese.

## 图像清单

| 用途 | 尺寸 | 文件 |
| --- | --- | --- |
| 商店横幅、窄幅、主封面、竖封 | 920×430、462×174、1232×706、748×896 | [graphics](graphics) |
| 库封面、库横幅、库英雄图 | 600×900、920×430、3840×1240 | [graphics](graphics) |
| 透明库字标 | 1280×390 RGBA | [library-logo.png](graphics/library-logo.png) |
| 快捷方式、应用图标 | 512×512 PNG、184×184 JPG | [shortcut-icon.png](graphics/shortcut-icon.png) · [app-icon.jpg](graphics/app-icon.jpg) |
| 五张游戏画面 | 全部 1920×1080，16:9 | [gameplay](gameplay) |

商店封面只带游戏标题，库英雄图无文字，游戏截图直接取自 Godot 实际渲染。规格按核对时的 Steamworks 文档，本地已经检查尺寸和透明通道。发行方仍需核对后台预览的压缩、裁切和适龄截图。[商店图像规格](https://partner.steamgames.com/doc/store/assets/standard) · [库用图像规格](https://partner.steamgames.com/doc/store/assets/libraryassets) · [图标规格](https://partner.steamgames.com/doc/store/assets/community)

截图包括常规对战第 12 轮的十费范围法术、第 7 轮的双桥遭遇、首章对白 `c01.a03`、可操作的援护教程，以及第十七章「先送灯手」的正式任务配置。对战画面来自正常资源和规则下的 AI 行动，保留游戏原界面。 [尺寸及哈希核对](inventory.json)

## 玩法预告候选

0.43.0-dev 约 29 秒的实机录像包含桥头交战、手牌伏设与援护、十费铜钟和首章剧情。游戏保留了战斗界面与原声。视频为 1920×1080、30 FPS、H.264 约 7.15 Mbps 及 AAC 48 kHz 立体声。 [下载 MP4](https://github.com/yifanchen12/sigils-and-oaths/releases/download/v0.43.0-dev/SigilsAndOaths-0.43.0-dev-Gameplay.mp4) · [Steamworks 视频规格](https://partner.steamgames.com/doc/store/trailer)

[内容披露与授权底稿](content-disclosure.md) · [主视觉来源](key-art-source.md)

## Windows 构建入库

已提供从验收过的 Windows 包建立 SteamPipe 目录的脚本。内容目录及启动项使用同一份可运行文件，实际 App ID、Depot ID、Steam 客户端下载安装与提交归发行账号流程。 [Windows 入库目录与预览方式](windows-depot.md)
