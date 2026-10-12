# Estado de assets de personajes

Revisión de los archivos fuente en `_source/models` (2026-10-12): esqueleto, malla enlazada (skin) y animaciones que trae cada modelo.
Kaelen y Elysia usan modelos existentes (se descartó modelarlos por tiempo).

Estados: `listo` / `falta rig` / `falta animación` / `reemplazado`.

## Resumen

| Rol | Fuente | Esqueleto | Animaciones incluidas | Estado | Trabajo pendiente |
|---|---|---|---|---|---|
| Kaelen | `low-poly-woman-knight/source/women knight final.fbx` | **No** | — | falta rig | Auto-rig Mixamo + `idle`, `walk`, `run`, `roll`, `attack_1..3`, `hurt`, `death` (*in place*). Falta `license.txt`. |
| Elysia | `ancient-elf-lady-psx/source/ancient lady elf psx.glb` (744 tris) | **No** | — | falta rig | Auto-rig Mixamo + idle, levantarse, abrazo. Falta `license.txt`. |
| Esbirros 3 | `TheWrapper V2/MonsterPSX.fbx` | Sí, propio (`MonsterPSX_Rig`) | `Attack_Lunge`, `Idle_Watchful`, `Run_Frantic`, `Scream.lol`, `Walk_Nervous`, `WallSlam_Recover` | listo | Exportar a `assets/minions/thewrapper/thewrapper.glb`; renombrar a `attack`, `idle`, `run`, `scream`, `walk`, `hurt` (WallSlam_Recover). Falta `death` → tween/caída. |
| Esbirros 2 | `Plague Arcanist/Plague Arcanist/Plague Arcanist.fbx` | Sí, Mixamo | 10 clips con nombres genéricos (`Armature.00X\|mixamo.com\|Layer0`) | listo | Identificar cada clip y renombrar a `idle`, `walk`, `attack`, `hurt`, `death`. Exportar a `assets/minions/plague_arcanist/`. |
| Élite 3 (opcional) | `aura_battler_dunbine_-_vierres/scene.gltf` (1148 tris) | No (no lo necesita) | — | listo | Mecha rígido: flotar, embestida y giro con tweens en Godot. |
| Esbirros 1 | `Skeleton/Skeleton/skeleton.fbx` | **No** | — | falta rig | Auto-rig en Mixamo + `idle`, `walk`, `attack`, `hurt`, `death` (*in place*). |
| Élite 1 | `knight__ps1_psx/scene.gltf` (544 tris) | Propio, 26 huesos | Solo `Idle` | falta rig | Recomendado: subir la malla sin rig a Mixamo y descargar las 5 animaciones de esbirro. |
| Jefe 1 | `bonedragon/bone dragon.fbx` | **Sí**, ~70 huesos con skin (no hace falta crear rig) | Ninguna | falta animación | Keyframes en Blender: `idle`, `roar`, `bite`, `tail_sweep`, `stomp`, `death`. |
| Jefe 2 | `MaleniaPsx/Malenia/malenia.fbx` | Sí, metarig (Rigify) | `Idle`, `IdleMalenia` | falta animación | Quitar el metarig y re-riggear en Mixamo (más simple que el retarget): `idle`, `walk`, `slash`, `thrust`, `spin`, `hurt`, `death`. Ver `guia-mixamo.md`. |
| Jefe 3 | `mecha-king-ghidorah/source/Mecha King Ghidorah.fbx` (~26k tris) | **Sí**, con skin (3 cuellos, colas, alas) | Ninguna | falta animación | 1) Reducir a ~8k tris conservando pesos. 2) Keyframes: `idle`, `roar`, `bite`, `tail_sweep`, `beam`, `death`. |
| Reserva (jefe 3) | `psx_insectoid_demon/scene.gltf` (622 tris) | No | — | falta rig | Solo si Ghidorah falla. No humanoide: rig manual en Blender. |
| Reserva | `DoriOri.fbx` | Sí (`root`) | Solo `Pose` | falta animación | Sin uso previsto. |

Procedimiento Mixamo paso a paso: [`guia-mixamo.md`](guia-mixamo.md).

## Prioridad de trabajo

1. Animaciones de Bone Dragon y Ghidorah (12 clips a mano) — cuello de botella.
2. Decimar Ghidorah antes de animar.
3. Retarget de Malenia (BoneMap metarig → Mixamo).
4. Mixamo para Kaelen, Elysia, Skeleton y Knight.
5. Renombrar clips de Plague Arcanist y TheWrapper.

## Pendiente de medir al importar

Factor de escala y altura en `scale_reference` para cada modelo (se completa al exportar el `.glb`).
