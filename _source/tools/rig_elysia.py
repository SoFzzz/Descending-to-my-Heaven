"""Rigs Elysia (a static, un-rigged, A-posed mesh) and gives her three short animations, for the ending:
  idle    loop, 3 s: arms relaxed (lowered from the model's A-pose), breathing, a tiny head sway
  appear  2.4 s, plays once when she shows up: head and shoulders raise, arms settle (then idle)
  hug     1.8 s, plays at the embrace: both arms rise forward and close around Kaelen's back
No Mixamo and no auto-weights: the mesh is low-poly (676 vertices), so the skeleton is placed from
the measurements printed by elysia_info.py and the vertex weights are computed from geometry
(head / chest / hips by height, arms by distance to the arm segments).

Run (Blender 4.x / 5.x, background):
  blender -b --factory-startup -P _source/tools/rig_elysia.py -- <source.glb> <output.glb>
The mesh keeps its position and size (its origin is NOT at her body: the mesh center is ~1 m from it, which
the game accounts for), so nothing already placed in the levels moves.
"""
import math
import sys

import bpy
from mathutils import Matrix, Vector

SRC, DST = sys.argv[sys.argv.index("--") + 1:][:2]
FPS = 24
Y = 0.91   # depth (Blender Y) of her body's middle, from elysia_info.py

# bone: (head, tail, parent) in Blender axes (X sideways, Y depth, Z up); "L" is the +X side.
BONES = {
    "Hips": ((0.0, Y, 0.80), (0.0, Y, 0.95), None),
    "Spine": ((0.0, Y, 0.95), (0.0, Y, 1.20), "Hips"),
    "Chest": ((0.0, Y, 1.20), (0.0, Y, 1.36), "Spine"),
    "Neck": ((0.0, Y, 1.36), (0.0, Y, 1.42), "Chest"),
    "Head": ((0.0, Y, 1.42), (0.0, Y, 1.62), "Neck"),
    "UpperArm.L": ((0.17, Y, 1.30), (0.29, Y, 1.04), "Chest"),
    "Forearm.L": ((0.29, Y, 1.04), (0.38, Y, 0.84), "UpperArm.L"),
    "Hand.L": ((0.38, Y, 0.84), (0.41, Y, 0.74), "Forearm.L"),
    "UpperArm.R": ((-0.17, Y, 1.30), (-0.29, Y, 1.04), "Chest"),
    "Forearm.R": ((-0.29, Y, 1.04), (-0.38, Y, 0.84), "UpperArm.R"),
    "Hand.R": ((-0.38, Y, 0.84), (-0.41, Y, 0.74), "Forearm.R"),
}
ARM_RADIUS = 0.13   # sleeves (bell sleeves at the wrist) within this distance of the arm line belong to the arm


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def seg_param(p, a, b):
    """(distance to segment a-b, parameter 0..1 along it) for 3D points."""
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length, t


# --- scene -------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
assert len(meshes) == 1, "expected one mesh, found %d" % len(meshes)
mesh = meshes[0]
for o in list(bpy.context.scene.objects):   # drop any empties the importer made, keep the mesh at its place
    if o is not mesh and o.type == "EMPTY":
        o.select_set(False)
world = mesh.matrix_world.copy()
mesh.parent = None
mesh.matrix_world = world

# --- armature ----------------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("ElysiaRig")
arm_obj = bpy.data.objects.new("Armature", arm_data)
bpy.context.scene.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode="EDIT")
for name, (head, tail, parent) in BONES.items():
    eb = arm_data.edit_bones.new(name)
    eb.head = Vector(head)
    eb.tail = Vector(tail)
    eb.roll = 0.0
    if parent:
        eb.parent = arm_data.edit_bones[parent]
        eb.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

# --- weights from geometry ---------------------------------------------------------------------
for name in BONES:
    mesh.vertex_groups.new(name=name)
segments = {}
for side in ("L", "R"):
    segments[side] = [
        ("UpperArm." + side, Vector(BONES["UpperArm." + side][0]), Vector(BONES["UpperArm." + side][1])),
        ("Forearm." + side, Vector(BONES["Forearm." + side][0]), Vector(BONES["Forearm." + side][1])),
        ("Hand." + side, Vector(BONES["Hand." + side][0]), Vector(BONES["Hand." + side][1])),
    ]
