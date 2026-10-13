"""Utilidades para animar por script esqueletos de criaturas en Blender.

Las rotaciones se escriben en ejes del armature, no del hueso, así una misma
"inclinación" significa lo mismo en cualquier hueso:
    pitch: alrededor del eje lateral (X)
    yaw:   alrededor del eje vertical (Z)
    roll:  alrededor del eje largo del cuerpo (Y)
Ángulos en grados. Cada pose clave es {hueso: (pitch, yaw, roll)}; los huesos que una pose
no menciona vuelven a 0 en ese frame. Los clips se exportan como pistas NLA (glTF).
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

AXIS = {"pitch": Vector((1, 0, 0)), "yaw": Vector((0, 0, 1)), "roll": Vector((0, 1, 0))}


def arm_quat(pitch=0.0, yaw=0.0, roll=0.0):
    return (Quaternion(AXIS["yaw"], math.radians(yaw))
            @ Quaternion(AXIS["pitch"], math.radians(pitch))
            @ Quaternion(AXIS["roll"], math.radians(roll)))


def to_local(arm, bone_name, q_arm):
    """Convierte una rotación en ejes del armature a la rotación de pose del hueso."""
    rest = arm.data.bones[bone_name].matrix_local.to_3x3()
    return (rest.inverted() @ q_arm.to_matrix() @ rest).to_quaternion()


def loc_local(arm, bone_name, v_arm):
    rest = arm.data.bones[bone_name].matrix_local.to_3x3()
    return rest.inverted() @ Vector(v_arm)


def spread(bones, total, weights=None):
    """Reparte un ángulo total entre varios huesos de una cadena."""
    weights = weights or [1.0] * len(bones)
    s = sum(weights)
    return {b: total * w / s for b, w in zip(bones, weights)}


def reweight_controls(mesh, arm, is_control):
    """Pasa el peso de los huesos de control (IK) al hueso de deformación más cercano."""
    fk = [b for b in arm.data.bones if not is_control(b.name) and b.parent]
    segs = [(b.name, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in fk]

    def nearest(p):
        best, dist = None, 1e9
        for name, h, t in segs:
            d = t - h
            k = max(0.0, min(1.0, (p - h).dot(d) / max(d.length_squared, 1e-9)))
            dd = (h + d * k - p).length
            if dd < dist:
                best, dist = name, dd
        return best

    groups = {g.index: g for g in mesh.vertex_groups}
    moved = 0
    for v in mesh.data.vertices:
        p = mesh.matrix_world @ v.co
        for g in list(v.groups):
            grp = groups[g.group]
            if is_control(grp.name) and g.weight > 0:
                target = nearest(p)
                tg = mesh.vertex_groups.get(target) or mesh.vertex_groups.new(name=target)
                tg.add([v.index], g.weight, "ADD")
                grp.remove([v.index])
                moved += 1
    return moved


class Clip:
    def __init__(self, arm, name, length):
        self.arm, self.name, self.length = arm, name, length
        self.poses = {}   # frame -> {bone: (pitch, yaw, roll)}
        self.locs = {}    # frame -> {bone: (x, y, z)} en ejes del armature
        self.procedural = []  # funciones f(frame) -> {bone: (pitch, yaw, roll)} que se suman

    def pose(self, frame, rot=None, loc=None):
        self.poses.setdefault(frame, {}).update(rot or {})
        self.locs.setdefault(frame, {}).update(loc or {})
        return self

    def add(self, fn):
        self.procedural.append(fn)
        return self

    def bake(self):
        arm = self.arm
        action = bpy.data.actions.new(self.name)
        arm.animation_data.action = action
        rot_bones = sorted({b for p in self.poses.values() for b in p})
        loc_bones = sorted({b for p in self.locs.values() for b in p})
        frames = set(self.poses) | {1, self.length}
        step_frames = set(range(1, self.length + 1, 2)) | {self.length} if self.procedural else set()
        proc_bones = set()
        for fn in self.procedural:
            proc_bones |= set(fn(1))
        all_rot = sorted(set(rot_bones) | proc_bones)
        key_frames = sorted(frames | step_frames)

        def interp(table, frame, bone, default):
            ks = sorted(table)
            vals = [(f, table[f].get(bone, default)) for f in ks]
            if not vals:
                return default
            if frame <= vals[0][0]:
                return vals[0][1]
            for (f0, v0), (f1, v1) in zip(vals, vals[1:]):
                if f0 <= frame <= f1:
                    t = (frame - f0) / (f1 - f0)
                    t = t * t * (3 - 2 * t)  # suavizado
                    return tuple(a + (b - a) * t for a, b in zip(v0, v1))
            return vals[-1][1]

        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
        for f in key_frames:
            for b in all_rot:
                base = interp(self.poses, f, b, (0.0, 0.0, 0.0)) if self.poses else (0.0, 0.0, 0.0)
                extra = [0.0, 0.0, 0.0]
                for fn in self.procedural:
                    e = fn(f).get(b)
                    if e:
                        extra = [x + y for x, y in zip(extra, e)]
                p, y, r = (a + e for a, e in zip(base, extra))
                pb = arm.pose.bones[b]
                pb.rotation_quaternion = to_local(arm, b, arm_quat(p, y, r))
                pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
            for b in loc_bones:
                v = interp(self.locs, f, b, (0.0, 0.0, 0.0))
                pb = arm.pose.bones[b]
                pb.location = loc_local(arm, b, v)
                pb.keyframe_insert("location", frame=f, group=b)
        action.use_fake_user = True
        arm.animation_data.action = None
        track = arm.animation_data.nla_tracks.new()
        track.name = self.name
        track.strips.new(self.name, 1, action)
        for pb in arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        print(f"  + {self.name} ({self.length} frames)")
        return action


def wave(bones, amp, period, phase_step, axis="yaw", phase0=0.0):
    """Onda que recorre una cadena (cola, cuello). period en frames."""
    idx = {"pitch": 0, "yaw": 1, "roll": 2}[axis]

    def fn(f):
        out = {}
        for i, b in enumerate(bones):
            v = [0.0, 0.0, 0.0]
            v[idx] = amp * math.sin(2 * math.pi * f / period - i * phase_step + phase0)
            out[b] = tuple(v)
        return out
    return fn


def export_glb(path):
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB",
                              export_animation_mode="NLA_TRACKS", export_yup=True)
