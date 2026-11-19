"""Build Greenwood and Harbor as editable Blender dioramas and render flat board art."""

import argparse
import math
import sys
from functools import lru_cache
from pathlib import Path

import bpy
from mathutils import Vector, noise

sys.path.insert(0, str(Path(__file__).resolve().parent))
from render_rivergate import (
    Landscape,
    RNG,
    block,
    configure_render,
    form_mesh,
    lerp,
    material,
    outline,
    point,
    post,
    read_map,
    srgb,
    stone,
    use_relative_browser_paths,
)


TAU = math.tau
ink = lru_cache(maxsize=None)(srgb)


def clamp(value):
    return max(0.0, min(1.0, value))


def tiles(rows, symbols):
    return [(x, y) for y, row in enumerate(rows) for x, terrain in enumerate(row) if terrain in symbols]


def palette(name, colors, **settings):
    return [material(f"{name} {i + 1}", color, **settings) for i, color in enumerate(colors)]


def stacked(name, rings, mats, band_colors=None):
    """Join matching counterclockwise rings, preserving their individual silhouettes."""
    n = len(rings[0])
    verts = [p for ring in rings for p in ring]
    faces = [tuple(reversed(range(n)))]
    indices = [0]
    for level in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((level * n + i, level * n + j, (level + 1) * n + j, (level + 1) * n + i))
            indices.append(band_colors[level][i] if band_colors else 0)
    faces.append(tuple(range(len(verts) - n, len(verts))))
    indices.append(len(mats) - 1)
    obj = form_mesh(name, verts, faces, mats[0])
    for mat in mats[1:]:
        obj.data.materials.append(mat)
    for poly, index in zip(obj.data.polygons, indices):
        poly.material_index = index
    return obj


def ring(x, row, z, radius, count, phase=0, depth=1):
    return [
        point(
            x + radius * math.cos(phase + i * TAU / count),
            row - depth * radius * math.sin(phase + i * TAU / count),
            z,
        )
        for i in range(count)
    ]


def beam(name, start, end, radius, mat):
    return outline(name, [point(*start), point(*end)], radius, mat)


