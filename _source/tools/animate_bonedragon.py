"""Crea las animaciones del Bone Dragon (jefe 1) y exporta el .glb.

Uso (desde la raíz del repo):
    blender -b --factory-startup -P _source/tools/animate_bonedragon.py -- assets/bosses/bonedragon/bonedragon.glb

El dragón mira hacia -Y, con Z arriba. Signos útiles (ejes del armature):
    cuello/columna: pitch < 0 levanta la cabeza · mandíbula: pitch > 0 abre
    cola: pitch > 0 la levanta · patas: pitch < 0 lleva la pata hacia adelante
    alas: roll > 0 abre el ala izquierda, roll < 0 la derecha
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).parent))
from dragon_anim import Clip, arm_quat, export_glb, reweight_controls, spread, wave  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "_source/models/bonedragon"

NECK = ["spine.004", "spine.005", "spine.006"]
TAIL = [f"tail.{i:03d}" for i in range(1, 15)]
TAIL_W = [1 + i * 0.15 for i in range(14)]  # la punta se mueve más


# muerte: queda tumbado de costado (giro sobre el eje largo) y apoyado en el suelo
DEATH_ROLL = 75.0


def is_control(name):
    return "IK" in name or "control" in name.lower()


def wings(angle):
    return {"wing.L": (0, 0, angle), "wing.R": (0, 0, -angle)}


def neck(pitch, yaw=0.0, skull=0.0, jaw=0.0):
    out = {b: (p, y, 0) for (b, p), (_, y) in zip(spread(NECK, pitch).items(), spread(NECK, yaw).items())}
    out["skull"] = (skull, 0, 0)
    out["jaw"] = (jaw, 0, 0)
    return out


def tail(yaw=0.0, pitch=0.0):
    ys, ps = spread(TAIL, yaw, TAIL_W), spread(TAIL, pitch, TAIL_W)
    return {b: (ps[b], ys[b], 0) for b in TAIL}


def window(fn, start, end):
    """Aplica una función procedural solo entre dos frames, con entrada y salida suaves."""
    def g(f):
        if f < start or f > end:
            return {b: (0, 0, 0) for b in fn(start)}
        k = math.sin(math.pi * (f - start) / (end - start))
        return {b: tuple(x * k for x in v) for b, v in fn(f).items()}
    return g


def build(arm):
    clips = []

    # idle: respiración, cola y cuello ondulando, alas apenas moviéndose (bucle de 2 s)
    c = Clip(arm, "idle-loop", 61)
    c.add(wave(TAIL, 4, 60, 0.35))
    c.add(wave(NECK + ["skull"], 2.5, 60, 0.5))
    c.add(wave(["spine.002", "spine.003"], 1.5, 60, 0.0, axis="pitch"))
    c.add(lambda f: {"wing.L": (0, 0, 3 * math.sin(2 * math.pi * f / 60)),
                     "wing.R": (0, 0, -3 * math.sin(2 * math.pi * f / 60)),
                     "jaw": (2 + 2 * math.sin(2 * math.pi * f / 60), 0, 0)})
    clips.append(c)

    # roar: se levanta, abre alas y mandíbula, tiembla y vuelve
    c = Clip(arm, "roar", 70)
    c.pose(1, {})
    c.pose(15, {**neck(-30, skull=-10, jaw=12), "spine.002": (-4, 0, 0), "spine.003": (-6, 0, 0), **wings(25)})
    c.pose(25, {**neck(-40, skull=-15, jaw=38), "spine.002": (-6, 0, 0), "spine.003": (-8, 0, 0), **wings(45)})
    c.pose(52, {**neck(-38, skull=-15, jaw=38), "spine.002": (-6, 0, 0), "spine.003": (-8, 0, 0), **wings(45)})
    c.pose(70, {})
    c.add(window(lambda f: {"skull": (0, 3 * math.sin(f * 1.3), 2 * math.sin(f * 0.9))}, 25, 52))
    clips.append(c)

    # bite: se echa atrás (aviso), se lanza hacia adelante con la boca abierta y muerde
    c = Clip(arm, "bite", 45)
    c.pose(1, {}, {"root": (0, 0, 0)})
    c.pose(14, {**neck(-25, skull=-10, jaw=25), "spine.003": (-4, 0, 0)}, {"root": (0, 0.4, 0)})
    c.pose(22, {**neck(28, skull=12, jaw=38), "spine.003": (4, 0, 0)}, {"root": (0, -0.9, -0.1)})
    c.pose(26, {**neck(26, skull=10, jaw=0), "spine.003": (4, 0, 0)}, {"root": (0, -0.9, -0.1)})
    c.pose(45, {}, {"root": (0, 0, 0)})
    clips.append(c)

    # tail_sweep: carga la cola hacia un lado y barre hacia el otro
    c = Clip(arm, "tail_sweep", 60)
    c.pose(1, {})
    c.pose(16, {"spine.001": (0, 12, 0), **tail(-50, 5), **neck(0, yaw=15)})
    c.pose(30, {"spine.001": (0, -18, 0), **tail(110, 8), **neck(0, yaw=-20)})
    c.pose(42, {"spine.001": (0, -10, 0), **tail(60, 4), **neck(0, yaw=-10)})
    c.pose(60, {})
    clips.append(c)

    # stomp: se encabrita levantando las patas delanteras y golpea el suelo
    c = Clip(arm, "stomp", 50)
    front_up = {"upper_arm.L": (-45, 0, 0), "forearm.L": (40, 0, 0),
                "upper_arm.R": (-45, 0, 0), "forearm.R": (40, 0, 0)}
    front_down = {"upper_arm.L": (10, 0, 0), "forearm.L": (-5, 0, 0),
                  "upper_arm.R": (10, 0, 0), "forearm.R": (-5, 0, 0)}
    c.pose(1, {}, {"root": (0, 0, 0)})
    c.pose(18, {"spine.002": (-8, 0, 0), "spine.003": (-10, 0, 0), **front_up, **neck(-10, jaw=10), **wings(20)},
           {"root": (0, 0.2, 0.35)})
    c.pose(26, {"spine.002": (3, 0, 0), "spine.003": (4, 0, 0), **front_down, **neck(12, jaw=20), **wings(10)},
           {"root": (0, 0, -0.15)})
    c.pose(32, {"spine.002": (3, 0, 0), "spine.003": (4, 0, 0), **front_down, **neck(10, jaw=15), **wings(10)},
           {"root": (0, 0, -0.15)})
    c.pose(50, {}, {"root": (0, 0, 0)})
    clips.append(c)

    # death: último rugido, se tambalea y se derrumba de costado
    c = Clip(arm, "death", 100)
    # el hueso root gira sobre su cabeza (bajo el suelo): se compensa para que el torso
    # (a ~1.3 m de altura) termine apoyado a 0.6 m, ligeramente desplazado
    pivot = arm.matrix_world @ arm.data.bones["root"].head_local
    torso = Vector((0, 0, 1.3))
    rolled = pivot + arm_quat(roll=DEATH_ROLL) @ (torso - pivot)
    death_loc = tuple(Vector((0.4, 0, 0.6)) - rolled)
    dead = {**neck(35, yaw=15, skull=15, jaw=15), **tail(20, -10), **wings(-8),
            "upper_arm.L": (0, 0, 40), "upper_arm.R": (0, 0, -40),
            "thigh.L": (0, 0, 30), "thigh.R": (0, 0, -30), "spine.001": (0, 0, 10)}
    c.pose(1, {}, {"root": (0, 0, 0)})
    c.pose(20, {**neck(-30, skull=-10, jaw=30), "spine.003": (-8, 0, 0), **wings(30)}, {"root": (0, 0, 0.1)})
    c.pose(45, {**neck(10, yaw=15, jaw=20), "spine.001": (0, 0, 8), **wings(10), "root": (0, 0, 15)},
           {"root": (0.15, 0, -0.15)})
    c.pose(75, {**dead, "root": (0, 0, DEATH_ROLL)}, {"root": death_loc})
    c.pose(100, {**dead, "root": (0, 0, DEATH_ROLL)}, {"root": death_loc})
    clips.append(c)

    for c in clips:
        c.bake()


def main():
    out = Path(sys.argv[sys.argv.index("--") + 1:][0]).resolve()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.fbx(filepath=str(SRC / "bone dragon.fbx"), automatic_bone_orientation=False)
    bpy.ops.file.find_missing_files(directory=str(SRC))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    arm.animation_data_create()
    print(f"  pesos movidos de huesos de control: {reweight_controls(mesh, arm, is_control)}")
    build(arm)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC / "bonedragon_animated.blend"))
    export_glb(out)
    print(f"OK -> {out}")


main()
