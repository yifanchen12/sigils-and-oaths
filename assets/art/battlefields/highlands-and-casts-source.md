# 隘口、遗城、古堡与战斗特效

断脊隘口的山脊沿禁行格相连，日陨遗城的石台阶对应高地和工事，古堡棋庭的风玫瑰位于庭院中央的可通行地面。三张地图以 `data/maps.tres` 定位，使用 Blender 4.5.16 LTS 的固定正交相机和 Cycles 光照渲染。每格为 180×180 像素。地图在 Godot 的二维棋盘中显示。 [建模程序](../../../tools/render_highlands.py) · [投影检查](../../../tools/check_battlefield_models.py)

草地、细沙、石灰岩和板岩共用一张四分区材质图。古堡另有风玫瑰纹样。两幅材质由本次内置图像生成工具制作，再打包进可编辑的 Blender 工程。模型、光照与相机由本项目搭建。 [表面材质](../model_sources/highlands-surfaces-v1.png) · [风玫瑰](../model_sources/citadel-windrose-v1.png)

战斗特效由一张三列两行的透明图集提供。Godot 以六幅图绘制火焰、疗愈、盾、伏阵、冰棱和军旗；蓄势、飞行、命中、范围扩散和天气过场按时间与地格绘制。火焰、医术等技能的名牌使用游戏中对应的人物或卡面。开发期生成工具提供了原图和透明修订稿，模型编号未在工具结果中提供。 [最终图集](../actions/cast-seals-v1.png) · [战斗绘制](../../../scripts/cast_art.gd)

## 生成记录

| 素材 | 生成文件 | 用途 |
| --- | --- | --- |
| 古堡风玫瑰 | `exec-2b7c5add-b32f-4f03-9f29-1a93b8ac8e44.png` | 中庭原始镶嵌地面色彩图 |
| 地表材质 | `exec-fe755f1c-9910-4c1d-bbfa-95a72faca8c0.png` | 草地、风沙、石灰岩和板岩四种表面 |
| 法术与技能 | `exec-e9c06e87-bc53-4b07-b67e-03013b9aac96.png` | 六幅图的设计母稿 |
| 透明修订 | `exec-fee9a426-b3a1-40d9-b4a3-a2ad3cdca945.png` | 运行时使用的原始 RGBA 文件 |

## 原始提示词

### 古堡镶嵌

```text
A single square overhead albedo texture for an original medieval-fantasy tactical RPG's stone courtyard, intended to be mapped to a flat circular Blender floor inlay. Orthographic straight-down plan with perfectly circular concentric rings centered at the exact image center. In worn indigo slate, tiny warm ivory, ochre and muted verdigris ceramic tesserae form one large legible heraldic wind rose made from four elegant long lance-shaped leaves and four shorter rays, surrounding a bronze central boss. The broad silhouette should read from a distance. Fine chipped irregular mosaic stones, lines of missing tesserae revealing grey mortar, two sparse wandering hairline cracks, a subtle asymmetry of age. Intentional hand-crafted classic Japanese tactics RPG background painting, matte diffuse textures, richly pigmented but restrained value range. Fill the entire square from edge to edge with the same old grey limestone mosaic. Main ring occupies 88 percent of width. No text, no lettering, no digits, no UI, no units, no cast shadow, no perspective, no frame, no vignette, no modern graphic outlines. This is a directly usable texture, not a photograph of an object on a background.
```

### 地表材质

```text
Create one square game-art MATERIAL ATLAS for a hand-painted fantasy tactical battlefield rendered in Blender. Exactly four distinct equally sized square quadrants laid edge-to-edge in a clean 2-by-2 layout. Absolutely no borders, gutters, notes, lettering, graphics, lighting direction, shadows or perspective. All four are flat orthographic diffuse color materials sampled from surfaces at close range, not landscapes. TOP LEFT: an alpine meadow floor, tiny tightly layered olive-green and golden grasses, grey-green moss, pale lavender heather, soil, occasional flat slate pebbles; irregular organic brush clusters richly differentiated at multiple scales. TOP RIGHT: sun-dried ochre and apricot desert sand with delicate, wind-combed, oblique crossing ripples, earth fissures and scattered very small red grit, subtle color variations. BOTTOM LEFT: antique cool pale grey limestone surface, rich warm-to-cool ivory and silver grey mineral mottling with little patches of lichen, micro-pitting, natural hairline veins. One continuous stone surface without any blocks, grout or a paved pattern. BOTTOM RIGHT: alpine blue-grey fractured slate rock surface, high angular cleavages, jagged thin broken quartz seams, interrupted ochre and pale moss lichen, strongly faceted geology. Every quadrant is a seamless-looking, uniformly detailed material swatch filling the entire quadrant to the very edges. Delicate traditional Japanese fantasy battlefield background illustration with closely observed real material structure, luminous painterly color variation, mature visual sophistication. No props, trees, architecture, crest, icon or map. No baked cast shadows.
```

### 特效图集

```text
Create an original transparent 3-column by 2-row battle VFX sprite atlas for a polished hand-drawn Japanese fantasy tactics RPG with a flat grid. Landscape 3:2 canvas, EXACTLY SIX independent, equally sized square cells without drawn divisions. One isolated, compact, single magical impact keyframe per cell, centered at its exact cell center; ALL six have plenty of fully transparent margin (12% of cell on each side). True clear alpha outside the forms and in their inner negative space. Elegant confident tapered silhouette, luminous ivory core, richer saturated colored cel-shadow, irregular inked accents, spare glints, controlled glow. Mature game animation cels, visually distinct silhouettes, readable at 60 pixels. TOP LEFT: an asymmetric scarlet and vermilion flame eruption with a vertical golden-white spear of fire, ember flecks and an open flame ring low on the ground. TOP CENTER: a rising sage-green and turquoise spiral of slim healing leaves circling a small ivory four-point star, hollow center. TOP RIGHT: an airy formation of three overlapping faceted pale sapphire and silver spectral kite shields with a protective arc. BOTTOM LEFT: a sprung violet trap seal with two broken crossed chains and angular outward purple sparks, an open shape. BOTTOM CENTER: a cold fan of four jagged cobalt and pale blue ice prisms cracking upward with frost shards and a diamond glint. BOTTOM RIGHT: two curved ivory-and-gold banner-shaped streams rising over a flattened amber summoning ring, small arrowhead pennants and a warm central star. Flat face-on sprite rendering with a hint of elliptical ground plane; no characters, weapons held by people, borders, printed words, symbols resembling letters, numbers, backgrounds, checkerboard, frame, watermark, UI or shadows cast on a surface.
```

### 透明修订

```text
Preserve this exact original 3-by-2 RPG effects sheet: six cels, same locations, colors, shapes, square cell bounds and proportions. Remove all white and milky background, all white paper, broad soft glow and atmosphere both around and INSIDE the openings in the figures. Export a genuinely isolated transparent RGBA game sprite sheet, with alpha exactly ZERO throughout all empty areas right up to the cel outlines. Only the actual six small magic sprites should contain any visible pixels. Crisp colored edges, tight glows only inside silhouette, keep ivory highlights IN the flame, leaves, shield, chain, crystal and banners. Leave the wide gutter and all four corner pixels entirely clear, with no checkerboard drawn into the picture. Preserve the exact landscape format and arrangement.
```
