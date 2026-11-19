"""Open each shipped skirmish model in Blender and verify its 2D board projection."""

import math
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tools"))
from render_rivergate import read_map


def check_board(map_id):
    name = f"{map_id}-relief-v1.blend"
    bpy.ops.wm.open_mainfile(filepath=str(PROJECT / "assets/art/model_sources" / name))
    scene = bpy.context.scene
    rows, ruins = read_map(PROJECT / "data/maps.tres", map_id)
    width, height = len(rows[0]), len(rows)
    if map_id != "rivergate":
        assert scene["map_id"] == map_id and scene["grid_rows"].splitlines() == rows
        assert scene["ruin_cells"] == " ".join(f"{x},{y}" for x, y in ruins)
    assert scene.camera.data.type == "ORTHO" and scene.render.engine == "CYCLES"
    assert scene.render.filepath == f"//{map_id}-relief.png"
    assert (scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage) == (
        width * 180,
        height * 180,
        100,
    )
    for y in range(height):
        for x in range(width):
            ground = Vector((x + 0.5, -(y + 0.5) / math.cos(math.radians(16)), 0))
            projected = world_to_camera_view(scene, scene.camera, ground)
            assert abs(projected.x * width - x - 0.5) < 0.0001
            assert abs((1 - projected.y) * height - y - 0.5) < 0.0001
    assert not list(bpy.data.libraries)
    textures = set()
    for image in bpy.data.images:
        if not image.filepath:
            continue
        assert image.packed_file and image.filepath.startswith("//")
        assert all(item.filepath == image.filepath for item in image.packed_files)
        textures.add(image.filepath[2:])
    expected = {"highlands-surfaces-v1.png"} if map_id in ("ridgepass", "sunspire", "citadel") else set()
    if map_id == "citadel":
        expected.add("citadel-windrose-v1.png")
    assert textures == expected, textures
    print(
        f"VERIFIED {map_id}: {width * height} projected centres, {len(scene.objects)} objects, {len(textures)} packed textures"
    )


for board in ("greenwood", "rivergate", "sunspire", "ridgepass", "citadel", "harbor"):
    check_board(board)
