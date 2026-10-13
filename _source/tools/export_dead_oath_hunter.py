"""Exporta Dead Oath Hunter (jefe 2) a .glb con sus clips separados y nombrados.

Uso (desde la raíz del repo):
    blender -b "_source/models/dead_oath_hunter/DEAD OATH HUNTER.blend" -P _source/tools/export_dead_oath_hunter.py -- assets/bosses/dead_oath_hunter/dead_oath_hunter.glb

El .blend trae 18 acciones de Mixamo con nombres genéricos y una acción larga ("Todo") con
todas pegadas, que se descarta. Los nombres de CLIPS se asignaron mirando cada acción.
"""
import sys
from pathlib import Path

import bpy

CLIPS = {
    "Armature.006|mixamo.com|Layer0.001": "idle_guard-loop",
    "Armature.005|mixamo.com|Layer0.001": "idle-loop",
    "Armature.001|mixamo.com|Layer0.001": "walk-loop",
    "Armature.004|mixamo.com|Layer0.001": "walk_forward-loop",
    "Armature.003|mixamo.com|Layer0.001": "strafe-loop",
    "Armature|mixamo.com|Layer0.001": "step-loop",
    "Armature.001|mixamo.com|Layer0": "attack_overhead",
    "Armature.009|mixamo.com|Layer0": "attack_thrust",
    "Armature.010|mixamo.com|Layer0": "attack_slash",
    "Armature.008|mixamo.com|Layer0": "attack_combo",
    "Armature.011|mixamo.com|Layer0": "attack_combo_thrust",
    "Armature.012|mixamo.com|Layer0": "attack_charge",
    "Armature|mixamo.com|Layer0": "attack_leap",
    "Armature.007|mixamo.com|Layer0": "dodge",
    "Armature.005|mixamo.com|Layer0": "dash",
    "Armature.006|mixamo.com|Layer0": "hurt",
    "Armature.004|mixamo.com|Layer0": "taunt",
    "Armature.003|mixamo.com|Layer0": "death",
}
# clips que conservan el desplazamiento horizontal de la cadera (el resto queda "in place")
ROOT_MOTION_CLIPS = {"death"}


def strip_root_motion(action):
    """Fija X y Z locales de mixamorig:Hips a su primer valor (Y local = altura)."""
    fcurves = [fc for layer in action.layers for strip in layer.strips
               for bag in strip.channelbags for fc in bag.fcurves]
    for fc in fcurves:
        if fc.data_path == 'pose.bones["mixamorig:Hips"].location' and fc.array_index in (0, 2):
            v = fc.keyframe_points[0].co[1]
            for kp in fc.keyframe_points:
                kp.co[1] = v
                kp.handle_left[1] = kp.handle_right[1] = v


def main():
    out = Path(sys.argv[sys.argv.index("--") + 1:][0]).resolve()
    src_dir = Path(bpy.data.filepath).parent
    bpy.ops.file.find_missing_files(directory=str(src_dir / "Textures"))

    arm = bpy.data.objects["Armature.002"]
    for name in ("Cube.001", "Camera", "Light"):  # duplicado oculto y objetos de escena
        if name in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[name])
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()

    # La espada viene emparentada al hueso mixamorig:RightHand, que el glTF no exporta bien:
    # se convierte en malla con skin, 100 % pesada a la mano.
    sword = bpy.data.objects["Cube.002"]
    sword.hide_render = False
    sword.hide_set(False)
    world = sword.matrix_world.copy()
    sword.parent = arm
    sword.parent_type = "OBJECT"
    sword.matrix_world = world
    group = sword.vertex_groups.new(name="mixamorig:RightHand")
    group.add([v.index for v in sword.data.vertices], 1.0, "REPLACE")
    sword.modifiers.new("Armature", "ARMATURE").object = arm

    for t in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(t)
    for src_name, clip in CLIPS.items():
        action = bpy.data.actions[src_name]
        action.name = clip
        if clip not in ROOT_MOTION_CLIPS:
            strip_root_motion(action)
        track = arm.animation_data.nla_tracks.new()
        track.name = clip
        track.strips.new(clip, 1, action)
        print(f"  + {clip} ({int(action.frame_range[1])} frames)")

    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB",
                              export_animation_mode="NLA_TRACKS", export_yup=True)
    print(f"OK -> {out}")


main()
