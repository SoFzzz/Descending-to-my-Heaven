# Estado de assets de personajes

Revisión de los archivos fuente en `_source/models` (2026-10-12): esqueleto, malla enlazada (skin) y animaciones que trae cada modelo.
Kaelen y Elysia usan modelos existentes (se descartó modelarlos por tiempo).

Estados: `listo` / `falta rig` / `falta animación` / `reemplazado`.

## Resumen

| Rol | Fuente | Esqueleto | Animaciones incluidas | Estado | Trabajo pendiente |
|---|---|---|---|---|---|
| Kaelen | `low-poly-woman-knight` → Mixamo (`_source/mixamo/kaelen/`) | Sí, Mixamo | 18 clips: `idle`, `walk`, `walk_back`, `strafe_left`, `strafe_right`, `run`, `roll`, `attack_1..3`, `hurt`, `death` + extras (`roll_to_run`, `jump_attack`, `block`, `turn_180`, `draw_sword`, `jump`) | listo | `assets/characters/kaelen/kaelen.glb` (1.70 m). `roll` dura 2.4 s: reproducir más rápido (`speed_scale`) para llegar a 0.6 s, o usar `roll_to_run` (1.4 s). `attack_2` es un combo largo (3.3 s). Sin arma: el mandoble se engancha en Godot a `mixamorig:RightHand`. Falta `license.txt`. |
| Elysia | `ancient-elf-lady-psx/source/ancient lady elf psx.glb` (744 tris) | No (no lo necesita) | — | listo | Sin rig ni animaciones (decisión 2026-10-12): Mixamo deforma su vestido de una pieza y el pelo largo. Modelo estático en pose de reposo; en Godot un `Tween` de respiración (sube/baja ~2 cm en bucle) y giro hacia Kaelen; el abrazo se resuelve con fundido de cámara. Exportar a `assets/characters/elysia/elysia.glb` a 1.60 m. Falta `license.txt`. |
| Esbirros 3 | `TheWrapper V2/MonsterPSX.fbx` | Sí, propio (`MonsterPSX_Rig`) | `idle`, `walk`, `run`, `attack`, `hurt`, `scream` | listo | `assets/minions/thewrapper/thewrapper.glb` (2.00 m). Se borraron las mallas `WGT_*` (formas de control del rig). No tiene `death`: tween o caída en Godot. |
| Esbirros 2 | `Plague Arcanist/Plague Arcanist/Plague Arcanist.fbx` | Sí, Mixamo | `idle`, `idle_alt`, `walk`, `strafe`, `attack` (zarpazo), `attack_cast` (hechizo al frente), `attack_leap`, `taunt`, `knockdown`, `hurt`, `death` | listo | `assets/minions/plague_arcanist/plague_arcanist.glb` (1.80 m). `hurt` (frames 1–15) y `death` (frames 1–42) son recortes de `knockdown`: el pack no trae muerte propia. |
| Élite 3 (opcional) | `aura_battler_dunbine_-_vierres/scene.gltf` (1148 tris) | No (no lo necesita) | — | listo | Mecha rígido: flotar, embestida y giro con tweens en Godot. |
| Esbirros 1 | `Skeleton` → Mixamo (`_source/mixamo/skeleton/`) | Sí, Mixamo | `idle`, `walk`, `attack`, `hurt`, `death` | listo | `assets/minions/skeleton/skeleton.glb` (1.75 m). |
| Élite 1 | `knight__ps1_psx` → Mixamo (`_source/mixamo/knight/`) | Sí, Mixamo | `idle`, `walk`, `attack`, `attack_2`, `combo`, `hurt`, `death` | listo | `assets/minions/knight/knight.glb` (2.10 m). `walk` es `Sword And Shield Run` (no hay caminar): reproducirlo más lento. Espada aparte en `_source/mixamo/knight/sword.fbx` → engancharla en Godot a `mixamorig:RightHand`. Falta `license.txt`. |
| Jefe 1 | `bonedragon/bone dragon.fbx` | Sí, ~70 huesos (los pesos de los huesos de control IK se pasaron al hueso FK más cercano) | `idle` (bucle), `roar`, `bite`, `tail_sweep`, `stomp`, `death` | listo | `assets/bosses/bonedragon/bonedragon.glb`, generado con `_source/tools/animate_bonedragon.py` (poses clave por script; editable en `_source/models/bonedragon/bonedragon_animated.blend`). Mide ~7.7 m de largo: escala 1. `bite` y `stomp` mueven el hueso `root`; `death` termina tumbado de costado. |
| Jefe 2 | `dead_oath_hunter/DEAD OATH HUNTER.blend` (reemplaza a Malenia, 2026-10-13) | Sí, Mixamo (65 huesos) | 18 clips (ver sección abajo) | listo | `assets/bosses/dead_oath_hunter/dead_oath_hunter.glb` (generado con `_source/tools/export_dead_oath_hunter.py`; espada pesada a la mano derecha). Mide ~1.5 m → escalar a 2.60 m en Godot. Licencia **no comercial**: acreditar a imaginais. |
| Reserva (esbirro) | `straw_reaper/THE STRAW REAPER new.fbx` | Sí, Mixamo | 9 clips Mixamo sin nombre (17–366 frames) + `Scarecrow anim` (701 frames, todas pegadas) | falta animación | Solo si un esbirro falla o se ve peor. Identificar y nombrar clips como se hizo con el Hunter. Hoz incluida. Uso comercial permitido (crédito opcional a imaginais). |
| Jefe 3 | `mecha-king-ghidorah/source/Mecha King Ghidorah.fbx` (26k → 9.1k tris) | Sí, estilo MMD (nombres en japonés; 3 cuellos, 2 colas, alas) | `idle` (bucle), `roar`, `bite`, `tail_sweep`, `beam`, `death` | listo | `assets/bosses/ghidorah/ghidorah.glb`, generado con `_source/tools/animate_ghidorah.py` (reduce la malla y crea las poses; editable en `_source/models/mecha-king-ghidorah/ghidorah_animated.blend`). Mide ~3.5 m: **escalar ×3** en Godot. En `bite` la cabeza central baja casi al suelo entre los frames 24 y 44 (ventana para golpearla); el rayo de `beam` es un efecto en Godot (frames 27–65). |
| Reserva (jefe 3) | `psx_insectoid_demon/scene.gltf` (622 tris) | No | — | falta rig | Solo si Ghidorah falla. No humanoide: rig manual en Blender. |
| Reserva | `DoriOri.fbx` | Sí (`root`) | Solo `Pose` | falta animación | Sin uso previsto. |

