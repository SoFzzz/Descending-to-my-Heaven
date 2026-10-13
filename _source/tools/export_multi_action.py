"""Exporta personajes que traen varias animaciones dentro de un solo FBX (Plague Arcanist, TheWrapper).

Uso (desde la raíz del repo), uno por ejecución:
    blender -b --factory-startup -P _source/tools/export_multi_action.py -- plague_arcanist
    (plague_arcanist | thewrapper)

Cada tabla dice: clip final -> (acción del FBX, frame final o None). Con un frame final se
recorta la acción (sirve para sacar "hurt" y "death" de una animación más larga). Los nombres
se asignaron mirando capturas de cada acción. Todo queda "in place" salvo los de ROOT_MOTION y
el modelo se escala a la altura de §7.4 del documento de diseño.
"""
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).parent))
from combine_mixamo import action_fcurves, normalize_height, strip_root_motion  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
ROOT_MOTION = {"death"}

PA = "Armature|Armature|Armature{}|mixamo.com|Layer0"
CHARACTERS = {
    "plague_arcanist": {
        "fbx": "_source/models/Plague Arcanist/Plague Arcanist/Plague Arcanist.fbx",
        "textures": "_source/models/Plague Arcanist/Plague Arcanist/Texture",
        "out": "assets/minions/plague_arcanist/plague_arcanist.glb",
        "height": 1.80,
        "clips": {
            "idle-loop": (PA.format(".009"), None),
            "idle_alt-loop": (PA.format(".008"), None),
            "walk-loop": (PA.format(".002"), None),
            "strafe-loop": (PA.format(".003"), None),
            "attack": (PA.format(".006"), None),
            "attack_cast": (PA.format(".005"), None),
            "attack_leap": (PA.format(".001"), None),
            "taunt": (PA.format(".007"), None),
            "knockdown": (PA.format(".004"), None),
            "hurt": (PA.format(".004"), 15),   # retroceso inicial de knockdown
            "death": (PA.format(".004"), 42),  # knockdown hasta quedar en el suelo
        },
    },
    "thewrapper": {
        "fbx": "_source/models/TheWrapper V2/MonsterPSX.fbx",
        "textures": "_source/models/TheWrapper V2",
        "out": "assets/minions/thewrapper/thewrapper.glb",
        "height": 2.00,
        "clips": {
            "idle-loop": ("MonsterPSX_Rig|MonsterPSX_Rig|Idle_Watchful", None),
            "walk-loop": ("MonsterPSX_Rig|MonsterPSX_Rig|Walk_Nervous", None),
            "run-loop": ("MonsterPSX_Rig|MonsterPSX_Rig|Run_Frantic", None),
            "attack": ("MonsterPSX_Rig|MonsterPSX_Rig|Attack_Lunge", None),
            "hurt": ("MonsterPSX_Rig|MonsterPSX_Rig|WallSlam_Recover", None),
            "scream": ("MonsterPSX_Rig|MonsterPSX_Rig|Scream.lol", None),
        },
    },
}


def trimmed_copy(action, end):
    new = action.copy()
    for fc in action_fcurves(new):
        for kp in [k for k in fc.keyframe_points if k.co[0] > end][::-1]:
            fc.keyframe_points.remove(kp)
    return new


def main():
    cfg = CHARACTERS[sys.argv[sys.argv.index("--") + 1]]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.fbx(filepath=str(REPO / cfg["fbx"]), automatic_bone_orientation=False)
    bpy.ops.file.find_missing_files(directory=str(REPO / cfg["textures"]))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    arm.animation_data.action = None
    # TheWrapper trae las formas de control del rig (WGT_*) como mallas sueltas: no son parte del modelo
    bpy.data.batch_remove([o for o in bpy.data.objects if o.name.startswith("WGT_")])

    for clip, (src, end) in cfg["clips"].items():
        action = bpy.data.actions[src]
        if end is not None:
            action = trimmed_copy(action, end)
        else:
            action = action.copy()
        strip_root_motion(action) if clip not in ROOT_MOTION else None
        if clip in ROOT_MOTION:  # igual se quitan las claves de escala/posición del objeto
            for fc in action_fcurves(action):
                if fc.data_path in ("location", "rotation_euler", "rotation_quaternion", "scale"):
                    fc.keyframe_points.clear()
        action.name = clip
        action.use_fake_user = True
        track = arm.animation_data.nla_tracks.new()
        track.name = clip
        track.strips.new(clip, 1, action)
        print(f"  + {clip} ({int(action.frame_range[1])} frames) <- {src}")

    normalize_height(arm, cfg["height"])
    out = REPO / cfg["out"]
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB",
                              export_animation_mode="NLA_TRACKS", export_yup=True)
    print(f"OK -> {out}")


main()
