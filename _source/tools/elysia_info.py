"""Prints the layout of Elysia's mesh (bounds and, per height slice, the x extent and the arm gaps) so the
rig in rig_elysia.py can place its joints. Run:
  blender -b --factory-startup -P _source/tools/elysia_info.py -- assets/characters/elysia/elysia.glb
"""
import sys
import bpy

src = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for obj in bpy.context.scene.objects:
    print("OBJ", obj.name, obj.type, tuple(round(v, 3) for v in obj.location), tuple(round(v, 3) for v in obj.rotation_euler), tuple(round(v, 3) for v in obj.scale))
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for ob in meshes:
    mw = ob.matrix_world
    pts = [mw @ v.co for v in ob.data.vertices]
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    zs = [p.z for p in pts]
    print("MESH", ob.name, "verts", len(pts), "x", round(min(xs), 3), round(max(xs), 3), "y", round(min(ys), 3), round(max(ys), 3), "z", round(min(zs), 3), round(max(zs), 3))
    cy = (min(ys) + max(ys)) / 2.0
    z0, z1 = min(zs), max(zs)
    n = 32
    for i in range(n):
        lo = z0 + (z1 - z0) * i / n
        hi = z0 + (z1 - z0) * (i + 1) / n
        sl = [p for p in pts if lo <= p.z < hi]
        if not sl:
            continue
        # x positions sorted, with gaps larger than 4 cm marking separate parts (body vs arms)
        xs_sorted = sorted(p.x for p in sl)
        parts = []
        start = xs_sorted[0]
        prev = start
        for x in xs_sorted[1:]:
            if x - prev > 0.04:
                parts.append((round(start, 2), round(prev, 2)))
                start = x
            prev = x
        parts.append((round(start, 2), round(prev, 2)))
        print("Z %.2f-%.2f" % (lo, hi), "y-center %.2f" % (sum(p.y for p in sl) / len(sl)), parts)
