"""Junta un personaje de Mixamo y sus animaciones en un solo .glb para Godot.

Uso (desde la raíz del repo):
    blender -b --factory-startup -P _source/tools/combine_mixamo.py -- <carpeta_mixamo> <salida.glb>

<carpeta_mixamo> debe contener:
    base.fbx          descargado de Mixamo (con skin, en T-pose)
    anims/<clip>.fbx  una animación por archivo (con o sin skin);
                      el nombre del archivo es el nombre final del clip (idle.fbx -> "idle")

También se puede importar y llamar a combine() con una tabla {clip: archivo}; ver
build_characters.py. Los clips de LOOP_CLIPS terminan en "-loop" (Godot los importa en
bucle) y todos quedan "in place" salvo los de ROOT_MOTION_CLIPS.
"""
import sys
from pathlib import Path

import bpy

LOOP_CLIPS = {"idle", "walk", "run", "walk_back", "strafe_left", "strafe_right"}
ROOT_MOTION_CLIPS = {"death"}


def import_fbx(path: Path) -> list:
    before = set(bpy.data.objects)
    try:
        bpy.ops.import_scene.fbx(filepath=str(path), automatic_bone_orientation=False)
    except AttributeError:
        bpy.ops.wm.fbx_import(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


def armature_in(objs: list):
    arms = [o for o in objs if o.type == "ARMATURE"]
    if not arms:
        raise SystemExit(f"Sin esqueleto en {[o.name for o in objs]}")
    return arms[0]


def action_fcurves(action):
    if hasattr(action, "layers"):
        return [fc for layer in action.layers for strip in layer.strips
                for bag in strip.channelbags for fc in bag.fcurves]
    return list(action.fcurves)


def strip_root_motion(action):
    """Fija X y Z locales de la cadera a su primer valor (Y local = altura).

    También borra las claves de transformación del objeto (algunos FBX fijan su escala en
    cada clip, y eso pisaría normalize_height al exportar).
    """
    for fc in action_fcurves(action):
        if fc.data_path in ("location", "rotation_euler", "rotation_quaternion", "scale"):
            fc.keyframe_points.clear()
    for fc in action_fcurves(action):
        if fc.data_path.endswith(':Hips"].location') and fc.array_index in (0, 2):
            v = fc.keyframe_points[0].co[1]
            for kp in fc.keyframe_points:
                kp.co[1] = v
                kp.handle_left[1] = kp.handle_right[1] = v


def normalize_height(arm, height):
    """Escala el objeto raíz para que el personaje mida `height` m en el frame 1 de su idle."""
    tracks = list(arm.animation_data.nla_tracks)
    for t in tracks:
        t.mute = True
    idle = next((t.strips[0].action for t in tracks if t.name.startswith("idle")), tracks[0].strips[0].action)
    arm.animation_data.action = idle
    bpy.context.scene.frame_set(1)

    def measure():
        dg = bpy.context.evaluated_depsgraph_get()
        zs = []
        for o in bpy.context.scene.objects:
            if o.type == "MESH":
                e = o.evaluated_get(dg)
                me = e.to_mesh()
                zs += [(o.matrix_world @ v.co).z for v in me.vertices]
                e.to_mesh_clear()
        return max(zs) - min(zs)

    root = arm
    while root.parent:
        root = root.parent
    before = measure()
    root.scale *= height / before
    bpy.context.view_layer.update()
    arm.animation_data.action = None
    for t in tracks:
        t.mute = False
    print(f"  altura {before:.2f} -> {height:.2f} m (escala x{height / before:.4f})")


def combine(base_fbx: Path, clips: dict, out: Path, height: float = None) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    base = armature_in(import_fbx(base_fbx))
    base.animation_data_create()
    base.animation_data.action = None

    for clip, fbx in clips.items():
        new_objs = import_fbx(fbx)
        arm = armature_in(new_objs)
        action = arm.animation_data.action
        if clip not in ROOT_MOTION_CLIPS:
            strip_root_motion(action)
        else:
            for fc in action_fcurves(action):
                if fc.data_path in ("location", "rotation_euler", "rotation_quaternion", "scale"):
                    fc.keyframe_points.clear()
        name = clip + ("-loop" if clip in LOOP_CLIPS else "")
        action.name = name
        action.use_fake_user = True
        track = base.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, int(action.frame_range[0]), action)
        bpy.data.batch_remove(new_objs)
        print(f"  + {name} ({int(action.frame_range[1] - action.frame_range[0])} frames) <- {fbx.name}")

    if height:
        normalize_height(base, height)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_animation_mode="NLA_TRACKS",
        export_yup=True,
    )
    print(f"OK -> {out} con {len(clips)} animaciones")


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:]
    src, out = Path(args[0]), Path(args[1])
    files = sorted((src / "anims").glob("*.fbx"))
    if not files:
        raise SystemExit(f"No hay animaciones en {src / 'anims'}")
    combine(src / "base.fbx", {f.stem: f for f in files}, out)


if __name__ == "__main__":
    main()
