"""Model and render the Rivergate battlefield using Blender 4.5 LTS."""

import argparse
import json
import math
import random
import re
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector, noise


TILT = math.radians(16)
STRETCH = 1 / math.cos(TILT)
WATER = -0.16
RNG = random.Random(5426)
GRASS = ("#426741", "#719846", "#a9b870")
STONE = ("#556268", "#707779", "#9d9380")


def srgb(hex_color):
    channels = (int(hex_color[index:index + 2], 16) / 255 for index in (1, 3, 5))
    return tuple(value / 12.92 if value < 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels)


def lerp(left, right, amount):
    return tuple(a + (b - a) * amount for a, b in zip(left, right))


def point(x, row, height):
    return x, -row * STRETCH, height


def material(name, color, roughness=0.82, texture_scale=12, bump_strength=0.13):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*srgb(color), 1.0)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    surface = nodes.get("Principled BSDF")
    surface.inputs["Roughness"].default_value = roughness
    position = nodes.new("ShaderNodeNewGeometry")
    grain = nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = texture_scale
    grain.inputs["Detail"].default_value = 3.0
    links.new(position.outputs["Position"], grain.inputs["Vector"])
    tone = nodes.new("ShaderNodeValToRGB")
    tone.color_ramp.elements[0].position = 0.10
    tone.color_ramp.elements[0].color = (*lerp(srgb(color), (0, 0, 0), 0.34), 1)
    tone.color_ramp.elements[1].position = 0.90
    tone.color_ramp.elements[1].color = (*lerp(srgb(color), (1, 1, 1), 0.08), 1)
    links.new(grain.outputs["Fac"], tone.inputs["Fac"])
    links.new(tone.outputs["Color"], surface.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = 0.035
    links.new(grain.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], surface.inputs["Normal"])
    return mat


def form_mesh(name, verts, faces, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    return obj


def block(name, x, row, z, width, length, height, mat, bevel=0.018):
    a, b, c = width / 2, length * STRETCH / 2, height / 2
    verts = [(-a, -b, -c), (a, -b, -c), (a, b, -c), (-a, b, -c),
             (-a, -b, c), (a, -b, c), (a, b, c), (-a, b, c)]
    faces = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    obj = form_mesh(name, verts, faces, mat)
    obj.location = point(x, row, z)
    if bevel:
        edge = obj.modifiers.new("Worn edges", "BEVEL")
        edge.width = bevel
        edge.segments = 2
    return obj


def stone(name, x, row, z, scale, mat, subdivisions=1, smooth=False):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=point(x, row, z))
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler.z = RNG.uniform(0, 6.28)
    obj.data.materials.append(mat)
    if smooth and subdivisions == 2:
        for vertex in obj.data.vertices:
            irregularity = noise.noise_vector(vertex.co * 3.7 + Vector((x, row, 8)))[0]
            vertex.co *= 1.0 + 0.20 * irregularity
    for face in obj.data.polygons:
        face.use_smooth = smooth
    return obj


def post(name, x, row, z, radius, height, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius, depth=height, location=point(x, row, z))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)


def outline(name, positions, width, mat):
    curves = bpy.data.curves.new(name, "CURVE")
    curves.dimensions = "3D"
    curves.bevel_depth = width
    curves.bevel_resolution = 2
    stream = curves.splines.new("POLY")
    stream.points.add(len(positions) - 1)
    for vertex, coordinates in zip(stream.points, positions):
        vertex.co = (*coordinates, 1)
    curves.materials.append(mat)
    obj = bpy.data.objects.new(name, curves)
    bpy.context.collection.objects.link(obj)
    return obj


def read_map(path):
    source = path.read_text(encoding="utf-8")
    rivergate = re.search(r'"id": "rivergate".*?\n\},', source, re.S).group()
    rows = json.loads(re.search(r'"rows": (\[[^\n]*\])', rivergate).group(1))
    ruin_list = re.search(r'"ruins": \[(.*?)\]', rivergate).group(1)
    ruins = [(int(x), int(y)) for x, y in re.findall(r"Vector2i\((\d+), (\d+)\)", ruin_list)]
    return rows, ruins


