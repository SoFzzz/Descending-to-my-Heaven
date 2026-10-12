"""Junta un personaje de Mixamo y sus animaciones en un solo .glb para Godot.

Uso (desde la raíz del repo):
    blender -b --factory-startup -P _source/tools/combine_mixamo.py -- <carpeta_mixamo> <salida.glb>

<carpeta_mixamo> debe contener:
    base.fbx          descargado de Mixamo "With Skin" (en T-pose)
    anims/<clip>.fbx  una animación por archivo, descargada "Without Skin";
                      el nombre del archivo es el nombre final del clip (idle.fbx -> "idle")

Los clips cuyo nombre está en LOOP_CLIPS terminan en "-loop", así Godot los importa en bucle.
"""
import sys
from pathlib import Path

import bpy

LOOP_CLIPS = {"idle", "walk", "run"}


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


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:]
    src, out = Path(args[0]), Path(args[1])
    bpy.ops.wm.read_factory_settings(use_empty=True)

    base = armature_in(import_fbx(src / "base.fbx"))
    base.animation_data_create()
    base.animation_data.action = None

    clips = sorted((src / "anims").glob("*.fbx"))
    if not clips:
        raise SystemExit(f"No hay animaciones en {src / 'anims'}")
    for fbx in clips:
        new_objs = import_fbx(fbx)
        arm = armature_in(new_objs)
        action = arm.animation_data.action
        name = fbx.stem + ("-loop" if fbx.stem in LOOP_CLIPS else "")
        action.name = name
        action.use_fake_user = True
        track = base.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, int(action.frame_range[0]), action)
        bpy.data.batch_remove(new_objs)
        print(f"  + {name} ({int(action.frame_range[1] - action.frame_range[0])} frames)")

    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_animation_mode="NLA_TRACKS",
        export_yup=True,
    )
    print(f"OK -> {out} con {len(clips)} animaciones")


main()
