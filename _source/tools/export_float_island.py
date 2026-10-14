"""Exporta piezas de float-islands/FloatingIsland.fbx a assets/environment/island/*.glb.

Uso:  blender -b --python _source/tools/export_float_island.py

El FBX es un kit con muchas islas sueltas (ya en metros). Se exporta cada pieza elegida por
separado, centrada en XY y con su punto más alto en Z=0 (Y=0 en Godot), sin cambiar la escala.
"""
import os
import bpy
import mathutils

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "_source", "models", "float-islands", "FloatingIsland.fbx")
OUT = os.path.join(ROOT, "assets", "environment", "island")
# pieza del FBX → nombre de salida
PIECES = {
    "IslandSkull": "island_main",      # ≈ 104 × 104 m, isla principal (calavera: fantasía oscura)
    "Round": "islet_round",
    "Long": "islet_long",
    "L": "islet_l",
    "Small": "islet_small",
    "IslandHoleSmall": "islet_hole",
}


def bounds(o):
    pts = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
    return (mathutils.Vector([min(p[i] for p in pts) for i in range(3)]),
            mathutils.Vector([max(p[i] for p in pts) for i in range(3)]))


os.makedirs(OUT, exist_ok=True)
for src, out in PIECES.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=SRC)
    ob = bpy.data.objects[src]
    for o in list(bpy.data.objects):
        if o != ob:
            bpy.data.objects.remove(o)
    ob.parent = None
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mn, mx = bounds(ob)
    c = (mn + mx) / 2
    ob.location = (-c.x, -c.y, -mx.z)
    bpy.ops.object.transform_apply(location=True)
    mn, mx = bounds(ob)
    print("ISLAND %-12s size %s" % (out, tuple(round(v, 1) for v in mx - mn)))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, out + ".glb"), export_format="GLB")
