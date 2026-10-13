# Estado de assets de personajes

Revisión de los archivos fuente en `_source/models` (2026-10-12): esqueleto, malla enlazada (skin) y animaciones que trae cada modelo.
Kaelen y Elysia usan modelos existentes (se descartó modelarlos por tiempo).

Estados: `listo` / `falta rig` / `falta animación` / `reemplazado`.

## Resumen

| Rol | Fuente | Esqueleto | Animaciones incluidas | Estado | Trabajo pendiente |
|---|---|---|---|---|---|
| Kaelen | `low-poly-woman-knight/source/women knight final.fbx` | Sí, Mixamo (`_source/mixamo/kaelen/base.fbx`) | 18 clips Mixamo en `_source/mixamo/kaelen/anims/` (ver sección abajo) | listo | Renombrar los clips a los nombres de la guía y ejecutar `combine_mixamo.py`. Falta `license.txt`. |
| Elysia | `ancient-elf-lady-psx/source/ancient lady elf psx.glb` (744 tris) | **No** | — | falta rig | Auto-rig Mixamo + idle, levantarse, abrazo. Falta `license.txt`. |
| Esbirros 3 | `TheWrapper V2/MonsterPSX.fbx` | Sí, propio (`MonsterPSX_Rig`) | `Attack_Lunge`, `Idle_Watchful`, `Run_Frantic`, `Scream.lol`, `Walk_Nervous`, `WallSlam_Recover` | listo | Exportar a `assets/minions/thewrapper/thewrapper.glb`; renombrar a `attack`, `idle`, `run`, `scream`, `walk`, `hurt` (WallSlam_Recover). Falta `death` → tween/caída. |
| Esbirros 2 | `Plague Arcanist/Plague Arcanist/Plague Arcanist.fbx` | Sí, Mixamo | 10 clips con nombres genéricos (`Armature.00X\|mixamo.com\|Layer0`) | listo | Identificar cada clip y renombrar a `idle`, `walk`, `attack`, `hurt`, `death`. Exportar a `assets/minions/plague_arcanist/`. |
| Élite 3 (opcional) | `aura_battler_dunbine_-_vierres/scene.gltf` (1148 tris) | No (no lo necesita) | — | listo | Mecha rígido: flotar, embestida y giro con tweens en Godot. |
| Esbirros 1 | `Skeleton/Skeleton/skeleton.fbx` (origen); base Mixamo en `_source/mixamo/skeleton/base.fbx` | Sí, Mixamo | 5 clips Mixamo en `_source/mixamo/skeleton/anims/`: `Attack`, `Dying`, `Impact`, `Walk`, `Zombie Idle` | listo | Renombrar a `attack`, `death` (Dying), `hurt` (Impact), `walk`, `idle` (Zombie Idle) y ejecutar `combine_mixamo.py`. |
| Élite 1 | `knight__ps1_psx/scene.gltf` (544 tris); base Mixamo en `_source/mixamo/knight/base.fbx` | Sí, Mixamo | 7 clips Mixamo en `_source/mixamo/knight/anims/`: `Idle`, `Sword And Shield Run`, `Sword And Shield Attack`, `Sword And Shield Slash`, `One Hand Club Combo`, `Sword And Shield Impact`, `Falling Back Death` | listo | Renombrar a `idle`, `attack` (Attack o Slash), `hurt` (Impact), `death` (Falling Back Death) y ejecutar `combine_mixamo.py`. Falta `walk`: usar `Sword And Shield Run` si se ve bien o buscar otro en Mixamo. Falta `license.txt` en `assets/`. |
| Jefe 1 | `bonedragon/bone dragon.fbx` | **Sí**, ~70 huesos con skin (no hace falta crear rig) | Ninguna | falta animación | Keyframes en Blender: `idle`, `roar`, `bite`, `tail_sweep`, `stomp`, `death`. |
| Jefe 2 | `MaleniaPsx/Malenia/malenia.fbx` | Sí, metarig (Rigify) | `Idle`, `IdleMalenia` | falta animación | Quitar el metarig y re-riggear en Mixamo (más simple que el retarget): `idle`, `walk`, `slash`, `thrust`, `spin`, `hurt`, `death`. Ver `guia-mixamo.md`. |
| Jefe 3 | `mecha-king-ghidorah/source/Mecha King Ghidorah.fbx` (~26k tris) | **Sí**, con skin (3 cuellos, colas, alas) | Ninguna | falta animación | 1) Reducir a ~8k tris conservando pesos. 2) Keyframes: `idle`, `roar`, `bite`, `tail_sweep`, `beam`, `death`. |
| Reserva (jefe 3) | `psx_insectoid_demon/scene.gltf` (622 tris) | No | — | falta rig | Solo si Ghidorah falla. No humanoide: rig manual en Blender. |
| Reserva | `DoriOri.fbx` | Sí (`root`) | Solo `Pose` | falta animación | Sin uso previsto. |

Procedimiento Mixamo paso a paso: [`guia-mixamo.md`](guia-mixamo.md).

## Animaciones de Kaelen (Mixamo)

Carpeta: `_source/mixamo/kaelen/anims/`. Los archivos conservan el nombre original de Mixamo; aún no están renombrados, así que `combine_mixamo.py` todavía no los puede usar tal cual.

| Archivo | Uso probable (nombre en la guía) | Notas |
|---|---|---|
| `Great Sword Walk-ahead.fbx` | `walk` | |
| `Great Sword Run.fbx` | `run` | |
| `Quick Roll To Run.fbx` | `roll` | Alternativa: `Stand To Roll.fbx`. Revisar que dure ~0.6 s. |
| `Great Sword Slash.fbx` | `attack_1` | |
| `Two Hand Sword Combo.fbx` | `attack_2` | Revisar que encadene con `attack_1`. |
| `Great Sword High Spin Attack.fbx` | `attack_3` | Alternativa: `Great Sword Jump Attack.fbx`. |
| `Great Sword Impact.fbx` | `hurt` | |
| `Sword And Shield Death.fbx` | `death` | No hay muerte a dos manos; es de espada y escudo. |
| `Great Sword Blocking.fbx` | — (extra) | Posible clip de bloqueo. |
| `Great Sword Strafe.fbx`, `Great Sword Strafe-left.fbx` | — (extra) | Movimiento lateral. |
| `Great Sword 180 Turn-right.fbx` | — (extra) | Giro. |
| `Draw A Great Sword 2.fbx` | — (extra) | Desenvainar. |
| `Sword And Shield Jump.fbx` | — (extra) | Salto con espada y escudo. |
| `Great Sword Idle.fbx` | `idle` | Añadido después; reposo con mandoble. |

Base: `_source/mixamo/kaelen/base.fbx` (T-pose, con skin; antes `Kaden-R.fbx`).

## Prioridad de trabajo

1. Animaciones de Bone Dragon y Ghidorah (12 clips a mano) — cuello de botella.
2. Decimar Ghidorah antes de animar.
3. Retarget de Malenia (BoneMap metarig → Mixamo).
4. Mixamo para Kaelen, Elysia, Skeleton y Knight.
5. Renombrar clips de Plague Arcanist y TheWrapper.

## Pendiente de medir al importar

Factor de escala y altura en `scale_reference` para cada modelo (se completa al exportar el `.glb`).
