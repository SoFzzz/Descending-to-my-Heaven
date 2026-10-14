"""Convierte _source/mixamo/knight/sword.fbx a assets/minions/knight/knight_sword.glb.

Uso: blender -b --factory-startup -P _source/tools/export_knight_sword.py
El FBX viene a escala enorme (~1.4 unidades x100) y en diagonal. El script:
- halla el eje largo (par de vértices más alejado) y lo alinea con +Z de Blender (= +Y en Godot, punta hacia arriba),
- escala para que mida LENGTH m,
- pone el origen en la empuñadura (centro entre la guarda y el pomo).
"""
import bpy, os
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "_source", "mixamo", "knight", "sword.fbx")
OUT = os.path.join(ROOT, "assets", "minions", "knight", "knight_sword.glb")
LENGTH = 1.10

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = obj.data
pts = [v.co.copy() for v in me.vertices]

# Eje largo: extremo más lejano desde un punto cualquiera, y el más lejano desde ese
a = max(pts, key=lambda p: (p - pts[0]).length)
b = max(pts, key=lambda p: (p - a).length)
axis = (b - a).normalized()
L = (b - a).length

def width_near(end, frac=0.08):
    """Anchura perpendicular de los vértices en el 8 % del largo cercano al extremo."""
    sel = [p for p in pts if abs((p - end).dot(axis)) < L * frac]
    rad = [((p - end) - axis * (p - end).dot(axis)).length for p in sel]
    return max(rad) if rad else 0.0

# La punta es el extremo más fino
tip, base = (a, b) if width_near(a) < width_near(b) else (b, a)
axis = (tip - base).normalized()

# Guarda = sección más ancha en la mitad del lado del pomo
def t(p): return (p - base).dot(axis)
slices = {}
for p in pts:
    k = int(t(p) / L * 50)
    r = ((p - base) - axis * t(p)).length
    slices[k] = max(slices.get(k, 0), r)
guard_k = max((k for k in slices if k < 25), key=lambda k: slices[k])
guard_t = (guard_k + 0.5) / 50 * L
grip_t = guard_t * 0.5
grip = base + axis * grip_t
print("largo original=%.3f guarda a %.3f del pomo" % (L, guard_t))

rot = axis.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4()
s = LENGTH / L
me.transform(Matrix.Scale(s, 4) @ rot @ Matrix.Translation(-grip))
me.update()
pts = [v.co for v in me.vertices]
for i, n in enumerate("xyz"):
    print("SWORD %s %.4f .. %.4f" % (n, min(p[i] for p in pts), max(p[i] for p in pts)))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB")
print("exportado", OUT)