Procedimiento Mixamo paso a paso: [`guia-mixamo.md`](guia-mixamo.md).

## Cómo se generan los `.glb`

| Personajes | Script | Comando |
|---|---|---|
| Kaelen, Skeleton, Knight | `_source/tools/build_characters.py` (tabla clip ← animación de Mixamo) | `blender -b --factory-startup -P _source/tools/build_characters.py -- kaelen` |
| Plague Arcanist, TheWrapper | `_source/tools/export_multi_action.py` (varias acciones en un FBX) | `blender -b --factory-startup -P _source/tools/export_multi_action.py -- plague_arcanist` |
| Dead Oath Hunter | `_source/tools/export_dead_oath_hunter.py` | ver el script |
| Bone Dragon, Ghidorah | `_source/tools/animate_bonedragon.py`, `animate_ghidorah.py` | ver el script |

Todos dejan las animaciones *in place* (salvo `death`), marcan `idle`/`walk`/`run` como bucle (`-loop`) y escalan el personaje a su altura de §7.4 midiendo el frame 1 de su `idle`.

## Animaciones de Dead Oath Hunter (jefe 2)

Identificadas a partir de capturas de cada acción del `.blend` (la acción larga "Todo", con todas pegadas, se descarta). Todas quedan *in place* salvo `death`.

| Clip | Frames | Qué hace | Uso sugerido |
|---|---|---|---|
| `idle` / `idle_guard` | 41 / 56 | Guardia con espada baja / en alto | Reposo (fase 1 / fase 2) |
| `walk`, `walk_forward`, `strafe`, `step` | ~40 | Pasos y desplazamiento lateral | Acercarse / rodear al jugador |
| `attack_slash` | 57 | Tajo corto | Ataque cercano rápido |
| `attack_thrust` | 69 | Estocada horizontal | Ataque a media distancia |
| `attack_overhead` | 90 | Tajo descendente amplio | Ataque pesado con aviso largo |
| `attack_combo` / `attack_combo_thrust` | 96 / 83 | Combos de varios golpes | Fase 2 |
| `attack_charge` | 96 | Ataque en carrera | Cerrar distancia |
| `attack_leap` | 107 | Salto grande con golpe | Fase 2, a distancia (el código mueve al jefe) |
| `dodge`, `dash` | 111 / 23 | Esquiva / impulso agachado | Opcional |
| `hurt` | 49 | Se dobla al recibir golpe | Reacción |
| `taunt` | 86 | Se inclina y se recupera | Transición a fase 2 |
| `death` | 118 | Cae al suelo | Muerte |

## Prioridad de trabajo

1. ~~Animaciones de Bone Dragon y Ghidorah~~ (hecho, 2026-10-13).
2. ~~Kaelen, esbirros y élite~~ (hecho, 2026-10-13). Pendiente: probar todos los `.glb` en `scale_reference` de Godot.

## Revisar un `.glb` en Blender

Al importar un `.glb`, Blender dibuja cada hueso con una esfera (objeto `Icosphere`). En modelos con muchos huesos (Ghidorah tiene 118) las esferas se amontonan y tapan la malla: parece una "papa" con contorno naranja (es el *Armature* seleccionado). No es un error del modelo y Godot no dibuja los huesos. Para verlo: seleccionar el *Armature* → *Object Data* → *Viewport Display* → desmarcar **Shapes** (o ocultarlo con `H`), y `Home` para encuadrar. Alternativa: abrir los `.blend` de trabajo (`bonedragon_animated.blend`, `ghidorah_animated.blend`), que no tienen ese problema.

## Pendiente de medir al importar

Factor de escala y altura en `scale_reference` para cada modelo (se completa al exportar el `.glb`).
