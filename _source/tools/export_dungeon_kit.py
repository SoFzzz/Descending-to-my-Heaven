"""Normaliza piezas de PSX_Dungeon a la grilla de 4 m y las exporta a assets/environment/kit/*.glb.

Uso:  blender -b --python _source/tools/export_dungeon_kit.py

Las piezas originales miden 20 unidades por módulo (muro 20 × 5 × 20), así que el factor es 0.2.
Convención (en coordenadas de Godot, Y arriba, norte = -Z):
  - Cada pieza de GridMap tiene el origen en el centro del suelo de su celda de 4 × 4 × 4 m.
  - Los muros ocupan el borde NORTE de la celda (z de -2 a -1, 1 m de grosor); el GridMap los gira.
  - `wall_corner` = muro norte + muro oeste.
  - Pilares y arcos no van en la grilla: su origen está en el centro de su base.
"""
import os
import bpy
import mathutils

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "_source", "models", "PSX_Dungeon", "PSX_Dungeon")
OUT = os.path.join(ROOT, "assets", "environment", "kit")
S = 0.2  # 20 unidades → 4 m

# nombre de salida: (piezas fuente, escala xyz, tipo de colocación, textura)
#   "edge"  → borde norte de la celda   "floor" → plano en el suelo   "ceil" → plano mirando abajo
#   "base"  → centrado en XY, base en Z=0
PIECES = {
    "floor":           (["Floor_Tiles"], (S, S, S), "floor", None),
    "ceiling":         (["Floor_Tiles"], (S, S, S), "ceil", None),
    "wall":            (["Wall_01"], (S, S, S), "edge", None),
    "wall_skull":      (["Skull_Wall"], (S, S, S), "edge", None),
    "wall_window":     (["Windowed_Wall_01"], (S, S, S), "edge", None),
    "wall_ruin":       (["Wall_Ruin"], (S, S, S), "edge", None),
    "wall_corner":     (["Wall_01", "Wall_01"], (S, S, S), "corner", None),
    "pillar":          (["Pillar"], (1.2 / 5.65, 1.2 / 5.65, 8.0 / 30.2), "base", None),
    "pillar_collapsed": (["Pillar_Collapsed_01"], (1.2 / 5.65, 1.2 / 5.65, 1.2 / 5.65), "base", None),
    "arch":            (["Arch"], (S, S, S), "base", None),
    "stairs_wide":     (["Stairs_Wide"], (S, S, S), "base", None),
}


def import_piece(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(SRC, "Models", name + ".fbx"))
    objs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for o in [o for o in bpy.data.objects if o not in before and o != ob]:
        bpy.data.objects.remove(o)
    ob.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    mn = mathutils.Vector([min(v[i] for v in vs) for i in range(3)])
    mx = mathutils.Vector([max(v[i] for v in vs) for i in range(3)])
    return mn, mx


def place(ob, scale, mode):
    ob.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    mn, mx = bounds(ob)
    c = (mn + mx) / 2
    # Godot -Z (norte) = Blender +Y. Borde norte: y de 1 a 2.
    if mode == "edge":
        ob.location = (-c.x, 2.0 - mx.y, -mn.z)
    elif mode == "floor":
        ob.location = (-c.x, -c.y, -mn.z)
    elif mode == "ceil":
        ob.rotation_euler = (3.14159265, 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
        mn, mx = bounds(ob)
        c = (mn + mx) / 2
        ob.location = (-c.x, -c.y, -mn.z)
    else:
        ob.location = (-c.x, -c.y, -mn.z)
    bpy.ops.object.transform_apply(location=True)


def set_texture(ob, tex):
    # Las piezas usan el atlas Dungeon_Map (el FBX no trae la imagen enlazada).
    tex = tex or "Dungeon_Map"
    img = bpy.data.images.load(os.path.join(SRC, "Textures", tex + ".png"), check_existing=True)
    for slot in ob.material_slots:
        mat = slot.material.copy()
        slot.material = mat
        nodes = mat.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        tn = nodes.new("ShaderNodeTexImage")
        tn.image = img
        tn.interpolation = "Closest"
        mat.node_tree.links.new(tn.outputs[0], bsdf.inputs[0])


def main():
    os.makedirs(OUT, exist_ok=True)
    for out, (srcs, scale, mode, tex) in PIECES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if mode == "corner":
            a = import_piece(srcs[0]); place(a, scale, "edge")
            b = import_piece(srcs[1]); place(b, scale, "edge")
            b.rotation_euler = (0, 0, 3.14159265 / 2)   # norte → oeste
            bpy.ops.object.select_all(action="DESELECT")
            b.select_set(True); bpy.context.view_layer.objects.active = b
            bpy.ops.object.transform_apply(rotation=True)
            a.select_set(True); bpy.context.view_layer.objects.active = a
            bpy.ops.object.join()
            ob = a
        else:
            ob = import_piece(srcs[0])
            place(ob, scale, mode)
        ob.name = out
        set_texture(ob, tex)
        mn, mx = bounds(ob)
        imgs = {n.image.name for s in ob.material_slots for n in s.material.node_tree.nodes
                if n.type == "TEX_IMAGE" and n.image}
        print("KIT %-17s size %s min %s imgs %s" % (out, tuple(round(v, 2) for v in mx - mn),
              tuple(round(v, 2) for v in mn), imgs))
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, out + ".glb"), export_format="GLB",
                                  use_selection=False, export_apply=True)


main()
