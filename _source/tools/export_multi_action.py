"""Exporta personajes que traen varias animaciones dentro de un solo FBX (Plague Arcanist, TheWrapper,
Straw Reaper).

Uso (desde la raíz del repo), uno por ejecución:
    blender -b --factory-startup -P _source/tools/export_multi_action.py -- plague_arcanist
    (plague_arcanist | thewrapper | straw_reaper | blackhorn)

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
BH = "Armature.003|Armature.003|{}"
SR = "Armature.001|Armature.001|{}"
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
    # Élite de la arena 3 (reemplaza al Wrapper élite, 2026-10-15). Clips Mixamo sin nombre en
    # el FBX: se identificaron con capturas (las acciones .006 y .007 de "Armature" son iguales).
    "straw_reaper": {
        "fbx": "_source/models/straw_reaper/THE STRAW REAPER new.fbx",
        "textures": "_source/models/straw_reaper/texture",
        "out": "assets/minions/straw_reaper/straw_reaper.glb",
        "height": 1.90,  # algo más alto que Kaelen (1.70); la hoz sobresale por encima
        "center_xy": True,  # la armadura del FBX está ~1 m fuera del origen
        "clips": {
            "idle-loop": (SR.format("Armature.004|mixamo.com|Layer0"), None),
            "walk-loop": (SR.format("Armature.005|mixamo.com|Layer0"), None),    # carrera corta (17 frames)
            "lurch-loop": (SR.format("Armature.006|mixamo.com|Layer0"), None),   # zancada encorvada
            "attack": (SR.format("Armature|mixamo.com|Layer0"), None),           # tajo por encima de la cabeza
            "attack_2": (SR.format("Armature|mixamo.com|Layer0.002"), None),     # giro con la hoz
            "combo": (SR.format("Armature.002|mixamo.com|Layer0"), None),        # tajos agachado
            "hurt": (SR.format("Armature.001|mixamo.com|Layer0"), 20),           # inicio de la caída
            "death": (SR.format("Armature.001|mixamo.com|Layer0"), None),        # cae y queda tendido
        },
    },
    # Jefe 2 (reemplaza a Dead Oath Hunter, 2026-10-14). Bestia con cuernos, rig Mixamo.
    "blackhorn": {
        "fbx": "_source/models/blackhorn/Blackhorn of the Shattered Peaks.fbx",
        "textures": "_source/models/blackhorn/Textures",
        "out": "assets/bosses/blackhorn/blackhorn.glb",
        "height": 3.20,  # casi el doble que Kaelen (1.70): intimidante sin salirse de la arena 2
        "clips": {
            "idle-loop": (BH.format("Armature.007|mixamo.com|Layer0"), None),
            "taunt": (BH.format("Armature.005|mixamo.com|Layer0"), None),
            "roar": (BH.format("Armature.001|mixamo.com|Layer0"), None),
            "walk-loop": (BH.format("Armature.004|mixamo.com|Layer0.001"), None),
            "run-loop": (BH.format("Armature.003|mixamo.com|Layer0"), None),
            "charge-loop": (BH.format("Armature.004|mixamo.com|Layer0"), None),
            "attack_pounce": (BH.format("Armature.002|mixamo.com|Layer0"), None),
            "attack_slam": (BH.format("Armature.006|mixamo.com|Layer0"), None),
        },
        # el pack no trae golpe recibido ni muerte: descargadas de Mixamo sin skin
        # (mismos nombres de hueso que el rig de Blackhorn)
        "extra_clips": {
            "hurt": "_source/mixamo/blackhorn/anims/hurt.fbx",
            "death": "_source/mixamo/blackhorn/anims/death.fbx",
        },
    },
}


def center_on_hips(arm):
    """Mueve el objeto raíz en X/Y para que la cadera quede sobre el origen en el frame 1 del idle
    (algunos FBX traen la armadura desplazada y el modelo saldría lejos de su collider en Godot)."""
    tracks = list(arm.animation_data.nla_tracks)
    for t in tracks:
        t.mute = True
    arm.animation_data.action = next(t.strips[0].action for t in tracks if t.name == "idle-loop")
    bpy.context.scene.frame_set(1)
    root = arm
    while root.parent:
        root = root.parent
    hips = arm.matrix_world @ arm.pose.bones["mixamorig:Hips"].head
    root.location.x -= hips.x
    root.location.y -= hips.y
    bpy.context.view_layer.update()
    arm.animation_data.action = None
    for t in tracks:
        t.mute = False
    print(f"  centrado: cadera desplazada ({-hips.x:.3f}, {-hips.y:.3f}) m")


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

    for clip, path in cfg.get("extra_clips", {}).items():
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=str(REPO / path), automatic_bone_orientation=False)
        new_objs = [o for o in bpy.data.objects if o not in before]
        src = next(o for o in new_objs if o.type == "ARMATURE")
        action = src.animation_data.action
        for fc in action_fcurves(action):
            if fc.data_path in ("location", "rotation_euler", "rotation_quaternion", "scale"):
                fc.keyframe_points.clear()
        # la cadera de otro esqueleto guarda posiciones de SU reposo y en SUS unidades: se pasan
        # a desplazamientos relativos al primer frame, escalados por la altura de cadera
        hips = "mixamorig:Hips"
        ratio = arm.data.bones[hips].head_local.length / src.data.bones[hips].head_local.length
        # punto de partida: la cadera del idle de este personaje en su frame 1
        idle = bpy.data.actions[cfg["clips"]["idle-loop"][0]]
        ref = {fc.array_index: fc.evaluate(1) for fc in action_fcurves(idle)
               if fc.data_path.endswith(':Hips"].location')}
        for fc in action_fcurves(action):
            if fc.data_path.endswith(':Hips"].location') and fc.keyframe_points:
                v0 = fc.keyframe_points[0].co[1]
                base = ref.get(fc.array_index, 0.0)
                for kp in fc.keyframe_points:
                    for attr in ("co", "handle_left", "handle_right"):
                        pt = getattr(kp, attr)
                        pt[1] = base + (pt[1] - v0) * ratio
        if clip not in ROOT_MOTION:
            strip_root_motion(action)
        action.name = clip
        action.use_fake_user = True
        track = arm.animation_data.nla_tracks.new()
        track.name = clip
        track.strips.new(clip, 1, action)
        bpy.data.batch_remove(new_objs)
        print(f"  + {clip} ({int(action.frame_range[1])} frames) <- {Path(path).name}")

    normalize_height(arm, cfg["height"])
    if cfg.get("center_xy"):
        center_on_hips(arm)
    out = REPO / cfg["out"]
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB",
                              export_animation_mode="NLA_TRACKS", export_yup=True)
    print(f"OK -> {out}")


main()