arm_vertices = 0
for v in mesh.data.vertices:
    p = mesh.matrix_world @ v.co
    w = {}
    head_w = smooth(1.32, 1.44, p.z)
    # Arm candidates: nearest arm segment on this vertex's side, outside the torso column.
    side = "L" if p.x >= 0 else "R"
    best = None
    for bname, a, b in segments[side]:
        d, t = seg_param(p, a, b)
        if best is None or d < best[0]:
            best = (d, bname, t)
    is_arm = best[0] < ARM_RADIUS and abs(p.x) > 0.15 and p.z < 1.36
    if is_arm:
        arm_vertices += 1
        # Fade from the chest into the upper arm over the first part of the arm.
        along = (p - segments[side][0][1]).length
        to_arm = smooth(0.02, 0.16, along)
        w[best[1]] = to_arm
        w["Chest"] = 1.0 - to_arm
    else:
        chest_w = smooth(0.95, 1.2, p.z) * (1.0 - head_w)
        w["Head" if head_w > 0.5 else "Hips"] = 0.0
        w["Head"] = head_w
        w["Chest"] = chest_w
        w["Hips"] = 1.0 - head_w - chest_w
    for bname, value in w.items():
        if value > 0.001:
            mesh.vertex_groups[bname].add([v.index], value, "REPLACE")
print("arm vertices:", arm_vertices, "of", len(mesh.data.vertices))

mesh.parent = arm_obj
mesh.matrix_parent_inverse = arm_obj.matrix_world.inverted()
mod = mesh.modifiers.new("Armature", "ARMATURE")
mod.object = arm_obj

# --- animations --------------------------------------------------------------------------------
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode="POSE")
arm_obj.animation_data_create()
rest = {b.name: b.matrix_local.to_3x3() for b in arm_data.bones}
for pb in arm_obj.pose.bones:
    pb.rotation_mode = "QUATERNION"


def pose(bone, axis, degrees):
    """Rotation of `bone` by `degrees` around an armature-space axis ('X' sideways, 'Y' depth, 'Z' up),
    as a local pose quaternion."""
    r = Matrix.Rotation(math.radians(degrees), 3, axis)
    m = rest[bone]
    return (m.inverted() @ r @ m).to_quaternion()


def compose(*qs):
    out = qs[0]
    for q in qs[1:]:
        out = out @ q
    return out


def key(frame, poses):
    """poses: {bone: quaternion}; every bone not listed goes back to rest."""
    for pb in arm_obj.pose.bones:
        pb.rotation_quaternion = poses.get(pb.name, (1.0, 0.0, 0.0, 0.0))
        pb.keyframe_insert("rotation_quaternion", frame=frame)


def new_action(name, frames, loop):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm_obj.animation_data.action = act
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = frames
    return act


# The A-pose arms hang ~24 deg off vertical: relax them by LOWER degrees (more for the forearm).
LOWER = 15.0
REACH_OUT = 10.0   # extra Y degrees (on top of the lowering) that spread the reaching arms


def relaxed(extra=None, up=0.0):
    """Base pose: arms lowered toward the body; `extra` adds/overrides bones; `up` leans the chest back."""
    p = {
        "UpperArm.L": pose("UpperArm.L", "Y", LOWER),
        "UpperArm.R": pose("UpperArm.R", "Y", -LOWER),
        "Forearm.L": pose("Forearm.L", "Y", 4.0),
        "Forearm.R": pose("Forearm.R", "Y", -4.0),
    }
    if extra:
        p.update(extra)
    return p


# idle: breathing every 3 s (chest and head), arms moving a hair opposite to the breath.
n = 72
new_action("idle", n + 1, True)
key(1, relaxed({"Chest": pose("Chest", "X", 0.0), "Head": pose("Head", "Z", 1.5)}))
key(1 + n // 2, relaxed({
    "Chest": pose("Chest", "X", -2.2),
    "Head": compose(pose("Head", "Z", -1.5), pose("Head", "X", 1.0)),
    "UpperArm.L": pose("UpperArm.L", "Y", LOWER + 1.2),
    "UpperArm.R": pose("UpperArm.R", "Y", -LOWER - 1.2),
}))
key(1 + n, relaxed({"Chest": pose("Chest", "X", 0.0), "Head": pose("Head", "Z", 1.5)}))

# appear: starts bowed (head down, chest bent, arms slightly forward and out) and straightens.
n = 58
new_action("appear", n + 1, False)
bowed = relaxed({
    "Spine": pose("Spine", "X", 9.0),
    "Chest": pose("Chest", "X", 12.0),
    "Neck": pose("Neck", "X", 10.0),
    "Head": pose("Head", "X", 16.0),
    "UpperArm.L": compose(pose("UpperArm.L", "Y", LOWER - 6.0), pose("UpperArm.L", "X", -10.0)),
    "UpperArm.R": compose(pose("UpperArm.R", "Y", -LOWER + 6.0), pose("UpperArm.R", "X", -10.0)),
})
key(1, bowed)
key(36, relaxed({"Chest": pose("Chest", "X", -3.0), "Head": pose("Head", "X", -3.0)}))   # lifts a little past upright
key(n + 1, relaxed({"Chest": pose("Chest", "X", 0.0), "Head": pose("Head", "Z", 1.5)}))

