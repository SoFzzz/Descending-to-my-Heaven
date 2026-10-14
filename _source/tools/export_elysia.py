"""Exporta Elysia (estática, sin esqueleto) a assets/characters/elysia/elysia.glb.

Uso: blender -b --factory-startup -P _source/tools/export_elysia.py
- Importa el glb fuente, reconecta texturas que falten (busca en textures/ por nombre).
- Fuerza materiales opacos: Alpha = 1, sin enlaces al Alpha, blend opaco (el vestido salía semitransparente).
- Escala el objeto raíz para que mida 1.60 m con los pies en z = 0.
"""
import bpy, os
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "_source", "models", "ancient-elf-lady-psx", "source", "ancient lady elf psx.glb")
TEX_DIR = os.path.join(ROOT, "_source", "models", "ancient-elf-lady-psx", "textures")
OUT = os.path.join(ROOT, "assets", "characters", "elysia", "elysia.glb")
HEIGHT = 1.60

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

# Texturas: reconectar imágenes vacías o perdidas
tex_files = {f.lower(): os.path.join(TEX_DIR, f) for f in os.listdir(TEX_DIR)}
for img in bpy.data.images:
    ok = img.packed_file is not None or img.has_data or (img.filepath and os.path.exists(bpy.path.abspath(img.filepath)))
    print("imagen:", img.name, "ok" if ok else "SIN DATOS")
    if not ok:
        key = os.path.basename(img.filepath or img.name).lower()
        for k, p in tex_files.items():
            if k == key or k.startswith(os.path.splitext(key)[0]):
                img.filepath = p
                img.reload()
                print("  reconectada ->", p)

for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            a = n.inputs["Alpha"]
            for l in list(a.links):
                mat.node_tree.links.remove(l)
            a.default_value = 1.0
        if n.type == "TEX_IMAGE":
            print("material", mat.name, "textura", n.image.name if n.image else None)
    for attr, val in (("blend_method", "OPAQUE"), ("surface_render_method", "DITHERED")):
        if hasattr(mat, attr):
            try:
                setattr(mat, attr, val)
            except Exception:
                pass

def bounds():
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in bpy.context.scene.objects if o.type == "MESH" for v in o.data.vertices]
    return Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))), \
           Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))

roots = [o for o in bpy.context.scene.objects if o.parent is None]
lo, hi = bounds()
s = HEIGHT / (hi.z - lo.z)
for r in roots:
    r.scale = r.scale * s
    r.location = r.location * s
lo, hi = bounds()
for r in roots:
    r.location.z -= lo.z
lo, hi = bounds()
print("ELYSIA alto=%.4f min_z=%.4f ancho=%.3f fondo=%.3f" % (hi.z - lo.z, lo.z, hi.x - lo.x, hi.y - lo.y))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB")
print("exportado", OUT)
