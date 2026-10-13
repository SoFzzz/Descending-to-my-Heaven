"""Arma los .glb de los personajes de Mixamo con los nombres de clip que espera el código.

Uso (desde la raíz del repo), un personaje por ejecución:
    blender -b --factory-startup -P _source/tools/build_characters.py -- kaelen
    (kaelen | skeleton | knight)

Las alturas (m) son las de §7.4 del documento de diseño.
Para cambiar qué animación de Mixamo se usa en un clip, editar la tabla del personaje.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from combine_mixamo import combine  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
MX = REPO / "_source/mixamo"

CHARACTERS = {
    "kaelen": ("assets/characters/kaelen/kaelen.glb", 1.70, {
        "idle": "Great Sword Idle",
        "walk": "Great Sword Walk-ahead",
        "walk_back": "Great Sword Walk-back",
        "strafe_left": "Great Sword Strafe-left",
        "strafe_right": "Great Sword Strafe",
        "run": "Great Sword Run",
        "roll": "Stand To Roll",
        "attack_1": "Great Sword Slash",
        "attack_2": "Two Hand Sword Combo",
        "attack_3": "Great Sword High Spin Attack",
        "hurt": "Great Sword Impact",
        "death": "Sword And Shield Death",
        # extras (no los pide el plan; quedan disponibles)
        "roll_to_run": "Quick Roll To Run",
        "jump_attack": "Great Sword Jump Attack",
        "block": "Great Sword Blocking",
        "turn_180": "Great Sword 180 Turn-right",
        "draw_sword": "Draw A Great Sword 2",
        "jump": "Sword And Shield Jump",
    }),
    "skeleton": ("assets/minions/skeleton/skeleton.glb", 1.75, {
        "idle": "Zombie Idle",
        "walk": "Walk",
        "attack": "Attack",
        "hurt": "Impact",
        "death": "Dying",
    }),
    "knight": ("assets/minions/knight/knight.glb", 2.10, {
        "idle": "Idle",
        "walk": "Sword And Shield Run",  # no hay caminar: se usa correr
        "attack": "Sword And Shield Slash",
        "attack_2": "Sword And Shield Attack",
        "combo": "One Hand Club Combo",
        "hurt": "Sword And Shield Impact",
        "death": "Falling Back Death",
    }),
}


BASE_FROM_ANIM = {"skeleton": "Zombie Idle", "knight": "Idle"}


def main() -> None:
    name = sys.argv[sys.argv.index("--") + 1]
    out, height, table = CHARACTERS[name]
    clips = {clip: MX / name / "anims" / f"{src}.fbx" for clip, src in table.items()}
    missing = [str(p) for p in clips.values() if not p.exists()]
    if missing:
        raise SystemExit(f"Faltan archivos: {missing}")
    # Skeleton y Knight: su base.fbx es el subido a Mixamo (sin rig); se usa una animación
    # descargada "with skin", que trae malla y esqueleto
    base = MX / name / "anims" / f"{BASE_FROM_ANIM[name]}.fbx" if name in BASE_FROM_ANIM else MX / name / "base.fbx"
    combine(base, clips, REPO / out, height)


main()