# hug: both arms rise forward and the forearms close in (toward Kaelen's back); holds the last pose.
n = 43
new_action("hug", n + 1, False)
key(1, relaxed({"Head": pose("Head", "Z", 1.5)}))
hug_pose = relaxed({
    "Chest": pose("Chest", "X", 4.0),
    "Head": pose("Head", "X", 8.0),
    "UpperArm.L": compose(pose("UpperArm.L", "Y", 15.0), pose("UpperArm.L", "X", -48.0)),
    "UpperArm.R": compose(pose("UpperArm.R", "Y", -15.0), pose("UpperArm.R", "X", -48.0)),
    "Forearm.L": compose(pose("Forearm.L", "Y", 45.0), pose("Forearm.L", "X", -30.0)),
    "Forearm.R": compose(pose("Forearm.R", "Y", -45.0), pose("Forearm.R", "X", -30.0)),
})
key(n + 1, hug_pose)

# walk: slow, calm steps (loop, 1.6 s). The long dress hides her legs, so it is a gentle hip sway with the
# chest and head countering it and the arms swinging a little.
n = 38
new_action("walk", n + 1, True)


def walk_pose(side):
    return relaxed({
        "Hips": compose(pose("Hips", "Z", 4.0 * side), pose("Hips", "Y", 2.5 * side)),
        "Spine": pose("Spine", "Z", -2.0 * side),
        "Chest": compose(pose("Chest", "Z", -2.5 * side), pose("Chest", "X", 1.5)),
        "Head": pose("Head", "Z", -1.5 * side),
        "UpperArm.L": compose(pose("UpperArm.L", "Y", LOWER), pose("UpperArm.L", "X", 7.0 * side)),
        "UpperArm.R": compose(pose("UpperArm.R", "Y", -LOWER), pose("UpperArm.R", "X", -7.0 * side)),
    })


key(1, walk_pose(1))
key(1 + n // 2, walk_pose(-1))
key(1 + n, walk_pose(1))

# talk: she speaks (loop, 4 s): head turns and tilts, a hand rises and falls a little with the words.
n = 96
new_action("talk", n + 1, True)
talk_a = relaxed({"Head": compose(pose("Head", "Z", 5.0), pose("Head", "X", 2.0)), "Chest": pose("Chest", "X", 0.0)})
talk_b = relaxed({
    "Head": compose(pose("Head", "Z", -4.0), pose("Head", "X", -3.0)),
    "Chest": pose("Chest", "X", -1.5),
    "UpperArm.R": compose(pose("UpperArm.R", "Y", -LOWER + 4.0), pose("UpperArm.R", "X", -22.0)),
    "Forearm.R": compose(pose("Forearm.R", "Y", -12.0), pose("Forearm.R", "X", -38.0)),
})
talk_c = relaxed({
    "Head": compose(pose("Head", "Z", 2.0), pose("Head", "X", 4.0)),
    "Chest": pose("Chest", "X", 1.0),
    "UpperArm.L": compose(pose("UpperArm.L", "Y", LOWER - 4.0), pose("UpperArm.L", "X", -14.0)),
    "Forearm.L": compose(pose("Forearm.L", "Y", 8.0), pose("Forearm.L", "X", -26.0)),
})
key(1, talk_a)
key(25, talk_b)
key(49, talk_c)
key(73, talk_b)
key(97, talk_a)

# reach: both arms open and extend forward, palms toward Kaelen, inviting the embrace (holds the last pose).
n = 36
new_action("reach", n + 1, False)
key(1, relaxed({"Head": pose("Head", "Z", 1.5)}))
key(n + 1, relaxed({
    "Chest": pose("Chest", "X", 2.0),
    "Head": pose("Head", "X", 4.0),
    "UpperArm.L": compose(pose("UpperArm.L", "Y", REACH_OUT), pose("UpperArm.L", "X", -60.0)),
    "UpperArm.R": compose(pose("UpperArm.R", "Y", -REACH_OUT), pose("UpperArm.R", "X", -60.0)),
    "Forearm.L": compose(pose("Forearm.L", "Y", -6.0), pose("Forearm.L", "X", -18.0)),
    "Forearm.R": compose(pose("Forearm.R", "Y", 6.0), pose("Forearm.R", "X", -18.0)),
}))

bpy.ops.object.mode_set(mode="OBJECT")
arm_obj.animation_data.action = None

# --- export ------------------------------------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True)
arm_obj.select_set(True)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.export_scene.gltf(
    filepath=DST, export_format="GLB", use_selection=True, export_animations=True,
    export_animation_mode="ACTIONS", export_force_sampling=True, export_yup=True,
)
print("exported", DST, [a.name for a in bpy.data.actions])
