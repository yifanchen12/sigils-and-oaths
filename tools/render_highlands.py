"""Bake the mountain pass, sunken city and castle court for the flat tactical board."""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector, noise

sys.path.insert(0, str(Path(__file__).resolve().parent))
from render_frontier import Greenwood, beam, clamp, ink, palette, ring, stacked, tiles
from render_rivergate import (
    RNG,
    STRETCH,
    block,
    configure_render,
    form_mesh,
    lerp,
    material,
    outline,
    point,
    post,
    read_map,
    stone,
    use_relative_browser_paths,
)


TAU = math.tau


def packed_texture(path):
    image = bpy.data.images.load(str(path.resolve()), check_existing=True)
    if not image.packed_file:
        image.pack()
    image.filepath = "//" + path.name
    for packed in image.packed_files:
        packed.filepath = image.filepath
    return image


def surface_grain(mat, atlas, quadrant, scale, amount, vertical=False):
    """Mirror the material swatch in world space so neighboring meshes share its grain."""
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    position = nodes.new("ShaderNodeNewGeometry").outputs["Position"]
    if vertical:
        rotation = nodes.new("ShaderNodeVectorRotate")
        rotation.rotation_type = "X_AXIS"
        rotation.inputs["Angle"].default_value = 0.72
        links.new(position, rotation.inputs["Vector"])
        position = rotation.outputs["Vector"]

    def transform(source, operation, value=None):
        node = nodes.new("ShaderNodeVectorMath")
        node.operation = operation
        links.new(source, node.inputs[0])
        if operation == "SCALE":
            node.inputs["Scale"].default_value = value
        elif value is not None:
            node.inputs[1].default_value = value
        return node.outputs["Vector"]

    uv = transform(position, "SCALE", scale / 2)
    uv = transform(uv, "FRACTION")
    uv = transform(uv, "SUBTRACT", (0.5, 0.5, 0))
    uv = transform(uv, "ABSOLUTE")
    uv = transform(uv, "SCALE", 0.984)
    uv = transform(uv, "ADD", (quadrant[0] / 2 + 0.004, quadrant[1] / 2 + 0.004, 0))
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = atlas
    links.new(uv, tex.inputs["Vector"])
    shader = nodes.get("Principled BSDF")
    base = shader.inputs["Base Color"].links[0].from_socket
    mix = nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "SOFT_LIGHT"
    mix.inputs[0].default_value = amount
    links.new(base, mix.inputs[1])
    links.new(tex.outputs["Color"], mix.inputs[2])
    links.new(mix.outputs[0], shader.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    bump.inputs["Distance"].default_value = 0.022
    links.new(tex.outputs["Color"], bump.inputs["Height"])
    if shader.inputs["Normal"].is_linked:
        links.new(shader.inputs["Normal"].links[0].from_socket, bump.inputs["Normal"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])


def strata(name, x, y, z, rx, ry, height, layers, mats, slant=0.12):
    """One tilted, fractured outcrop with exposed bedding on its sun-facing edge."""
    n = 12
    phase = RNG.uniform(0, TAU)
    sides = [RNG.uniform(0.80, 1.10) for _ in range(n)]
    split = [RNG.uniform(-0.045, 0.045) for _ in range(n)]
    rings, bands = [], []
    for level, (radius, lift, color) in enumerate(layers):
        course = []
        shades = []
        for i in range(n):
            a = phase + TAU * i / n
            reach = radius * sides[i]
            course.append(
                point(
                    x + rx * (math.cos(a) * reach + slant * lift),
                    y - ry * math.sin(a) * reach,
                    z + height * (lift + radius * (0.108 * math.cos(a + phase) + split[i])),
                )
            )
            shades.append(min(len(mats) - 2, color + int(i % 5 == 2)))
        rings.append(course)
        if level < len(layers) - 1:
            bands.append(shades)
    return stacked(name, rings, mats, bands)


def batched_faces(name, verts, faces, colors, mats):
    obj = form_mesh(name, verts, faces, mats[0])
    for mat in mats[1:]:
        obj.data.materials.append(mat)
    for face, shade in zip(obj.data.polygons, colors):
        face.material_index = shade
    return obj


def stair(x, y, base, mats, width=0.58, rise=0.235, count=5):
    for i in range(count):
        tall = rise * (i + 1) / count
        block(
            "Worn approach step",
            x,
            y - i * 0.063,
            base + tall / 2,
            width - i * 0.015,
            0.11,
            tall,
            mats[i % len(mats)],
            0.012,
        )


def hanging_flag(x, y, z, high, cloth, wood):
    beam("Standard staff", (x, y, z), (x, y, z + high), 0.015, wood)
    half = high * 0.36
    beam("Banner crosspiece", (x - half, y, z + high * 0.91), (x + 0.025, y, z + high * 0.91), 0.011, wood)
    verts = []
    for i in range(7):
        t = i / 6
        yy = y + 0.034 * math.sin(t * 6.1)
        verts.extend(
            [
                point(x - half * t, yy, z + high * 0.89),
                point(x - half * t, yy + 0.016, z + high * (0.43 - math.sin(t * math.pi) * 0.20)),
            ]
        )
    form_mesh("Swallowtail field pennant", verts, [(i, i + 2, i + 3, i + 1) for i in range(0, 12, 2)], cloth)


class Ridgepass(Greenwood):
    def __init__(self, rows):
        super().__init__(rows)
        self.slate = palette(
            "Folded slate and pale quartz", ["#414557", "#586071", "#697789", "#889398", "#b5b7a6", "#c6c4ae"]
        )
        self.larch = palette("Autumn larch needles", ["#795b32", "#9b7738", "#bf9246", "#d7b75a", "#d9c575"])
        self.flag = material("Oxide red signal cloth", "#a9543c")

    def land_color(self, x, y):
        big = noise.noise_vector(Vector((x * 0.44, y * 0.64, 23)))[1]
        grain = noise.noise_vector(Vector((x * 2.3, y * 2.6, 11)))[0]
        near = min(math.hypot(x - a - 0.5, y - b - 0.52) for a, b in self.mountains)
        turf = lerp(ink("#69734e"), ink("#adb075"), clamp(0.5 + big * 1.1 + grain * 0.55))
        turf = lerp(turf, ink("#77808a"), clamp((1.17 - near) * 0.91 + grain * 0.37))
        turf = lerp(turf, ink("#a48673"), clamp((big - 0.07) * 1.38))
        road = self.road_distance(x, y)
        return (
            *lerp(
                turf, lerp(ink("#92785f"), ink("#c5ad83"), clamp(0.50 + grain)), clamp((0.34 - road) / 0.15)
            ),
            1,
        )

    def ridge(self):
        summits = {
            (x, y): (x + RNG.uniform(0.36, 0.63), y + RNG.uniform(0.46, 0.68), RNG.uniform(0.79, 1.20))
            for x, y in self.mountains
        }
        segments = []
        for (x, y), (cx, cy, h) in summits.items():
            angle = RNG.uniform(-0.92, 0.69)
            segments.append(
                (
                    cx - 0.33 * math.cos(angle),
                    cy - 0.33 * math.sin(angle),
                    cx + 0.29 * math.cos(angle),
                    cy + 0.29 * math.sin(angle),
                    h * 0.72,
                    h,
                    0.42,
                )
            )
            for dx, dy in [(1, 0), (0, 1)]:
                if (x + dx, y + dy) in summits:
                    xx, yy, hh = summits[x + dx, y + dy]
                    segments.append((cx, cy, xx, yy, h, hh, 0.49))
        verts, heights, faces, colors = [], [], [], []
        resolution = 13
        nx, ny = self.width * resolution + 1, self.length * resolution + 1
        for j in range(ny):
            for i in range(nx):
                x, y = (
                    (i + RNG.uniform(-0.23, 0.23)) / resolution,
                    (j + RNG.uniform(-0.23, 0.23)) / resolution,
                )
                n = noise.noise_vector(Vector((x * 3.1, y * 3.2, 31)))
                px, py = x + 0.082 * n[0], y + 0.084 * n[1]
                lift = 0
                for ax, ay, bx, by, ha, hb, width in segments:
                    dx, dy = bx - ax, by - ay
                    t = clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
                    offset = math.hypot(px - ax - t * dx, py - ay - t * dy)
                    weight = clamp(1 - offset / width)
                    lift = max(lift, weight**1.35 * (ha + (hb - ha) * t) * (1 - 0.22 * math.sin(t * math.pi)))
                h = max(0, lift * (0.94 + n[2] * 0.23) + min(0.08, lift) * math.sin(x * 11 - y * 9))
                heights.append(h)
                verts.append(point(x, y, self.relief(x, y) - 0.035 + h))
        for j in range(ny - 1):
            for i in range(nx - 1):
                a = j * nx + i
                for face in ((a, a + nx, a + 1), (a + nx, a + nx + 1, a + 1)):
                    h = sum(heights[k] for k in face) / 3
                    if h < 0.032:
                        continue
                    x, y, _ = verts[a]
                    bedding = (h * 9 + x * 1.7 - y * 0.86) % 1
                    shade = 2 + int(h > 0.58) + int(bedding > 0.92) - int(bedding < 0.29) - int(h < 0.18)
                    faces.append(face)
                    colors.append(max(0, min(5, shade)))
        batched_faces(
            "Continuous fractured arêtes, gullies and quartz beds", verts, faces, colors, self.slate
        )

    def scree(self, x, y):
        cx, cy = x + 0.49, y + 0.56
        for i in range(13):
            a = RNG.uniform(0, TAU)
            xx, yy = cx + math.cos(a) * RNG.uniform(0.36, 0.53), cy + math.sin(a) * RNG.uniform(0.29, 0.47)
            r = RNG.uniform(0.035, 0.092)
            stone(
                "Footslope scree",
                xx,
                yy,
                self.relief(xx, yy) + 0.019,
                (r * 1.4, r, r * 0.65),
                self.slate[i % 4],
            )

    def build(self, ruins):
        self.ground("Alpine saddle and sheep tracks")
        self.ridge()
        for x, y in self.mountains:
            self.scree(x, y)
        for i, (x, y) in enumerate(self.forest):
            for j, (ox, oy) in enumerate(
                [(0.26, 0.33), (0.67, 0.27), (0.47, 0.55), (0.75, 0.72), (0.21, 0.77)]
            ):
                if (i + j) % 3 == 0:
                    self.broadleaf(x + ox, y + oy, RNG.uniform(0.53, 0.88), self.larch)
                else:
                    self.fir(x + ox, y + oy, RNG.uniform(0.55, 0.95))
        for i, (x, y) in enumerate(self.hills):
            self.escarpment(x, y, i)
            for j in range(3):
                xx, yy = x + 0.06 * j, y + 0.39 - j * 0.086
                block(
                    "Stone foothold in the turf",
                    xx,
                    yy,
                    self.relief(xx, yy) + 0.01,
                    0.22 - 0.022 * j,
                    0.07,
                    0.043,
                    self.slate[3],
                    0.012,
                )
        for i, (x, y) in enumerate(ruins):
            self.shrine(x, y, bool(i))
            xx, yy = x + 0.73, y + 0.53
            hanging_flag(xx, yy, self.relief(xx, yy), 0.64, self.flag, self.bark)
        self.understory()


class Sunspire(Greenwood):
    def __init__(self, rows):
        super().__init__(rows)
        self.sandstone = palette(
            "Banded sandstone", ["#775344", "#a26e4f", "#c98d62", "#d9a874", "#ebc496", "#efc899"]
        )
        self.ceramic = palette("Glazed solar tiles", ["#327577", "#609187", "#435d79", "#a46e3d"])
        self.fronds = palette("Date palm leaves", ["#385e54", "#517958", "#72975f", "#93a767"])
        self.gold = material("Weathered solar brass", "#b69150", 0.53)
        self.pavers = palette("Old processional road", ["#bc9975", "#cfac83", "#b49573", "#d6b38a"])
        self.flag = material("Faded indigo awning", "#526782")

    def relief(self, x, y):
        n = noise.noise_vector(Vector((x * 0.49, y * 0.59, 13)))[0]
        drift = 0.052 * math.sin(x * 1.7 + y * 0.71 + n * 0.8)
        return 0.045 + n * 0.092 + drift

    def land_color(self, x, y):
        coarse, fine, variation = noise.noise_vector(Vector((x * 0.86, y * 1.3, 34)))
        ridge = math.sin(x * 14.1 + y * 4.3 + coarse * 4.8)
        sand = lerp(ink("#bd825d"), ink("#e7bb7d"), clamp(0.59 + coarse * 0.72 + fine * 0.36 + ridge * 0.075))
        grove = min(math.hypot(x - a - 0.5, y - b - 0.5) for a, b in self.forest)
        sand = lerp(sand, ink("#878c5b"), clamp((0.94 - grove) * 0.72 + variation * 0.16))
        distance = self.road_distance(x, y)
        return (*lerp(sand, ink("#c5a17c"), clamp((0.39 - distance) / 0.18)), 1)

    def palms(self, x, y):
        for j, (ox, oy, h) in enumerate([(0.26, 0.39, 0.77), (0.68, 0.36, 0.68), (0.48, 0.71, 0.55)]):
            xx, yy = x + ox, y + oy
            z = self.relief(xx, yy)
            lean = 0.068 if j % 2 == 0 else -0.065
            trunk = [
                ring(
                    xx + lean * (t / 8) ** 1.5,
                    yy,
                    z + t * h / 8,
                    (0.040 - 0.013 * t / 8) * (0.91 if t % 2 else 1.12),
                    8,
                )
                for t in range(9)
            ]
            stacked(
                "Ringed date palm trunk", trunk, [self.wood[0], self.wood[2]], [[t % 2] * 8 for t in range(8)]
            )
            xx += lean
            verts, faces, colors = [], [], []
            for k in range(15):
                a = k * 2.4 + j
                dx, dy = math.cos(a), math.sin(a)
                length = h * (0.49 if k < 9 else 0.38)

                def rib(t):
                    return (
                        xx + dx * length * t,
                        yy + dy * length * t,
                        z + h + h * (0.45 * t - 0.61 * t * t + 0.08 * (k >= 9) * t),
                    )

                outline(
                    "Arching date palm rib", [point(*rib(t / 4)) for t in range(5)], 0.008, self.fronds[2]
                )
                for n in range(1, 10):
                    t = n / 11
                    px, py, pz = rib(t)
                    for side in (-1, 1):
                        w = 0.087 * (1 - t * 0.68) * side
                        v = len(verts)
                        verts.extend(
                            [
                                point(px, py, pz),
                                point(px + dx * 0.044, py + dy * 0.044, pz - 0.006),
                                point(px - dy * w + dx * 0.058, py + dx * w + dy * 0.058, pz - 0.031),
                            ]
                        )
                        faces.append((v, v + 1, v + 2))
                        colors.append((k + int(n > 6) + int(side == 1)) % 4)
            batched_faces("Pinnate palm crown", verts, faces, colors, self.fronds)

    def sun_dial(self, x, y, broken):
        xx, yy = x + 0.50, y + 0.55
        z = self.relief(xx, yy)
        for i, radius in enumerate([0.38, 0.32, 0.265]):
            post(
                "Octagonal observatory plinth",
                xx,
                yy,
                z + 0.047 + i * 0.056,
                radius,
                0.08,
                self.sandstone[2 + i],
            )
        post("Turquoise mosaic dial", xx, yy, z + 0.184, 0.25, 0.017, self.ceramic[0])
        for angle in (0.25, 1.61):
            path = []
            for n in range(37 if not broken or angle > 1 else 25):
                a = n * TAU / 36
                path.append(
                    point(
                        xx + 0.22 * math.cos(a) * math.cos(angle),
                        yy + 0.22 * math.cos(a) * math.sin(angle) + 0.07 * math.sin(a),
                        z + 0.44 + 0.22 * math.sin(a),
                    )
                )
            outline("Armillary brass great circle", path, 0.022, self.gold)
        stone("Verdigris celestial sphere", xx, yy, z + 0.44, (0.085, 0.085, 0.085), self.ceramic[0], 2, True)
        stair(xx, yy + 0.44, z, self.sandstone[2:4], 0.39, 0.12, 3)

    def terrace(self, x, y, fort):
        xx, yy = x + 0.5, y + 0.48
        z = self.relief(xx, yy)
        for i, (w, depth, h) in enumerate([(0.85, 0.71, 0.10), (0.78, 0.63, 0.09), (0.72, 0.58, 0.065)]):
            block(
                "Sun court stepped retaining wall",
                xx,
                yy,
                z + (0.052, 0.14, 0.213)[i],
                w,
                depth,
                h,
                self.sandstone[2 + i],
                0.023,
            )
        stair(xx, yy + 0.47, z, self.sandstone[2:5], 0.44)
        if fort:
            for side in (-1, 1):
                for i, width in enumerate([0.20, 0.174, 0.146, 0.19]):
                    block(
                        "Split solar gate pylon",
                        xx + side * 0.245,
                        yy - 0.11,
                        z + 0.30 + i * 0.103,
                        width,
                        0.225,
                        0.108,
                        self.ceramic[0] if i == 2 else self.sandstone[2 + i % 3],
                        0.012,
                    )
            block("Chipped painted gate lintel", xx, yy - 0.11, z + 0.69, 0.70, 0.24, 0.10, self.sandstone[4])
            block("Indigo frieze", xx, yy + 0.014, z + 0.69, 0.65, 0.016, 0.040, self.ceramic[2], 0.003)
            hanging_flag(xx + 0.29, yy - 0.04, z + 0.68, 0.38, self.flag, self.gold)
        else:
            for i in range(3):
                block(
                    "Remnant of terrace parapet",
                    xx - 0.22 + i * 0.167,
                    yy - 0.215,
                    z + 0.287,
                    0.157,
                    0.094,
                    0.091,
                    self.sandstone[2 + i % 2],
                    0.008,
                )
            corners = [(-0.26, -0.17), (0.24, -0.17)]
            for i, (ax, ay) in enumerate(corners):
                for j in range(1 + (x + y + i) % 3):
                    post(
                        "Fractured column on the raised terrace",
                        xx + ax,
                        yy + ay,
                        z + 0.286 + j * 0.09,
                        0.046 + 0.006 * (j == 0),
                        0.089,
                        self.sandstone[(2 + j) % 5],
                    )

    def needle(self, x, y, broken):
        base = self.relief(x, y) + 0.47
        for i, d in enumerate([0.39, 0.32, 0.28]):
            block(
                "Obelisk foundation courses", x, y, base + i * 0.063, d, d, 0.073, self.sandstone[3 + i % 2]
            )
        levels = [(0.12, 0.139), (0.20, 0.138), (0.225, 0.134), (0.52, 0.110)]
        if not broken:
            levels.extend([(0.87, 0.082), (1.02, 0.008)])
        stacked(
            "Wind-worn solar needle",
            [ring(x, y, base + z, r, 4, math.pi / 4) for z, r in levels],
            self.sandstone,
            [[3, 2, 3, 4] if i != 1 else [1] * 4 for i in range(len(levels) - 1)],
        )
        if not broken:
            for j in range(5):
                xx = x + (0.018 if j % 2 else -0.018)
                block(
                    "Blue enamel on the sun needle",
                    xx,
                    y + 0.082,
                    base + 0.29 + j * 0.084,
                    0.052 - j * 0.006,
                    0.018,
                    0.025,
                    self.ceramic[2],
                    0.003,
                )

    def build(self, ruins):
        self.ground("Wind-streaked sand, palm groves and the buried causeway")
        for x, y in self.mountains:
            for ox, oy, radius, h in [
                (0.47, 0.58, 0.49, 0.8),
                (0.23, 0.68, 0.31, 0.45),
                (0.74, 0.48, 0.29, 0.54),
            ]:
                xx, yy = x + ox, y + oy
                strata(
                    "Eroded sandstone mesa",
                    xx,
                    yy,
                    self.relief(xx, yy) - 0.04,
                    radius,
                    radius * 0.82,
                    h,
                    [
                        (1, 0, 0),
                        (0.92, 0.23, 1),
                        (0.73, 0.33, 1),
                        (0.79, 0.42, 2),
                        (0.68, 0.58, 1),
                        (0.52, 0.83, 3),
                        (0.59, 0.87, 2),
                        (0.48, 1.0, 3),
                    ],
                    self.sandstone,
                )
        for x, y in self.forest:
            self.palms(x, y)
        for x, y in tiles(self.rows, "ht"):
            self.terrace(x, y, self.rows[y][x] == "t")
        for i, (x, y) in enumerate(ruins):
            self.sun_dial(x, y, bool(i))
        for j in range(self.length * 6):
            for i in range(self.width * 4 + 1):
                xx, yy = (i + (j % 2) * 0.5) / 4, j / 6
                cover = noise.noise_vector(Vector((xx * 1.05, yy * 1.22, 10)))[2]
                if self.road_distance(xx, yy) > 0.28 or cover < -0.22:
                    continue
                # Follow the underlying dunes at every corner. Sand can cover a corner
                # without leaving a floating square and a dark gap underneath it.
                edge = [
                    (0.117, 0.064),
                    (0.095, 0.078),
                    (-0.104, 0.074),
                    (-0.12, 0.052),
                    (-0.118, -0.062),
                    (-0.095, -0.078),
                    (0.107, -0.076),
                    (0.12, -0.054),
                ]
                verts = []
                for dx, dy in edge:
                    x, y = xx + dx + RNG.uniform(-0.009, 0.009), yy + dy + RNG.uniform(-0.007, 0.007)
                    z = self.relief(x, y) + 0.003 + 0.025 * cover + RNG.uniform(-0.006, 0.006)
                    verts.append(point(x, y, z))
                form_mesh(
                    "Partly buried flagstone", verts, [tuple(reversed(range(8)))], RNG.choice(self.pavers)
                )
        self.needle(0.49, 0.59, False)
        self.needle(11.49, 9.62, True)
        for side in (0, 1):
            for i in range(7):
                xx = 0.16 if side == 0 else self.width - 0.16
                yy = 2.0 + i * 0.72 + 0.32 * side
                z = self.relief(xx, yy)
                block("Buried gallery foundation", xx, yy, z + 0.03, 0.27, 0.56, 0.08, self.sandstone[2])
                n = (2, 5, 4, 1, 3, 5, 2)[(i + side) % 7]
                for j in range(n):
                    post(
                        "Fluted colonnade drum",
                        xx,
                        yy,
                        z + 0.105 + j * 0.092,
                        0.083 - j * 0.005,
                        0.089,
                        self.sandstone[2 + j % 3],
                    )
                if n == 5:
                    block("Glazed palm capital", xx, yy, z + 0.57, 0.213, 0.211, 0.082, self.ceramic[1])
        verts, faces, colors = [], [], []
        for _ in range(1450):
            xx, yy = RNG.uniform(0, self.width), RNG.uniform(0, self.length)
            if self.road_distance(xx, yy) < 0.37:
                continue
            z = self.relief(xx, yy)
            n = noise.noise_vector(Vector((xx * 0.71, yy * 0.80, 7)))[0]
            w = RNG.uniform(0.012, 0.038)
            index = len(verts)
            verts.extend(
                [
                    point(xx - w, yy, z + 0.012),
                    point(xx, yy - w * 0.6, z + 0.014),
                    point(xx + w, yy, z + 0.011),
                    point(xx, yy + w * 0.57, z + 0.019),
                ]
            )
            faces.append((index, index + 1, index + 2, index + 3))
            colors.append(int(n > 0.22) + int(n < -0.28) * 2)
        batched_faces(
            "Desert gravel and old ceramic fragments",
            verts,
            faces,
            colors,
            [self.sandstone[3], self.pavers[2], self.ceramic[1]],
        )


class Citadel(Greenwood):
    def __init__(self, rows, mosaic):
        super().__init__(rows)
        self.granite = palette("Court granite", ["#697780", "#899391", "#9aa19c", "#b0afa2", "#c2bcab"])
        self.lane = palette("Ivory processional paving", ["#b9aa90", "#cfbfa4", "#dcceb4", "#d3c5ac"])
        self.mortar = material("Cool recessed lime joints", "#626e71")
        self.copper = palette(
            "Oxidised copper roofs", ["#345e61", "#477477", "#6a9891", "#a69a62"], roughness=0.64
        )
        self.blue = material("Deep madder field standard", "#914851")
        self.leaf = palette("Yew and clipped myrtle", ["#365843", "#4e7051", "#769160"])
        self.sun = material("Brass dial rim", "#a38d5d", 0.57)
        self.mosaic = mosaic

    def relief(self, x, y):
        return 0.04

    def pavement(self):
        block(
            "Grouted courtyard foundation",
            self.width / 2,
            self.length / 2,
            -0.045,
            self.width + 1,
            self.length + 1,
            0.15,
            self.mortar,
            0,
        )
        verts, faces, colors = [], [], []
        for j in range(-1, self.length * 5 + 2):
            yy = j / 5
            for i in range(-2, self.width * 3 + 3):
                xx = (i + (j % 2) * 0.50) / 3
                road = self.road_distance(xx, yy)
                a, b = 1 / 6 - 0.005, 0.10 - 0.005
                corners = [(xx - a, yy + b), (xx + a, yy + b), (xx + a, yy - b), (xx - a, yy - b)]
                base = len(verts)
                h = 0.048 + RNG.uniform(-0.002, 0.002)
                for x, y in corners:
                    verts.append(point(x, y, h - 0.012))
                for x, y in corners:
                    verts.append(point(x + (xx - x) * 0.036, y + (yy - y) * 0.045, h))
                shade = int(road < 0.40) * len(self.granite)
                shade += RNG.choices([0, 1, 2, 3], [1, 3, 5, 2])[0]
                faces.append(tuple(range(base + 4, base + 8)))
                colors.append(shade)
                for k in range(4):
                    m = (k + 1) % 4
                    faces.append((base + k, base + m, base + 4 + m, base + 4 + k))
                    colors.append(shade)
        batched_faces(
            "Individually chamfered promenade and court pavers",
            verts,
            faces,
            colors,
            self.granite + self.lane,
        )

    def roundel(self):
        x, y, z, radius = 6.0, 5.0, 0.061, 1.13
        mat = material("Eight winds courtyard mosaic", "#928b76", roughness=0.92, texture_scale=71)
        picture = packed_texture(self.mosaic)
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = picture
        mat.node_tree.links.new(
            tex.outputs["Color"], mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"]
        )
        n = 100
        verts = [point(x, y, z)] + ring(x, y, z, radius, n)
        obj = form_mesh(
            "Inlaid rose of the eight winds", verts, [(0, i + 1, (i + 1) % n + 1) for i in range(n)], mat
        )
        uv = obj.data.uv_layers.new(name="Stone inlay projection")
        for loop in obj.data.loops:
            vx, vy, _ = verts[loop.vertex_index]
            uv.data[loop.index].uv = (
                (vx - x) / (2 * radius) + 0.5,
                (vy + y * STRETCH) / (2 * radius * STRETCH) + 0.5,
            )
        for r in (radius + 0.012, radius + 0.055):
            track = ring(x, y, z + 0.003, r, n)
            outline("Inlaid brass compass circumference", track + [track[0]], 0.011, self.sun)

    def bastion(self, x, y, variant):
        xx, yy, z = x + 0.5, y + 0.55, 0.05
        for i, (w, d, h) in enumerate([(0.79, 0.62, 0.10), (0.70, 0.53, 0.10), (0.67, 0.51, 0.065)]):
            block(
                "Ashlar fighting terrace", xx, yy, z + (0.05, 0.145, 0.222)[i], w, d, h, self.granite[2 + i]
            )
        stair(xx, yy + 0.39, z, self.lane, 0.40, 0.25)
        for s in (-1, 1):
            px, py = xx + s * 0.23, yy - 0.08
            post("Octagonal sentry turret", px, py, z + 0.36, 0.102, 0.27, self.granite[1])
            post("Pale stone cornice", px, py, z + 0.495, 0.127, 0.061, self.lane[2])
            if s == 1 or variant % 3 != 0:
                stacked(
                    "Coursed pavilion roof",
                    [
                        ring(px, py, z + h, r, 8, math.pi / 8)
                        for h, r in [
                            (0.50, 0.154),
                            (0.53, 0.163),
                            (0.60, 0.105),
                            (0.612, 0.115),
                            (0.70, 0.044),
                            (0.74, 0.010),
                        ]
                    ],
                    self.copper,
                    [[0] * 8, [1, 1, 2, 1, 1, 1, 2, 1], [0] * 8, [1, 2, 2, 1, 1, 2, 1, 1], [3] * 8],
                )
            else:
                for j in range(4):
                    a = j * TAU / 4
                    block(
                        "Crenellation",
                        px + 0.078 * math.cos(a),
                        py + 0.078 * math.sin(a),
                        z + 0.56,
                        0.064,
                        0.056,
                        0.09,
                        self.lane[1],
                        0.006,
                    )
        block("Stone parapet between the towers", xx, yy - 0.12, z + 0.33, 0.34, 0.073, 0.14, self.granite[3])
        hanging_flag(xx - 0.02, yy - 0.15, z + 0.37, 0.37, self.blue, self.sun)

    def raised_loggia(self, x, y):
        xx, yy = x + 0.5, y + 0.44
        for i in range(3):
            block(
                "Balustraded garden terrace",
                xx,
                yy,
                0.10 + i * 0.072,
                0.84 - 0.053 * i,
                0.67 - 0.047 * i,
                0.083,
                self.granite[i + 2],
            )
        stair(xx, yy + 0.44, 0.05, self.lane, 0.44)
        for j in range(6):
            post("Carved stone baluster", xx - 0.31 + j * 0.124, yy - 0.22, 0.36, 0.022, 0.16, self.lane[1])
        block("Balustrade coping", xx, yy - 0.22, 0.449, 0.70, 0.065, 0.052, self.lane[2])

    def arcade(self, x, y):
        """Open bays along the north and south palace walls, clear of tile centres."""
        for j in range(5):
            px = x + j * 0.51
            block("Arcade pier base", px, y, 0.095, 0.15, 0.21, 0.12, self.granite[2])
            block("Arcade shaft", px, y, 0.24, 0.078, 0.145, 0.25, self.granite[4])
            block("Arcade impost", px, y, 0.375, 0.139, 0.191, 0.056, self.lane[1])
            if j == 4:
                continue
            cx = px + 0.255
            for k in range(9):
                a, b = k * math.pi / 9, (k + 1) * math.pi / 9 - 0.015
                profile = [
                    (cx + r * math.cos(t), 0.385 + r * 0.82 * math.sin(t))
                    for r, t in [(0.198, a), (0.262, a), (0.262, b), (0.198, b)]
                ]
                verts = [point(xx, y + edge, zz) for edge in (-0.081, 0.081) for xx, zz in profile]
                form_mesh(
                    "Weathered arcade voussoir",
                    verts,
                    [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)],
                    self.lane[(j + k) % 3],
                )
        block("Cloister cornice", x + 1.02, y, 0.625, 2.23, 0.23, 0.070, self.lane[1])
        # Two sloping banks of overlapping copper roofing.
        for side in (-1, 1):
            for j in range(14):
                for k in range(3):
                    tile = block(
                        "Patinated overlapping roof sheet",
                        x - 0.02 + j * 0.16,
                        y + side * (0.127 - k * 0.046),
                        0.679 + k * 0.036,
                        0.158,
                        0.079,
                        0.026,
                        self.copper[1 + int((j + 2 * k) % 5 == 0)],
                        0.004,
                    )
                    tile.rotation_euler.x = -side * 0.53
        beam("Cloister ridge roll", (x - 0.10, y, 0.783), (x + 2.16, y, 0.783), 0.020, self.copper[0])

    def build(self, ruins):
        self.pavement()
        self.roundel()
        for x in (0.24, self.width - 2.30):
            for y in (0.15, self.length - 0.025):
                self.arcade(x, y)
        for i, (x, y) in enumerate(tiles(self.rows, "t")):
            self.bastion(x, y, i)
        for x, y in tiles(self.rows, "h"):
            self.raised_loggia(x, y)
        for x, y in self.forest:
            xx, yy = x + 0.5, y + 0.54
            block("Moulded garden curb", xx, yy, 0.11, 0.82, 0.67, 0.11, self.lane[0])
            block("Dark garden earth", xx, yy, 0.17, 0.75, 0.60, 0.065, self.turf[0])
            for j, (dx, dy, h) in enumerate(
                [(-0.25, -0.08, 0.68), (0.02, -0.18, 0.91), (0.22, 0.015, 0.72), (-0.10, 0.17, 0.53)]
            ):
                rings = [
                    ring(xx + dx, yy + dy, 0.18 + h * lift, r, 11, j)
                    for lift, r in [(0, 0.056), (0.20, 0.13), (0.50, 0.118), (0.78, 0.069), (1, 0.007)]
                ]
                stacked(
                    "Clipped cypress",
                    rings,
                    self.leaf,
                    [[0] * 11, [1 + (k % 4 == 0) for k in range(11)], [1] * 11, [2] * 11],
                )
        for x, y in ruins:
            xx, yy = x + 0.50, y + 0.48
            for j, (r, h) in enumerate([(0.40, 0.09), (0.31, 0.16), (0.25, 0.24)]):
                post("Garden shrine circular step", xx, yy, h, r, 0.071, self.lane[j])
            for j in range(5):
                a = math.pi * (j / 4)
                px, py = xx + 0.24 * math.cos(a), yy - 0.20 * math.sin(a)
                post("Open cloister column", px, py, 0.41, 0.035, 0.34, self.granite[4])
                post("Cloister capital", px, py, 0.59, 0.055, 0.04, self.lane[2])
            arc = [
                point(xx + 0.24 * math.cos(a / 24 * math.pi), yy - 0.20 * math.sin(a / 24 * math.pi), 0.62)
                for a in range(25)
            ]
            outline("Semicircle of the cloister cornice", arc, 0.041, self.lane[1])
            post("Bronze votive basin", xx, yy, 0.30, 0.115, 0.069, self.copper[2])
        # The open court is framed by low parapets at the extreme sides only.
        for x in (0.075, self.width - 0.075):
            for j in range(20):
                y = 0.23 + j * 0.5
                block("Outer court parapet", x, y, 0.12, 0.12, 0.43, 0.15, self.granite[2])
                block("Pale parapet coping", x, y, 0.207, 0.145, 0.45, 0.035, self.lane[0])
                if j % 3 == 0:
                    block("Parapet pier", x, y + 0.215, 0.19, 0.185, 0.145, 0.28, self.granite[3])
                    post("Brass finial", x, y + 0.215, 0.36, 0.05, 0.073, self.sun)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("map", choices=("ridgepass", "sunspire", "citadel"))
    parser.add_argument("--maps", type=Path, required=True)
    parser.add_argument("--blend", type=Path)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--draft", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    RNG.seed({"ridgepass": 56091, "sunspire": 56098, "citadel": 56099}[args.map])
    rows, ruins = read_map(args.maps, args.map)
    if args.map == "citadel":
        model = Citadel(
            rows, Path(__file__).resolve().parents[1] / "assets/art/model_sources/citadel-windrose-v1.png"
        )
    else:
        model = Ridgepass(rows) if args.map == "ridgepass" else Sunspire(rows)
    model.build(ruins)
    texture_folder = Path(__file__).resolve().parents[1] / "assets/art/model_sources"
    atlas = packed_texture(texture_folder / "highlands-surfaces-v1.png")
    if args.map == "ridgepass":
        surface_grain(bpy.data.materials["Grass, soil and worn track"], atlas, (0, 1), 0.67, 0.83)
        for mat in model.slate:
            surface_grain(mat, atlas, (1, 0), 0.82, 0.94, True)
    elif args.map == "sunspire":
        surface_grain(bpy.data.materials["Grass, soil and worn track"], atlas, (1, 1), 0.79, 0.76)
        for mat in model.pavers + model.sandstone:
            surface_grain(mat, atlas, (0, 0), 0.79, 0.65, True)
    else:
        for mat in model.granite + model.lane:
            surface_grain(mat, atlas, (0, 0), 0.74, 0.85)
    scene = configure_render(model.width, model.length, args.draft)
    scene["map_id"] = args.map
    scene["grid_rows"] = "\n".join(rows)
    scene["ruin_cells"] = " ".join(f"{x},{y}" for x, y in ruins)
    scene.render.filepath = f"//{args.map}-relief.png"
    if args.blend:
        use_relative_browser_paths()
        bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()), compress=True, relative_remap=False)
    scene.render.filepath = str(args.image.resolve())
    bpy.ops.render.render(write_still=True)
    print(f"{args.map}: projected {model.width}x{model.length}, {len(bpy.data.objects)} editable objects")


if __name__ == "__main__":
    main()