class Greenwood(Landscape):
    def __init__(self, rows):
        super().__init__(rows)
        self.forest = tiles(rows, "f")
        self.mountains = tiles(rows, "m")
        self.conifer = palette(
            "Blue spruce needles", ["#244c49", "#33665a", "#447965", "#648d70", "#8da383"], texture_scale=34
        )
        self.birch = palette(
            "Sunlit deciduous leaves",
            ["#4b6740", "#708044", "#8c9849", "#abc164", "#c3cb73"],
            texture_scale=27,
        )
        self.rowan = palette(
            "Copper rowan leaves", ["#705338", "#99603c", "#b77943", "#c7934d", "#dec06f"], texture_scale=29
        )
        self.turf = palette("Heath and moss", ["#44623e", "#6f834a", "#96a261"], texture_scale=32)
        self.shale = palette(
            "Bedded frontier shale", ["#4b555f", "#727a79", "#949287", "#afa38e"], texture_scale=19
        )
        self.pale_bark = material("Silver birch bark", "#b9aaa0")
        self.woodcut = material("End grain", "#ad8554", texture_scale=25)
        self.flowers = palette(
            "Wildflower petals", ["#8875aa", "#b798c5", "#dfc675", "#e4dbb2"], texture_scale=42
        )
        self.diagonals = []
        for x, y in sorted(self.roads):
            for dx in (-1, 1):
                if (
                    (x + dx, y + 1) in self.roads
                    and (x + dx, y) not in self.roads
                    and (x, y + 1) not in self.roads
                ):
                    self.diagonals.append((x + 0.5, y + 0.5, dx))

    def shore_distance(self, x, row):
        return 2.0

    def relief(self, x, row):
        broad = noise.noise_vector(Vector((x * 0.55, row * 0.66, 3)))[2]
        rolling = sum(
            0.35 * math.exp(-((x - cx) ** 2 / 0.33 + (row - cy) ** 2 / 0.29)) for cx, cy in self.hills
        )
        return 0.036 + 0.14 * broad + rolling

    def road_distance(self, x, row):
        distance = super().road_distance(x, row)
        for sx, sy, dx in self.diagonals:
            if abs(x - sx) > 1.2 or abs(row - sy) > 1.2:
                continue
            t = clamp(((x - sx) * dx + row - sy) / 2)
            distance = min(distance, math.hypot(x - sx - dx * t, row - sy - t))
        return distance

    def land_color(self, x, row):
        n = noise.noise_vector(Vector((x * 1.9, row * 1.95, 7)))
        swale = noise.noise_vector(Vector((x * 0.38, row * 0.64, 15)))[1]
        edge = min(math.hypot((x - ix - 0.49) * 0.95, row - iy - 0.5) for ix, iy in self.forest)
        meadow = lerp(ink("#48714b"), ink("#bdba68"), clamp(0.50 + n[0] * 0.61 + swale * 1.41))
        heather = noise.noise_vector(Vector((x * 0.86, row * 1.5, 11)))[2]
        meadow = lerp(meadow, ink("#b99c60"), clamp((heather - 0.13) * 1.46))
        meadow = lerp(meadow, ink("#315947"), clamp((1.13 - edge) * 0.88 + n[1] * 0.23))
        distance = self.road_distance(x, row)
        road = clamp((0.34 - distance + 0.065 * n[1]) / 0.16)
        ochre = lerp(ink("#b19470"), ink("#d4bb8a"), clamp(0.48 + n[0] * 0.6))
        wear = math.exp(-(((distance - 0.115) / 0.033) ** 2))
        return (*lerp(meadow, lerp(ochre, ink("#7d694f"), wear * 0.35), road), 1)

    def fir(self, x, row, height):
        base = self.relief(x, row)
        post("Spruce leader", x, row, base + height * 0.43, height * 0.036, height * 0.84, self.bark)
        for tier, (bottom, extent) in enumerate(
            ((0.16, 0.32), (0.31, 0.29), (0.47, 0.235), (0.63, 0.17), (0.77, 0.112))
        ):
            n = 18
            phase = RNG.uniform(0, TAU)
            shape = [RNG.uniform(0.86, 1.13) * (1 if i % 2 else 0.69) for i in range(n)]
            rings = []
            for radius, lift in ((0.83, 0.046), (1, 0.025), (0.54, 0.18), (0.055, 0.31)):
                layer = []
                for i in range(n):
                    angle = i * TAU / n + phase
                    reach = extent * height * radius * shape[i]
                    sag = 0.057 if i % 2 and radius > 0.80 else 0
                    layer.append(
                        point(
                            x + reach * math.cos(angle),
                            row - reach * math.sin(angle),
                            base + height * (bottom + lift - sag),
                        )
                    )
                rings.append(layer)
            shade = min(2, tier // 2)
            color_bands = [
                [shade] * n,
                [min(4, shade + int(i % 3 != 0)) for i in range(n)],
                [min(4, shade + 1 + int(i % 4 == 0)) for i in range(n)],
            ]
            stacked("Tier of sweeping spruce boughs", rings, self.conifer, color_bands)

    def broadleaf(self, x, row, height, foliage):
        base = self.relief(x, row)
        top = base + height * 0.76
        beam("Birch main stem", (x, row, base), (x + 0.035, row, top), height * 0.034, self.pale_bark)
        for i in range(10):
            angle = i * 2.4
            reach = height * (0.189 if i < 6 else 0.102)
            bx, by = x + math.cos(angle) * reach, row + math.sin(angle) * reach
            bz = base + height * (0.57 + 0.044 * i)
            beam("Birch fork", (x, row, base + height * 0.40), (bx, by, bz), height * 0.015, self.pale_bark)
            radius = height * RNG.uniform(0.115, 0.176)
            stone(
                "Birch leaf cluster",
                bx,
                by,
                bz,
                (radius * 1.17, radius, radius * 0.84),
                foliage[min(4, i // 3 + RNG.randrange(2))],
                2,
                True,
            )
        stone(
            "Sunlit crown",
            x + 0.02,
            row,
            top + height * 0.18,
            (height * 0.15, height * 0.14, height * 0.11),
            foliage[3],
            2,
            True,
        )

    def rock_stack(self, name, x, row, base, rx, ry, height, moss):
        n = 10
        phase = RNG.random()
        edge = [RNG.uniform(0.68, 1.12) for _ in range(n)]
        rings = []
        for radius, elevation in (
            (0.89, 0),
            (1, 0.20),
            (0.92, 0.39),
            (0.85, 0.45),
            (0.90, 0.53),
            (0.73, 0.9),
            (0.65, 1),
        ):
            layer = []
            for i in range(n):
                angle = phase + i * TAU / n
                layer.append(
                    point(
                        x + rx * edge[i] * radius * math.cos(angle) + 0.07 * rx * elevation,
                        row - ry * edge[i] * radius * math.sin(angle),
                        base + height * (elevation + 0.19 * math.cos(angle + 0.75)),
                    )
                )
            rings.append(layer)
        mats = self.shale + [self.turf[1] if moss else self.shale[-1]]
        bands = [[max(0, min(3, s + int(i % 4 == 1))) for i in range(n)] for s in (0, 1, 0, 2, 1, 2)]
        stacked(name, rings, mats, bands)

    def shrine(self, x, y, broken):
        cx, cy = x + 0.5, y + 0.53
        base = self.relief(cx, cy)
        for lvl, size in enumerate((0.78, 0.65)):
            block(
                "Wayside chapel worn threshold",
                cx,
                cy,
                base + 0.04 + 0.077 * lvl,
                size,
                0.42 + 0.065 * (1 - lvl),
                0.08,
                self.shale[lvl + 1],
            )
        for dx in (-0.234, 0.234):
            for level in range(3 if broken and dx > 0 else 4):
                block(
                    "Wayside arch voussoir",
                    cx + dx,
                    cy,
                    base + 0.19 + level * 0.112,
                    0.12,
                    0.246,
                    0.104,
                    self.shale[(level + 2) % 4],
                )
        if not broken:
            for side in (-1, 1):
                for level in range(3):
                    voussoir = block(
                        "Pointed chapel arch",
                        cx + side * (0.198 - level * 0.074),
                        cy,
                        base + 0.61 + level * 0.064,
                        0.122,
                        0.231,
                        0.122,
                        self.shale[2 + (level % 2)],
                    )
                    voussoir.rotation_euler.y = side * (0.33 + level * 0.08)
        else:
            block(
                "Fallen shrine lintel", cx + 0.09, cy + 0.15, base + 0.19, 0.40, 0.12, 0.11, self.shale[2]
            ).rotation_euler.z = -0.24
        block("Pilgrim altar", cx, cy + 0.052, base + 0.20, 0.23, 0.21, 0.14, self.shale[1])
        post("Copper offering bowl", cx, cy + 0.052, base + 0.292, 0.064, 0.047, self.brass)
        for i in range(16):
            angle = i * 2.4
            xx, yy = cx + 0.42 * math.cos(angle), cy + 0.34 * math.sin(angle)
            radius = RNG.uniform(0.037, 0.077)
            stone(
                "Fallen chapel flagstone",
                xx,
                yy,
                self.relief(xx, yy) + 0.018,
                (radius, radius * 0.7, 0.027),
                self.shale[i % 3],
            )

    def understory(self):
        verts, faces, pigments = [], [], []
        for _ in range(8900):
            x, y = RNG.uniform(0, self.width), RNG.uniform(0, self.length)
            n = noise.noise_vector(Vector((x * 2.2, y * 2.7, 18)))
            if n[0] < -0.14 or self.road_distance(x, y) < 0.285:
                continue
            z = self.relief(x, y)
            for i in range(3):
                angle = i * 2.24 + RNG.random()
                reach = RNG.uniform(0.012, 0.039)
                start = len(verts)
                verts.extend(
                    (
                        point(x - 0.007, y - 0.01, z),
                        point(x + 0.009, y + 0.011, z),
                        point(
                            x + reach * math.cos(angle),
                            y + reach * math.sin(angle),
                            z + RNG.uniform(0.032, 0.092),
                        ),
                    )
                )
                faces.append((start, start + 1, start + 2))
                pigments.append(int(n[1] > 0.07))
            if n[1] < 0.22 or RNG.random() > 0.41:
                continue
            flower_color = 2 + (int(n[0] > 0.22) * 2) + RNG.randrange(2)
            for i in range(RNG.randint(3, 7)):
                bx, by = x + RNG.uniform(-0.10, 0.1), y + RNG.uniform(-0.11, 0.105)
                base = self.relief(bx, by) + 0.048
                r = RNG.uniform(0.010, 0.019)
                start = len(verts)
                verts.extend(ring(bx, by, base, r, 5, RNG.random()))
                faces.append(tuple(range(start, start + 5)))
                pigments.append(flower_color)
        cover = form_mesh("Heath, bluebells and meadow flowers", verts, faces, self.turf[0])
        for mat in [self.turf[2]] + self.flowers:
            cover.data.materials.append(mat)
        for poly, index in zip(cover.data.polygons, pigments):
            poly.material_index = index

    def escarpment(self, x, y, index):
        # Let the unbroken turf run up the back. Only the eroded face exposes slabs.
        angle = (0.55, 1.65, 2.87, 0.90, 3.70)[index % 5]
        for seg in range(8):
            theta = angle + (seg - 3.5) * 0.34
            tx, ty = x + 0.33 * math.cos(theta), y + 0.29 * math.sin(theta)
            rock_height = RNG.uniform(0.13, 0.24) * (1 - abs(seg - 3.5) * 0.075)
            base = self.relief(tx, ty) - rock_height * 0.42
            self.rock_stack("Eroded lip of the hill", tx, ty, base, 0.135, 0.111, rock_height, True)
            stone(
                "Talus below hill",
                tx + 0.10 * math.cos(theta),
                ty + 0.13 * math.sin(theta),
                base - 0.035,
                (0.093, 0.062, 0.040),
                self.shale[seg % 3],
                1,
            )

    def timber_margin(self, x, y, direction):
        for i in range(3):
            ox, oy = x + 0.060 * i, y + direction * 0.036 * i
            base = self.relief(ox, oy) + 0.098 + (i == 2) * 0.073
            dx, dy = 0.245, 0.093 * direction
            beam(
                "Fallen timber with bark",
                (ox - dx, oy - dy, base),
                (ox + dx, oy + dy, base + 0.01),
                0.062,
                self.bark,
            )
            beam(
                "Pale end of cut timber",
                (ox + dx, oy + dy, base + 0.01),
                (ox + dx + 0.009, oy + dy, base + 0.011),
                0.052,
                self.woodcut,
            )
        stump_z = self.relief(x + 0.22, y + 0.19)
        post("Coppiced tree stump", x + 0.22, y + 0.19, stump_z + 0.105, 0.089, 0.21, self.bark)
        post("Cut surface", x + 0.22, y + 0.19, stump_z + 0.211, 0.084, 0.013, self.woodcut)

    def boundary(self, x, y, direction, length):
        for i in range(length):
            xx, yy = x + direction * 0.073 * math.sin(i * 0.53), y + i * 0.209
            base = self.relief(xx, yy)
            for tier in range(2 if i % 5 in (1, 3) else 3):
                piece = block(
                    "Broken dry-stone boundary",
                    xx + direction * tier * 0.016,
                    yy + tier * 0.035,
                    base + 0.043 + tier * 0.064,
                    0.118 - tier * 0.011,
                    RNG.uniform(0.175, 0.22),
                    RNG.uniform(0.057, 0.079),
                    self.turf[1] if tier == 2 and i % 3 else self.shale[(i + tier) % 3],
                    0.022,
                )
                piece.rotation_euler.z = RNG.uniform(-0.20, 0.20)

    def build(self, ruins):
        self.ground("Frontier meadow, cart ruts and continuous hill relief")
        for index, (x, y) in enumerate(self.forest):
            offsets = [(0.27, 0.38), (0.63, 0.27), (0.49, 0.61), (0.76, 0.70), (0.19, 0.72)]
            for j, (ox, oy) in enumerate(offsets):
                tx, ty = x + ox + RNG.uniform(-0.063, 0.063), y + oy + RNG.uniform(-0.051, 0.051)
                height = RNG.uniform(0.55, 0.94) * (1.12 if j == 2 else 1)
                if (index + j) % 3 == 0:
                    self.broadleaf(tx, ty, height, self.rowan if index in (1, 4, 7, 11) else self.birch)
                else:
                    self.fir(tx, ty, height)
            for j in range(6):
                tx, ty = x + RNG.uniform(0.12, 0.88), y + RNG.uniform(0.13, 0.86)
                stone(
                    "Forest floor fern",
                    tx,
                    ty,
                    self.relief(tx, ty) + 0.045,
                    (0.10, 0.071, 0.073),
                    self.turf[j % 3],
                    1,
                )
        for x, y in self.mountains:
            for dx, dy, rx, ry, h in (
                (0.45, 0.53, 0.46, 0.40, 0.62),
                (0.63, 0.36, 0.33, 0.28, 0.68),
                (0.31, 0.72, 0.29, 0.19, 0.31),
                (0.79, 0.65, 0.17, 0.24, 0.27),
            ):
                self.rock_stack(
                    "Fractured slate crag",
                    x + dx,
                    y + dy,
                    self.relief(x + dx, y + dy) - 0.025,
                    rx,
                    ry,
                    h,
                    False,
                )
        for index, (x, y) in enumerate(self.hills):
            self.escarpment(x, y, index)
        for i, (x, y) in enumerate(ruins):
            self.shrine(x, y, bool(i))
        self.timber_margin(2.12, 3.67, 1)
        self.timber_margin(9.88, 6.64, -1)
        self.boundary(0.17, 0.55, 1, 10)
        self.boundary(11.81, 7.79, -1, 9)
        for x, y in tiles(self.rows, "r"):
            for i in range(RNG.randint(2, 5)):
                tx, ty = x + RNG.uniform(0.18, 0.82), y + RNG.uniform(0.15, 0.85)
                if 0.16 < self.road_distance(tx, ty) < 0.32:
                    stone(
                        "Track margin stone",
                        tx,
                        ty,
                        self.relief(tx, ty) + 0.013,
                        (0.049, 0.032, 0.016),
                        self.shale[i % 3],
                    )
        self.understory()


class Harbor:
    def __init__(self, rows):
        self.rows = rows
        self.width, self.length = len(rows[0]), len(rows)
        wet = tiles(rows, "wb")
        self.left = min(x for x, y in wet)
        self.right = max(x for x, y in wet) + 1
        self.crossings = sorted({y for x, y in tiles(rows, "b")})
        assert len(self.crossings) == 2 and all(
            row[self.left : self.right] in ("b" * (self.right - self.left), "w" * (self.right - self.left))
            for row in rows
        )
        self.stone = palette("Limestone ashlar", ["#73838b", "#93a1a4", "#b3b7ad", "#c4bba8", "#9f9b94"])
        self.road = palette("Amber trade street", ["#a99578", "#b8a68b", "#c5b397", "#cabc9c"])
        self.brick = palette("Clay and copper roof", ["#9e5642", "#bd7252", "#cf986b"])
        self.timber = palette(
            "Salt-worn wood", ["#5e5145", "#79634e", "#967d60", "#b19671"], texture_scale=25
        )
        self.copper = palette("Harbor verdigris", ["#3f6e70", "#5c9090", "#79a9a2"])
        self.brass = material("Brass fittings and beacons", "#c89c56", roughness=0.48)
        self.iron = material("Blue black iron", "#344a50", roughness=0.52)
        self.mortar = material("Lime mortar", "#797e77", texture_scale=31)
        self.sail = material("Unbleached sailcloth", "#d2bf97", texture_scale=55)
        self.rope = material("Tarred flax rope", "#8e754e", texture_scale=41)
        self.moorings = []
        self.sea = -0.22

    def pave(self):
        """Batch the individually beveled stones by bank; joint shadows survive at game zoom."""
        for side, (x0, x1) in enumerate(((-0.25, self.left), (self.right, self.width + 0.25))):
            block(
                "Stone quay mass",
                (x0 + x1) / 2,
                self.length / 2,
                -0.25,
                x1 - x0,
                self.length + 1,
                0.65,
                self.mortar,
            )
            bank_verts, bank_faces, indices = [], [], []
            materials = self.stone + self.road
            y = -0.25
            while y < self.length + 0.28:
                depth = RNG.uniform(0.147, 0.213)
                x = x0
                while x < x1 - 0.009:
                    length = min(RNG.uniform(0.23, 0.43), x1 - x)
                    tx, ty = x + length / 2, y + depth / 2
                    ix = max(0, min(self.width - 1, math.floor(tx)))
                    iy = max(0, min(self.length - 1, math.floor(ty)))
                    road = self.rows[iy][ix] == "r"
                    pigment = RNG.choice((5, 6, 6, 7, 7, 8)) if road else RNG.choice((0, 1, 1, 2, 2, 3, 4))
                    half_width, half_depth = max(0.002, length / 2 - 0.0045), depth / 2 - 0.0045
                    z = 0.103 + RNG.uniform(-0.011, 0.011)
                    start = len(bank_verts)
                    for radius, h in ((1, 0.064), (1, z - 0.011), (0.968, z)):
                        for dx, dy in (
                            (-half_width, half_depth),
                            (half_width, half_depth),
                            (half_width, -half_depth),
                            (-half_width, -half_depth),
                        ):
                            bank_verts.append(point(tx + dx * radius, ty + dy * radius, h))
                    for level in range(2):
                        for i in range(4):
                            a = start + 4 * level + i
                            b = start + 4 * level + (i + 1) % 4
                            bank_faces.append((a, b, b + 4, a + 4))
                            indices.append(pigment)
                    bank_faces.append(tuple(range(start + 8, start + 12)))
                    indices.append(pigment)
                    x += length
                y += depth
            pavement = form_mesh(
                "Hand-set quay paving " + str(side + 1), bank_verts, bank_faces, materials[0]
            )
            for mat in materials[1:]:
                pavement.data.materials.append(mat)
            for poly, index in zip(pavement.data.polygons, indices):
                poly.material_index = index
            edge = self.left if side == 0 else self.right
            for course in range(3):
                y = -0.5 + course * 0.21
                while y < self.length + 0.5:
                    length = RNG.uniform(0.44, 0.74)
                    block(
                        "Cut-stone retaining wall",
                        edge,
                        y + length / 2,
                        -0.33 + course * 0.146,
                        0.16,
                        length - 0.009,
                        0.139,
                        self.stone[RNG.randrange(3)],
                        0.014,
                    )
                    y += length
            for i in range(self.length * 2 + 2):
                block(
                    "Salt-bleached coping",
                    edge,
                    i * 0.50 - 0.24,
                    0.096,
                    0.20,
                    0.491,
                    0.11,
                    self.stone[2 + i % 2],
                    0.017,
                )

    def water(self):
        mat = material("Tidal canal", "#368b94", 0.278, 11, 0.19)
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        shader = nodes.get("Principled BSDF")
        shader.inputs["Coat Weight"].default_value = 0.34
        field = nodes.new("ShaderNodeVertexColor")
        field.layer_name = "Sea depth"
        streak = nodes.new("ShaderNodeVectorMath")
        streak.operation = "MULTIPLY"
        streak.inputs[1].default_value = (2.2, 0.85, 1)
        links.new(nodes.get("Geometry").outputs["Position"], streak.inputs[0])
        links.new(streak.outputs["Vector"], nodes.get("Noise Texture").inputs["Vector"])
        salt = nodes.new("ShaderNodeMixRGB")
        salt.blend_type = "MULTIPLY"
        salt.inputs[0].default_value = 0.23
        links.new(field.outputs["Color"], salt.inputs[1])
        links.new(nodes.get("Noise Texture").outputs["Fac"], salt.inputs[2])
        links.new(salt.outputs["Color"], shader.inputs["Base Color"])
        verts, faces, pigments = [], [], []
        nx, ny = 77, 177
        for j in range(ny + 1):
            y = -0.55 + j * (self.length + 1.1) / ny
            for i in range(nx + 1):
                x = self.left - 0.08 + (self.right - self.left + 0.16) * i / nx
                depth = clamp(min(x - self.left, self.right - x) / 0.85)
                current = noise.noise_vector(Vector((x * 1.22, y * 0.91, 5)))
                surface_noise = noise.noise_vector(Vector((x * 4.8, y * 3.1, 6)))
                swell = math.sin(x * 4.1 + y * 3.6 + current[1] * 4)
                verts.append(
                    point(x, y, self.sea + 0.006 * swell + 0.017 * current[0] + 0.005 * surface_noise[2])
                )
                color = lerp(
                    ink("#6dbbad"),
                    ink("#16677e"),
                    clamp(depth * 0.83 + 0.44 * current[2] + 0.13 * surface_noise[0]),
                )
                pigments.append((*color, 1))
                if i < nx and j < ny:
                    a = j * (nx + 1) + i
                    faces.append((a, a + nx + 1, a + nx + 2, a + 1))
        canal = form_mesh("Tidal canal and submerged margins", verts, faces, mat)
        colors = canal.data.color_attributes.new(name="Sea depth", type="FLOAT_COLOR", domain="POINT")
        for i, color in enumerate(pigments):
            colors.data[i].color = color
        for f in canal.data.polygons:
            f.use_smooth = True
        glint = material("Foam caught by the tide", "#a0c4b6", 0.56)
        for edge, direction in ((self.left, 1), (self.right, -1)):
            for i in range(38):
                y = RNG.uniform(0, self.length)
                distance = RNG.uniform(0.06, 0.39)
                length = RNG.uniform(0.09, 0.38)
                outline(
                    "Reflected light by the embankment",
                    [
                        point(
                            edge + direction * (distance + 0.032 * math.sin(k * 0.8)),
                            y + k * length / 6,
                            self.sea + 0.029,
                        )
                        for k in range(7)
                    ],
                    RNG.uniform(0.004, 0.009),
                    glint,
                )

    def stone_bridge(self, y):
        a, b = self.left - 0.08, self.right + 0.08
        half = 0.35
        span = (b - a) / 3
        for i in range(3):
            start = a + i * span
            for side in (-1, 1):
                # The outer spandrel is real geometry. Each opening clears the rendered water.
                front = y + side * half
                verts, faces = [], []
                for j in range(15):
                    t = j / 14
                    x = start + t * span
                    arch = -0.21 + 0.48 * math.sin(t * math.pi) ** 0.74
                    verts.extend((point(x, front, arch), point(x, front, 0.37)))
                    if j:
                        faces.append((2 * j - 2, 2 * j, 2 * j + 1, 2 * j - 1))
                form_mesh("Cut arch spandrel", verts, faces, self.stone[1])
                arch_line = [
                    point(
                        start + (j / 20) * span,
                        front + side * 0.008,
                        -0.18 + 0.48 * math.sin((j / 20) * math.pi) ** 0.74,
                    )
                    for j in range(21)
                ]
                outline("Dressed limestone arch ring", arch_line, 0.042, self.stone[3])
            for k in range(7):
                x = start + (k + 0.5) * span / 7
                block(
                    "Masonry bridge deck",
                    x,
                    y,
                    0.345,
                    span / 7 - 0.004,
                    0.71,
                    0.061,
                    self.road[(k + i) % 4],
                    0.008,
                )
                for sign in (-1, 1):
                    block(
                        "Masonry bridge parapet",
                        x,
                        y + 0.34 * sign,
                        0.447,
                        span / 7 - 0.010,
                        0.071,
                        0.14,
                        self.stone[2 + (k % 2)],
                        0.017,
                    )
        for i in range(4):
            x = a + i * span
            block("Bridge nose pier", x, y, -0.016, 0.23, 0.91, 0.62, self.stone[0], 0.065)
            for side in (-1, 1):
                block(
                    "Square bridge newel", x, y + side * 0.35, 0.49, 0.139, 0.145, 0.26, self.stone[2], 0.018
                )
                if i in (0, 3):
                    self.lamp(x, y + side * 0.35, 0.61)

    def lamp(self, x, y, z):
        post("Beacon post", x, y, z + 0.088, 0.026, 0.176, self.iron)
        lantern = ring(x, y, z + 0.19, 0.065, 6)
        stacked(
            "Amber oil lantern",
            [ring(x, y, z + 0.15, 0.042, 6), lantern, ring(x, y, z + 0.242, 0.055, 6)],
            [self.brass],
        )
        stacked(
            "Lantern copper cap",
            [ring(x, y, z + 0.239, 0.081, 6), ring(x, y, z + 0.30, 0.016, 6)],
            [self.copper[0]],
        )

    def drawbridge(self, y):
        a, b = self.left - 0.12, self.right + 0.12
        for side in (-1, 1):
            block(
                "Drawbridge iron stringer", (a + b) / 2, y + side * 0.29, 0.16, b - a, 0.075, 0.17, self.iron
            )
        for i in range(46):
            x = a + (b - a) * (i + 0.5) / 46
            block(
                "Bascule deck board",
                x,
                y,
                0.274,
                (b - a) / 46 - 0.006,
                0.715,
                0.085,
                self.timber[RNG.choice((1, 2, 2, 3))],
                0.009,
            )
        for sign in (-1, 1):
            yy = y + sign * 0.34
            for i in range(11):
                x = a + (b - a) * i / 10
                post("Bascule railing stanchion", x, yy, 0.414, 0.029, 0.25, self.iron)
            beam("Bridge hand cable", (a, yy, 0.505), (b, yy, 0.505), 0.014, self.iron)
        for i, x in enumerate((a + 0.64, b - 0.64)):
            direction = 1 if i == 0 else -1
            for sign in (-1, 1):
                yy = y + sign * 0.37
                block("Hardwood lifting standard", x, yy, 0.504, 0.077, 0.089, 0.74, self.timber[0], 0.016)
                beam("A-frame brace", (x - direction * 0.36, yy, 0.27), (x, yy, 0.75), 0.030, self.timber[1])
                beam(
                    "Lifting arm",
                    (x - direction * 0.24, yy, 0.87),
                    (x + direction * 0.50, yy, 0.83),
                    0.042,
                    self.timber[1],
                )
                beam(
                    "Lift chain",
                    (x + direction * 0.50, yy, 0.83),
                    (x + direction * 0.62, yy, 0.33),
                    0.011,
                    self.iron,
                )
                block("Iron counterweight", x - direction * 0.22, yy, 0.78, 0.105, 0.11, 0.18, self.iron)
            beam("Overhead lifting axle", (x, y - 0.42, 0.849), (x, y + 0.42, 0.849), 0.044, self.timber[1])
        for x in (a + 0.35, b - 0.35):
            block("Cutwater under the timber bridge", x, y, -0.025, 0.20, 0.78, 0.53, self.stone[1], 0.046)

    def bastion(self, x, y, towered):
        cx, cy = x + 0.50, y + 0.53
        base = 0.111
        for level, r in enumerate((0.43, 0.39, 0.35)):
            stacked(
                "Octagonal bastion course",
                [
                    ring(cx, cy, base + level * 0.08, r, 8, math.pi / 8, 0.86),
                    ring(cx, cy, base + (level + 1) * 0.08, r - 0.012, 8, math.pi / 8, 0.86),
                ],
                [self.stone[1 + level]],
            )
        if towered:
            for j in range(4):
                z = base + 0.24 + j * 0.106
                stacked(
                    "Pilot tower limestone drum",
                    [ring(cx, cy, z, 0.217, 8, math.pi / 8), ring(cx, cy, z + 0.101, 0.213, 8, math.pi / 8)],
                    [self.stone[1 + j % 2]],
                )
            for side in (-1, 1):
                block(
                    "Watch window",
                    cx + side * 0.084,
                    cy + 0.194,
                    base + 0.5,
                    0.046,
                    0.015,
                    0.13,
                    self.iron,
                    0.008,
                )
            roof = base + 0.67
            stacked(
                "Patinated signal cupola",
                [
                    ring(cx, cy, roof, 0.30, 8, math.pi / 8),
                    ring(cx, cy, roof + 0.14, 0.17, 8, math.pi / 8),
                    ring(cx, cy, roof + 0.32, 0.026, 8, math.pi / 8),
                ],
                self.copper,
                [[1, 2, 1, 0, 0, 1, 2, 1], [1, 2, 1, 0, 0, 1, 2, 1]],
            )
            post("Beacon finial", cx, cy, roof + 0.35, 0.021, 0.091, self.brass)
            for i in range(8):
                angle = (i + 0.5) * TAU / 8
                beam(
                    "Cupola folded seam",
                    (cx + 0.286 * math.cos(angle), cy + 0.286 * math.sin(angle), roof + 0.019),
                    (cx + 0.017 * math.cos(angle), cy + 0.017 * math.sin(angle), roof + 0.311),
                    0.009,
                    self.copper[2],
                )
        else:
            for i in range(8):
                angle = i * TAU / 8
                xx, yy = cx + 0.32 * math.cos(angle), cy + 0.27 * math.sin(angle)
                obj = block("Harbor crenel", xx, yy, 0.426, 0.116, 0.115, 0.139, self.stone[2 + i % 2], 0.020)
                obj.rotation_euler.z = -angle
            block("Terracotta parapet cap", cx, cy, 0.378, 0.32, 0.23, 0.046, self.brick[1])
        for step in range(3):
            block(
                "Bastion entry treads",
                cx,
                cy + 0.29 + step * 0.052,
                0.239 - step * 0.039,
                0.24,
                0.067,
                0.062,
                self.stone[2],
            )

    def beacon_ruin(self, x, y):
        cx, cy = x + 0.52, y + 0.54
        for j, r in enumerate((0.376, 0.30, 0.237)):
            stacked(
                "Tidemark memorial plinth",
                [ring(cx, cy, 0.114 + j * 0.079, r, 8), ring(cx, cy, 0.189 + j * 0.079, r, 8)],
                [self.stone[1 + j]],
            )
        for level in range(4):
            radius = 0.172 - level * 0.014
            stacked(
                "Fluted tidal memorial",
                [
                    ring(cx, cy, 0.347 + level * 0.092, radius, 10),
                    ring(cx, cy, 0.432 + level * 0.092, radius - 0.009, 10),
                ],
                [self.stone[2 + level % 2]],
            )
        for turn in (0, math.pi / 2):
            chain = []
            for j in range(33):
                angle = TAU * j / 32
                chain.append(
                    point(
                        cx + 0.156 * math.cos(angle) * math.cos(turn),
                        cy + 0.156 * math.cos(angle) * math.sin(turn),
                        0.819 + 0.157 * math.sin(angle),
                    )
                )
            outline("Brass armillary meridian", chain, 0.019, self.brass)
        stone("Orb at the navigators' memorial", cx, cy, 0.82, (0.063, 0.063, 0.063), self.copper[1], 2, True)

    def boat(self, x, y, size, direction):
        levels = ((0.02, 0.56), (0.094, 0.88), (0.15, 1.0))
        outline_xy = (
            (-0.15, -0.24),
            (-0.11, -0.40),
            (0, -0.49),
            (0.11, -0.40),
            (0.15, -0.24),
            (0.16, 0.23),
            (0.105, 0.40),
            (-0.105, 0.40),
            (-0.16, 0.23),
        )
        rings = []
        for height, width in levels:
            rings.append(
                [
                    point(x + dx * width * size, y + dy * direction * size, self.sea + height * size)
                    for dx, dy in outline_xy
                ]
            )
        # point() reverses the row axis, so face winding depends on the vessel's heading.
        if direction > 0:
            rings = [list(reversed(line)) for line in rings]
        stacked(
            "Moored coaster hull",
            rings,
            [self.timber[0], self.timber[2]],
            [[0] * len(outline_xy), [1] * len(outline_xy)],
        )
        weather = rings[-1]
        outline("Coaster gunwale", weather + [weather[0]], 0.016 * size, self.timber[0])
        for i in (-1, 0, 1):
            block(
                "Coaster deck planks",
                x + i * 0.066 * size,
                y,
                self.sea + 0.16 * size,
                0.059 * size,
                0.63 * size,
                0.025 * size,
                self.timber[i + 2],
                0.006,
            )
        for i in (-1, 1):
            block(
                "Canvas-covered cargo",
                x + 0.016 * size,
                y + direction * i * 0.197 * size,
                self.sea + 0.20 * size,
                0.18 * size,
                0.129 * size,
                0.076 * size,
                self.sail if i < 0 else self.brick[0],
                0.032,
            )
        mast = self.sea + 0.55 * size
        post("Moored boat mast", x, y, self.sea + 0.31 * size, 0.017 * size, 0.49 * size, self.timber[0])
        beam(
            "Furled sail on yard",
            (x - 0.109 * size, y, mast),
            (x + 0.112 * size, y, mast - 0.055 * size),
            0.029 * size,
            self.sail,
        )
        for sign in (-1, 1):
            beam(
                "Standing rigging",
                (x, y, mast),
                (x + sign * 0.111 * size, y + sign * 0.25 * size, self.sea + 0.16 * size),
                0.006 * size,
                self.iron,
            )

    def awning(self, x, y, direction, fabric):
        for sign in (-1, 1):
            post(
                "Chandler's stall upright",
                x + 0.23 * direction,
                y + sign * 0.34,
                0.33,
                0.023,
                0.45,
                self.timber[1],
            )
        block("Chandler's counter", x + 0.11 * direction, y, 0.247, 0.29, 0.69, 0.101, self.timber[2])
        for i in range(8):
            y0 = y - 0.37 + i * 0.0925
            verts = []
            for width, h in ((-0.17, 0.69), (0.04, 0.674), (0.19, 0.614), (0.30, 0.57), (0.31, 0.494)):
                verts.extend(
                    [point(x + width * direction, y0, h), point(x + width * direction, y0 + 0.0925, h)]
                )
            form_mesh(
                "Striped canvas and scalloped valance",
                verts,
                [(0, 1, 3, 2), (2, 3, 5, 4), (4, 5, 7, 6), (6, 7, 9, 8)],
                self.sail if i % 2 else fabric,
            )

    def winch(self, x, y, direction):
        block("Treadwheel crane footing", x, y, 0.173, 0.41, 0.35, 0.125, self.stone[1], 0.028)
        for d in (-1, 1):
            post("Treadwheel crane frame", x + d * 0.095, y, 0.411, 0.04, 0.48, self.timber[0])
        wheel = [
            point(x - 0.14, y + 0.158 * math.cos(TAU * j / 24), 0.47 + 0.158 * math.sin(TAU * j / 24))
            for j in range(25)
        ]
        outline("Crane treadwheel rim", wheel, 0.031, self.timber[2])
        for j in range(6):
            beam(
                "Treadwheel spoke",
                (x - 0.14, y, 0.47),
                (x - 0.14, y + 0.14 * math.cos(j * TAU / 6), 0.47 + 0.14 * math.sin(j * TAU / 6)),
                0.016,
                self.timber[1],
            )
        tip = (x + 0.37 * direction, y + 0.052, 0.69)
        beam("Loading jib", (x - 0.10 * direction, y, 0.31), tip, 0.047, self.timber[1])
        beam("Crane backstay", (x - 0.14 * direction, y, 0.19), tip, 0.014, self.iron)
        beam("Crane hoist rope", tip, (tip[0], tip[1], 0.31), 0.009, self.rope)

    def cargo(self, x, y, direction):
        for i, (dx, dy, width, depth, z) in enumerate(
            ((0, 0, 0.22, 0.20, 0.20), (0.12, 0.22, 0.20, 0.19, 0.20), (0.01, 0.02, 0.17, 0.16, 0.34))
        ):
            xx, yy = x + direction * dx, y + dy
            block("Harbor freight chest", xx, yy, z, width, depth, 0.14, self.timber[1 + i % 2])
            for sign in (-1, 1):
                block(
                    "Freight chest iron strapping",
                    xx + sign * width * 0.27,
                    yy,
                    z + 0.072,
                    0.018,
                    depth,
                    0.009,
                    self.iron,
                    0.003,
                )
        coil = []
        for j in range(93):
            angle = j * 0.19
            r = 0.018 + j * 0.00087
            coil.append(
                point(
                    x + 0.24 * direction + r * math.cos(angle), y + 0.08 + r * math.sin(angle) * 0.77, 0.125
                )
            )
        outline("Coiled quay line", coil, 0.008, self.rope)

    def build(self, ruins):
        self.pave()
        self.water()
        self.stone_bridge(self.crossings[0] + 0.5)
        self.drawbridge(self.crossings[1] + 0.5)
        for x, y in tiles(self.rows, "t"):
            self.bastion(x, y, (x in (1, self.width - 2)))
        for x, y in tiles(self.rows, "h"):
            for i in range(4):
                block(
                    "Raised dock terrace",
                    x + 0.5,
                    y + 0.51 - i * 0.052,
                    0.122 + i * 0.045,
                    0.80 - i * 0.081,
                    0.75 - i * 0.143,
                    0.057,
                    self.road[(i + 1) % 4],
                )
            for dx in (-0.262, 0.262):
                post("Terrace end bollard", x + 0.5 + dx, y + 0.35, 0.319, 0.048, 0.17, self.iron)
        for x, y in ruins:
            self.beacon_ruin(x, y)
        for i, (x, y, scale, direction) in enumerate(
            (
                (self.left + 0.37, 1.50, 0.84, 1),
                (self.right - 0.40, 4.42, 0.82, -1),
                (self.left + 0.38, 6.45, 0.80, -1),
                (self.right - 0.40, 9.49, 0.82, 1),
            )
        ):
            previous = set(bpy.data.objects)
            self.boat(x, y, scale, direction)
            edge = self.left if x < self.width / 2 else self.right
            for sign in (-1, 1):
                yy = y + sign * 0.39 * scale
                beam(
                    "Bow or stern line",
                    (edge + (0.10 if x < self.width / 2 else -0.10), yy, 0.145),
                    (x, y + sign * 0.31 * scale, self.sea + 0.16 * scale),
                    0.009,
                    self.timber[1],
                )
            self.moorings.extend(set(bpy.data.objects) - previous)
        self.awning(0.17, 2.02, 1, self.brick[0])
        self.awning(11.86, 7.47, -1, self.copper[0])
        self.awning(11.87, 6.63, -1, self.brick[0])
        self.winch(3.68, 8.53, 1)
        self.winch(8.32, 1.06, -1)
        for x, y, direction in (
            (0.25, 1.02, 1),
            (11.67, 8.12, -1),
            (3.40, 8.75, -1),
            (8.55, 1.21, 1),
            (0.39, 6.42, 1),
        ):
            self.cargo(x, y, direction)
        for edge in (self.left - 0.18, self.right + 0.18):
            for yy in (0.39, 3.4, 5.29, 9.69):
                for j in range(3):
                    theta = TAU * j / 3 + 0.3
                    tx, ty = edge + 0.068 * math.cos(theta), yy + 0.083 * math.sin(theta)
                    post("Dockside casks", tx, ty, 0.208, 0.060, 0.17, self.timber[2])
                    for h in (0.146, 0.242):
                        post("Hoop on dockside cask", tx, ty, h, 0.062, 0.013, self.iron)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("map", choices=("greenwood", "harbor"))
    parser.add_argument("--maps", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--blend", type=Path)
    parser.add_argument(
        "--bare-quay",
        type=Path,
        help="Also render Harbor with its four moorings empty for temporary bridge cards.",
    )
    parser.add_argument("--draft", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    RNG.seed(55031 if args.map == "greenwood" else 55073)
    rows, ruins = read_map(args.maps, args.map)
    model = Greenwood(rows) if args.map == "greenwood" else Harbor(rows)
    model.build(ruins)
    scene = configure_render(model.width, model.length, args.draft)
    scene["map_id"] = args.map
    scene["grid_rows"] = "\n".join(rows)
    scene["ruin_cells"] = " ".join(f"{x},{y}" for x, y in ruins)
    scene.render.filepath = f"//{args.map}-relief.png"
    if args.blend:
        use_relative_browser_paths()
        bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()), compress=True)
    scene.render.filepath = str(args.image.resolve())
    bpy.ops.render.render(write_still=True)
    if args.bare_quay:
        if args.map != "harbor":
            parser.error("--bare-quay requires Harbor")
        for obj in model.moorings:
            obj.hide_render = True
        scene.render.filepath = str(args.bare_quay.resolve())
        bpy.ops.render.render(write_still=True)
    print(f"{args.map}: projected {model.width}x{model.length}, {len(bpy.data.objects)} editable objects")


if __name__ == "__main__":
    main()