class Landscape:
    def __init__(self, rows):
        self.rows = rows
        self.width, self.length = len(rows[0]), len(rows)
        self.hills = [(x + 0.47, y + 0.52) for y, row in enumerate(rows) for x, tile in enumerate(row) if tile == "h"]
        self.roads = {(x, y) for y, row in enumerate(rows) for x, tile in enumerate(row) if tile in "rb"}
        self.segments = {
            (x, y): [(dx, dy) for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)] if (x + dx, y + dy) in self.roads]
            for x, y in self.roads
        }
        self.stones = [material("River limestone " + str(i), tone) for i, tone in enumerate(STONE)]
        self.wood = [material("Bridge timber " + str(i), tone, texture_scale=20) for i, tone in enumerate(("#65442f", "#886042", "#b58756", "#a3784c"))]
        self.leaves = [material("Canopy " + str(i), tone, texture_scale=33) for i, tone in enumerate(("#294f3f", "#386045", "#4e784b", "#739745", "#94a65b"))]
        self.brass = material("Copper fittings", "#a98750", 0.52, 25)
        self.bark = material("Oak bark", "#644c34", 0.90, 18)
        self.relic = material("Verdigris inlay", "#6fac97", 0.34, 24)

    def banks(self, x):
        return (4 + 0.14 * math.sin(x * 1.07) + 0.06 * math.sin(x * 3.2),
                6 + 0.12 * math.sin(x * 1.13 + 1.2) + 0.07 * math.sin(x * 2.7))

    def shore_distance(self, x, row):
        north, south = self.banks(x)
        return max(north - row, row - south)

    def relief(self, x, row):
        shore = self.shore_distance(x, row)
        terrain = noise.noise_vector(Vector((x * 0.73, row * 0.73, 9.0)))[0]
        hills = sum(0.43 * math.exp(-((x - cx) ** 2 / 0.37 + (row - cy) ** 2 / 0.34)) for cx, cy in self.hills)
        height = -0.39 + 0.54 * min(1, max(0, (shore + 0.22) / 0.43)) + terrain * 0.11 + hills
        return height

    def road_distance(self, x, row):
        # Wind the road around roots and rocks, keeping the bridge ends centered.
        inland = min(1.0, max(0.0, self.shore_distance(x, row) * 1.4))
        x += 0.11 * math.sin(row * 2.7 + x) * inland
        row += 0.10 * math.sin(x * 3.5 - row * 0.82) * inland
        column, tile_row = math.floor(x), math.floor(row)
        best = 2.0
        for iy in range(tile_row - 1, tile_row + 2):
            for ix in range(column - 1, column + 2):
                if (ix, iy) not in self.roads:
                    continue
                sx, sy = x - ix - 0.5, row - iy - 0.5
                best = min(best, math.hypot(sx, sy))
                for dx, dy in self.segments[ix, iy]:
                    reach = min(0.53, max(0, sx * dx + sy * dy))
                    best = min(best, math.hypot(sx - dx * reach, sy - dy * reach))
        return best

    def land_color(self, x, row):
        shade = noise.noise_vector(Vector((x * 1.8, row * 1.8, 18.0)))[0]
        region = noise.noise_vector(Vector((x * 0.63, row * 0.58, 12.0)))[1]
        grass = lerp(srgb(GRASS[0]), srgb(GRASS[1]), max(0, min(1, 0.56 + shade * 0.36 + region * 0.8)))
        grass = lerp(grass, srgb(GRASS[2]), max(0, shade + region * 0.55) * 0.56)
        shore = self.shore_distance(x, row)
        if shore < 0.44:
            grass = lerp(grass, srgb("#9d8960"), max(0, min(1, (0.48 - shore) / 0.49)))
        distance = self.road_distance(x, row)
        road = max(0, min(1, (0.30 - distance + shade * 0.13 + region * 0.06) / 0.13))
        dirt = lerp(srgb("#92714e"), srgb("#c8ab7e"), 0.49 + shade * 0.38)
        wheel_wear = math.exp(-((distance - 0.105) / 0.033) ** 2) * 0.22
        dirt = lerp(dirt, srgb("#796349"), wheel_wear)
        return (*lerp(grass, dirt, road), 1)

    def ground(self):
        mat = material("Grass, soil and worn track", "#748f52", texture_scale=20, bump_strength=0.21)
        nodes = mat.node_tree.nodes
        colors = nodes.new("ShaderNodeVertexColor")
        colors.layer_name = "Terrain palette"
        links = mat.node_tree.links
        granules = nodes.new("ShaderNodeMixRGB")
        granules.blend_type = "MULTIPLY"
        granules.inputs[0].default_value = 0.38
        links.new(colors.outputs["Color"], granules.inputs[1])
        links.new(nodes.get("Noise Texture").outputs["Fac"], granules.inputs[2])
        links.new(granules.outputs["Color"], nodes.get("Principled BSDF").inputs["Base Color"])
        intervals = 16
        nx, ny = int((self.width + 0.9) * intervals), int((self.length + 0.9) * intervals)
        verts, faces, pigment = [], [], []
        for iy in range(ny + 1):
            row = -0.45 + iy * (self.length + 0.9) / ny
            for ix in range(nx + 1):
                x = -0.45 + ix * (self.width + 0.9) / nx
                verts.append(point(x, row, self.relief(x, row)))
                pigment.append(self.land_color(x, row))
                if ix < nx and iy < ny:
                    v = iy * (nx + 1) + ix
                    faces.append((v, v + nx + 1, v + nx + 2, v + 1))
        surface = form_mesh("Continuous sculpted valley", verts, faces, mat)
        layer = surface.data.color_attributes.new(name="Terrain palette", type="FLOAT_COLOR", domain="POINT")
        for index, color in enumerate(pigment):
            layer.data[index].color = color
        for polygon in surface.data.polygons:
            polygon.use_smooth = True

    def river(self):
        mat = material("Slow teal river", "#318599", 0.29, 10, 0.32)
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        surface = nodes.get("Principled BSDF")
        surface.inputs["Metallic"].default_value = 0.07
        surface.inputs["Coat Weight"].default_value = 0.35
        flow = nodes.new("ShaderNodeVectorMath")
        flow.operation = "MULTIPLY"
        flow.inputs[1].default_value = (0.44, 3.6, 1.0)
        links.new(nodes.get("Geometry").outputs["Position"], flow.inputs[0])
        links.new(flow.outputs["Vector"], nodes.get("Noise Texture").inputs["Vector"])
        colors = nodes.new("ShaderNodeVertexColor")
        colors.layer_name = "Depth and water color"
        sheen = nodes.new("ShaderNodeMixRGB")
        sheen.blend_type = "MULTIPLY"
        sheen.inputs[0].default_value = 0.28
        links.new(colors.outputs["Color"], sheen.inputs[1])
        links.new(nodes.get("Noise Texture").outputs["Fac"], sheen.inputs[2])
        links.new(sheen.outputs["Color"], surface.inputs["Base Color"])
        verts, faces, pigment = [], [], []
        nx, ny = 80, 29
        for j in range(ny + 1):
            row = 3.45 + j * 3.10 / ny
            for i in range(nx + 1):
                x = -0.5 + i * (self.width + 1) / nx
                verts.append(point(x, row, WATER))
                shallowness = max(0, min(1, 1.0 + self.shore_distance(x, row) / 0.66))
                current = math.sin(x * 1.84 + row * 6.6) * 0.035
                pigment.append((*lerp(srgb("#196680"), srgb("#66b8a4"), max(0, min(1, shallowness + current))), 1))
                if i < nx and j < ny:
                    v = j * (nx + 1) + i
                    faces.append((v, v + nx + 1, v + nx + 2, v + 1))
        river = form_mesh("River surface", verts, faces, mat)
        depth = river.data.color_attributes.new(name="Depth and water color", type="FLOAT_COLOR", domain="POINT")
        for index, pigment_value in enumerate(pigment):
            depth.data[index].color = pigment_value
        foam = material("Light at the shallows", "#7bb5aa", 0.61, 26, 0.05)
        for side in range(2):
            for index in range(24):
                center = (index + RNG.uniform(-0.35, 0.35)) * 0.42
                length = RNG.uniform(0.13, 0.43)
                points = []
                for step in range(6):
                    x = center + step * length / 5
                    edge = self.banks(x)[side]
                    row = edge + (1 if side == 0 else -1) * (0.04 + math.sin(step / 5 * math.pi) * 0.046)
                    points.append(point(x, row, WATER + 0.008))
                outline("Near-bank glint", points, RNG.uniform(0.005, 0.011), foam)

    def bridge(self, x, name):
        for row in (3.84, 4.54, 5.47, 6.17):
            anchor = row in (3.84, 6.17)
            block(name + " limestone footing", x, row, -0.17, 0.91, 0.30, 0.40, self.stones[0], 0.036)
            if not anchor:
                for course in range(3):
                    block(name + " masonry pier", x, row, -0.08 + course * 0.089, 0.75 - course * 0.05, 0.25, 0.105, self.stones[course], 0.022)
            else:
                for offset in (-0.35, 0.35):
                    block(name + " wingwall", x + offset, row, 0.22, 0.20, 0.34, 0.24, self.stones[1], 0.022)
        for side in (-1, 1):
            ex = x + 0.32 * side
            block(name + " stringer", ex, 5.0, 0.20, 0.11, 2.50, 0.13, self.wood[0], 0.025)
            block(name + " handrail", ex, 5.0, 0.45, 0.048, 2.38, 0.061, self.wood[2], 0.011)
            for row in (3.84, 4.20, 4.60, 5.00, 5.40, 5.80, 6.16):
                block(name + " rail post", ex, row, 0.352, 0.06, 0.063, 0.25, self.wood[1], 0.012)
                if row in (3.84, 6.16):
                    block(name + " end cap", ex, row, 0.486, 0.085, 0.101, 0.04, self.brass, 0.009)
        for i in range(34):
            row = 3.76 + i * 0.0735
            warm = 1 if name == "West Bridge" else 2
            block(name + " deck board", x, row, 0.277 + RNG.uniform(-0.004, 0.004), RNG.uniform(0.695, 0.74), 0.069,
                  0.069, RNG.choice(self.wood[warm:]), 0.008)

    def grove(self, x, row):
        for _ in range(8):
            tx, ty = x + RNG.uniform(0.15, 0.85), row + RNG.uniform(0.16, 0.84)
            if self.road_distance(tx, ty) < 0.29:
                continue
            base = self.relief(tx, ty)
            height = RNG.uniform(0.43, 0.79)
            post("Deciduous trunk", tx, ty, base + height / 2, 0.035, height, self.bark)
            for level in range(8):
                radius = RNG.uniform(0.095, 0.195)
                angle = level * 2.39
                offset = 0.16 if level < 5 else 0.08
                shade = min(4, RNG.randrange(2) + level // 2)
                stone("Layered crown", tx + math.cos(angle) * offset, ty + math.sin(angle) * offset,
                      base + height * (0.66 + level * 0.069), (radius, radius * 1.15, radius * 1.04),
                      self.leaves[shade], subdivisions=2, smooth=True)

    def ruin(self, x, row):
        x, row = x + 0.5, row + 0.5
        height = self.relief(x, row)
        for level, span in enumerate((0.72, 0.53, 0.36)):
            block("Wayside shrine foundation", x, row, height + 0.04 + 0.07 * level, span, span * 0.73,
                  0.096, self.stones[level], 0.025)
        for side in (-1, 1):
            block("Wayside shrine pillar", x + side * 0.139, row, height + 0.33, 0.10, 0.12, 0.32, self.stones[2], 0.025)
        block("Carved crosspiece", x, row, height + 0.48, 0.42, 0.13, 0.091, self.stones[1], 0.022)
        stone("Green shrine seal", x, row, height + 0.53, (0.080, 0.067, 0.046), self.relic, 2, True)
        for index in range(12):
            angle = index * 2.39
            dx, dy = x + 0.39 * math.cos(angle), row + 0.34 * math.sin(angle)
            radius = RNG.uniform(0.04, 0.092)
            stone("Scattered shrine paving", dx, dy, self.relief(dx, dy) + radius * 0.11,
                  (radius, radius * 0.87, radius * 0.39), self.stones[index % 3])

    def decoration(self):
        for y, row in enumerate(self.rows):
            for x, tile in enumerate(row):
                if tile == "f":
                    self.grove(x, y)
        for cx, cy in self.hills:
            for index in range(9):
                angle = index * 2.39
                spread = RNG.uniform(0.16, 0.42)
                x, row = cx + math.cos(angle) * spread, cy + math.sin(angle) * spread
                radius = RNG.uniform(0.085, 0.19)
                stone("Exposed hill rock", x, row, self.relief(x, row) + radius * 0.32,
                      (radius, radius * 0.72, radius * 0.58), RNG.choice(self.stones), 2)
        for index in range(75):
            x = RNG.uniform(0, self.width)
            side = RNG.randrange(2)
            if min(abs(x - 3.5), abs(x - 8.5)) < 0.57:
                continue
            row = self.banks(x)[side] + RNG.uniform(0.02, 0.37) * (-1 if side == 0 else 1)
            radius = RNG.uniform(0.032, 0.12)
            stone("Bank stones", x, row, self.relief(x, row) + radius * 0.24,
                  (radius, radius * 0.71, radius * 0.6), RNG.choice(self.stones))
        blades, faces = [], []
        for i in range(1850):
            x, row = RNG.uniform(0, self.width), RNG.uniform(0, self.length)
            shore = self.shore_distance(x, row)
            if shore < 0.12 or self.road_distance(x, row) < 0.27:
                continue
            if shore > 0.54 and noise.noise_vector(Vector((x * 2.1, row * 2.1, 3)))[0] < 0.12:
                continue
            z = self.relief(x, row)
            for angle in (0.45, 2.62, 4.45):
                radius, height = RNG.uniform(0.012, 0.028), RNG.uniform(0.025, 0.064 if shore > 0.6 else 0.14)
                offset = math.cos(angle) * radius
                base = len(blades)
                blades.extend([point(x - offset, row - radius, z),
                               point(x + offset, row + radius, z),
                               point(x + math.cos(angle) * height * 0.48, row + math.sin(angle) * height * 0.41, z + height)])
                faces.append((base, base + 1, base + 2))
        form_mesh("Meadow grasses and bank reeds", blades, faces, self.leaves[3])


def configure_render(width, length, draft):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 18 if draft else 52
    scene.cycles.use_denoising = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 8
    scene.render.resolution_x = width * 180
    scene.render.resolution_y = length * 180
    scene.render.resolution_percentage = 52 if draft else 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.45

    world = bpy.data.worlds.new("Blue sky bounced light")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.53, 0.68, 0.91, 1)
    background.inputs["Strength"].default_value = 0.48
    scene.world = world
    light = bpy.data.lights.new("Afternoon key", type="SUN")
    light.energy = 2.35
    light.color = (1, 0.88, 0.73)
    light.angle = math.radians(12)
    sun = bpy.data.objects.new("Afternoon key", light)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = Vector((0.52, -0.48, -0.88)).to_track_quat("-Z", "Y").to_euler()

    lens = bpy.data.cameras.new("Orthographic board camera")
    lens.type = "ORTHO"
    lens.sensor_fit = "HORIZONTAL"
    lens.ortho_scale = width
    camera = bpy.data.objects.new("Orthographic board camera", lens)
    bpy.context.collection.objects.link(camera)
    focus = Vector(point(width / 2, length / 2, 0))
    camera.location = focus + Vector((0, -20 * math.sin(TILT), 20 * math.cos(TILT)))
    camera.rotation_euler = (focus - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    bpy.context.view_layer.update()
    for x, row in [(0, 0), (width, 0), (0, length), (width, length), (width / 2, length / 2)]:
        render_point = world_to_camera_view(scene, camera, Vector(point(x, row, 0)))
        assert abs(render_point.x - x / width) < 0.001 and abs(render_point.y - (1 - row / length)) < 0.001, render_point
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_perspective = "CAMERA"
    return scene


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--maps", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--blend", type=Path)
    parser.add_argument("--draft", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rows, ruins = read_map(args.maps)
    valley = Landscape(rows)
    valley.ground()
    valley.river()
    bridge_columns = [x for x, tile in enumerate(rows[4]) if tile == "b" and rows[5][x] == "b"]
    assert len(bridge_columns) == 2
    for x in bridge_columns:
        valley.bridge(x + 0.5, "West Bridge" if x == min(bridge_columns) else "East Bridge")
    for x, row in ruins:
        valley.ruin(x, row)
    valley.decoration()
    scene = configure_render(valley.width, valley.length, args.draft)
    scene.render.filepath = "//rivergate-relief.png"
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()), compress=True)
    scene.render.filepath = str(args.image.resolve())
    bpy.ops.render.render(write_still=True)
    print(f"RIVERGATE RELIEF: {valley.width}x{valley.length}; bridge columns {bridge_columns}; "
          f"{len(bpy.data.objects)} objects; five projection anchors verified")


if __name__ == "__main__":
    main()
