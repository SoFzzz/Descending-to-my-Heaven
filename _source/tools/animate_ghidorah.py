"""Reduce Mecha King Ghidorah (jefe 3), crea sus animaciones y exporta el .glb.

Uso (desde la raíz del repo):
    blender -b --factory-startup -P _source/tools/animate_ghidorah.py -- assets/bosses/ghidorah/ghidorah.glb

Esqueleto estilo MMD (nombres en japonés): 首 = cuello, 頭 = cabeza, 顎 = mandíbula,
尾 = cola, 翼 = ala, 足/ひざ/足首 = muslo/rodilla/tobillo, 上半身/下半身 = torso/cadera,
左 = izquierda (+X), 右 = derecha (-X). Mira hacia -Y, Z arriba, mide ~3.5 m (escalar ×3 en Godot).
Signos (ejes del armature): cuello pitch < 0 levanta la cabeza, > 0 la baja; mandíbula
pitch > 0 abre; pierna pitch < 0 adelanta; alas roll > 0 abre la izquierda.
"""
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).parent))
from dragon_anim import Clip, export_glb, spread, wave  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "_source/models/mecha-king-ghidorah"

# proporción de caras que se conserva por malla (26k -> ~9k triángulos)
DECIMATE = {"Ghidorah_Flesh": 0.2, "Mecha_Body": 0.5, "Wings": 0.4, "MKG_Head": 0.45, "knee_pads": 0.35}

NECK_C = ["首", "首2", "首3", "首4", "首5", "首6", "首7", "首8", "首9"]
NECK_L = ["左首", "左首2", "左首3", "左首4", "左首5"]
NECK_R = ["右首", "右首2", "右首3", "右首4", "右首5"]
HEADS = {"c": (NECK_C, "頭", "jaw"), "l": (NECK_L, "左頭", "左顎"), "r": (NECK_R, "右頭", "右顎")}
TAIL_L = ["左尾"] + [f"左尾{i}" for i in range(2, 11)]
TAIL_R = ["右尾"] + [f"右尾{i}" for i in range(2, 11)]
TAIL_W = [1 + i * 0.2 for i in range(10)]
ROOT, CENTER, UPPER, LOWER = "全ての親", "センター", "上半身", "下半身"


def head(key, pitch=0.0, yaw=0.0, skull=0.0, jaw=0.0, base=False):
    """base=True concentra la curva en la base del cuello: se estira en vez de enroscarse."""
    chain, skull_bone, jaw_bone = HEADS[key]
    w = [len(chain) - i for i in range(len(chain))] if base else None
    ps, ys = spread(chain, pitch, w), spread(chain, yaw)
    out = {b: (ps[b], ys[b], 0) for b in chain}
    out[skull_bone] = (skull, 0, 0)
    out[jaw_bone] = (jaw, 0, 0)
    return out


def heads(pitch=0.0, skull=0.0, jaw=0.0, side_yaw=0.0):
    return {**head("c", pitch, 0, skull, jaw),
            **head("l", pitch, side_yaw, skull, jaw),
            **head("r", pitch, -side_yaw, skull, jaw)}


def tails(yaw=0.0, pitch=0.0):
    out = {}
    for chain in (TAIL_L, TAIL_R):
        ys, ps = spread(chain, yaw, TAIL_W), spread(chain, pitch, TAIL_W)
        out.update({b: (ps[b], ys[b], 0) for b in chain})
    return out


def wings(angle):
    return {"左翼": (0, 0, angle), "右翼": (0, 0, -angle)}


def window(fn, start, end):
    def g(f):
        if f < start or f > end:
            return {b: (0, 0, 0) for b in fn(start)}
        k = math.sin(math.pi * (f - start) / (end - start))
        return {b: tuple(x * k for x in v) for b, v in fn(f).items()}
    return g


def build(arm):
    clips = []

    # idle: los tres cuellos ondulan desfasados, respiración, colas y alas (bucle de 2 s)
    c = Clip(arm, "idle-loop", 61)
    c.add(wave(NECK_C + ["頭"], 3, 60, 0.3))
    c.add(wave(NECK_L + ["左頭"], 4, 60, 0.4, phase0=2.1))
    c.add(wave(NECK_R + ["右頭"], 4, 60, 0.4, phase0=4.2))
    c.add(wave([UPPER, "上半身２"], 1.5, 60, 0.0, axis="pitch"))
    c.add(wave(TAIL_L, 3, 60, 0.3))
    c.add(wave(TAIL_R, 3, 60, 0.3, phase0=1.0))
    c.add(lambda f: {**wings(4 * math.sin(2 * math.pi * f / 60)),
                     "jaw": (3 + 3 * math.sin(2 * math.pi * f / 60), 0, 0),
                     "左顎": (3 + 3 * math.sin(2 * math.pi * f / 60 + 2), 0, 0),
                     "右顎": (3 + 3 * math.sin(2 * math.pi * f / 60 + 4), 0, 0)})
    clips.append(c)

    # roar: las tres cabezas al cielo, alas abiertas, temblor
    c = Clip(arm, "roar", 70)
    c.pose(1, {})
    c.pose(15, {**heads(-25, -10, 15, side_yaw=10), UPPER: (-6, 0, 0), **wings(25)})
    c.pose(25, {**heads(-40, -15, 40, side_yaw=18), UPPER: (-10, 0, 0), **wings(40)})
    c.pose(52, {**heads(-38, -15, 40, side_yaw=18), UPPER: (-10, 0, 0), **wings(40)})
    c.pose(70, {})
    c.add(window(lambda f: {"頭": (0, 3 * math.sin(f * 1.3), 0), "左頭": (0, 3 * math.sin(f * 1.1), 0),
                            "右頭": (0, 3 * math.sin(f * 1.5), 0)}, 25, 52))
    clips.append(c)

    # bite: la cabeza central se echa atrás (aviso) y muerde el suelo; queda abajo un momento
    # (ventana para golpearla) y vuelve
    c = Clip(arm, "bite", 64)
    c.pose(1, {}, {CENTER: (0, 0, 0)})
    c.pose(16, {**head("c", -30, 0, -10, 25), **head("l", 0, 20), **head("r", 0, -20), UPPER: (-8, 0, 0)},
           {CENTER: (0, 0.2, 0)})
    c.pose(24, {**head("c", 62, 0, -20, 40, base=True), **head("l", 10, 25), **head("r", 10, -25), UPPER: (42, 0, 0)},
           {CENTER: (0, -0.5, -0.35)})
    c.pose(28, {**head("c", 62, 0, -20, 0, base=True), **head("l", 10, 25), **head("r", 10, -25), UPPER: (42, 0, 0)},
           {CENTER: (0, -0.5, -0.35)})
    c.pose(44, {**head("c", 60, 0, -20, 5, base=True), **head("l", 8, 20), **head("r", 8, -20), UPPER: (40, 0, 0)},
           {CENTER: (0, -0.5, -0.35)})
    c.pose(64, {}, {CENTER: (0, 0, 0)})
    clips.append(c)

    # tail_sweep: gira el cuerpo y barre con las dos colas
    c = Clip(arm, "tail_sweep", 60)
    c.pose(1, {})
    c.pose(16, {UPPER: (0, -12, 0), LOWER: (0, -15, 0), **tails(-40, 10), **heads(0, side_yaw=8)})
    c.pose(30, {UPPER: (0, 20, 0), LOWER: (0, 30, 0), **tails(100, 15), **heads(5, side_yaw=-8)})
    c.pose(42, {UPPER: (0, 10, 0), LOWER: (0, 15, 0), **tails(55, 8)})
    c.pose(60, {})
    clips.append(c)

    # beam: carga con las bocas abiertas y dispara al frente (el rayo es un efecto en Godot)
    c = Clip(arm, "beam", 80)
    aim = {**heads(12, 5, 35, side_yaw=4), UPPER: (4, 0, 0), **wings(30)}
    c.pose(1, {})
    c.pose(20, {**heads(-15, -10, 20, side_yaw=10), UPPER: (-8, 0, 0), **wings(35)})
    c.pose(27, aim)
    c.pose(65, aim)
    c.pose(80, {})
    c.add(window(lambda f: {"頭": (0.8 * math.sin(f * 2.1), 0, 0), "左頭": (0.8 * math.sin(f * 2.4), 0, 0),
                            "右頭": (0.8 * math.sin(f * 1.8), 0, 0)}, 27, 65))
    clips.append(c)

    # death: grito, retrocede y cae de espaldas con los cuellos sin fuerza
    c = Clip(arm, "death", 100)
    limp = {**heads(25, 10, 25, side_yaw=25), **tails(10, 0), **wings(-10)}
    c.pose(1, {}, {CENTER: (0, 0, 0)})
    c.pose(20, {**heads(-35, -15, 40, side_yaw=15), UPPER: (-10, 0, 0), **wings(35)}, {CENTER: (0, 0, 0)})
    c.pose(50, {**heads(10, 0, 30, side_yaw=20), UPPER: (-15, 0, 0), "左ひざ+": (15, 0, 0),
                "右ひざ+": (15, 0, 0), **wings(15)}, {CENTER: (0, 0.3, -0.25)})
    c.pose(80, {**limp, ROOT: (-80, 0, 0), UPPER: (5, 0, 0)}, {CENTER: (0, 0.3, -0.25)})
    c.pose(100, {**limp, ROOT: (-80, 0, 0), UPPER: (5, 0, 0)}, {CENTER: (0, 0.3, -0.25)})
    clips.append(c)

    for c in clips:
        c.bake()


def decimate():
    tot = 0
    for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
        ratio = DECIMATE.get(obj.name)
        if ratio:
            bpy.context.view_layer.objects.active = obj
            mod = obj.modifiers.new("Decimate", "DECIMATE")
            mod.ratio = ratio
            bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
            bpy.ops.object.modifier_apply(modifier=mod.name)
        tot += sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"  triángulos tras reducir: {tot}")


def main():
    out = Path(sys.argv[sys.argv.index("--") + 1:][0]).resolve()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.fbx(filepath=str(SRC / "source/Mecha King Ghidorah.fbx"),
                             automatic_bone_orientation=False)
    bpy.ops.file.find_missing_files(directory=str(SRC / "textures"))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    arm.animation_data_create()
    decimate()
    build(arm)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC / "ghidorah_animated.blend"))
    export_glb(out)
    print(f"OK -> {out}")


main()
