# Estado de assets de personajes

Revisión de los archivos fuente en `_source/models` (2026-10-12): esqueleto, malla enlazada (skin) y animaciones que trae cada modelo.
Kaelen y Elysia usan modelos existentes (se descartó modelarlos por tiempo).

Estados: `listo` / `falta rig` / `falta animación` / `reemplazado`.

## Resumen

| Rol | Fuente | Esqueleto | Animaciones incluidas | Estado | Trabajo pendiente |
|---|---|---|---|---|---|
| Kaelen | `low-poly-woman-knight` → Mixamo (`_source/mixamo/kaelen/`) | Sí, Mixamo | 18 clips: `idle`, `walk`, `walk_back`, `strafe_left`, `strafe_right`, `run`, `roll`, `attack_1..3`, `hurt`, `death` + extras (`roll_to_run`, `jump_attack`, `block`, `turn_180`, `draw_sword`, `jump`) | listo | `assets/characters/kaelen/kaelen.glb` (1.70 m). `roll` dura 2.4 s: reproducir más rápido (`speed_scale`) para llegar a 0.6 s, o usar `roll_to_run` (1.4 s). `attack_2` es un combo largo (3.3 s). Sin arma: el mandoble se engancha en Godot a `mixamorig:RightHand`. |
| Elysia | `ancient-elf-lady-psx/source/ancient lady elf psx.glb` (744 tris) | No (no lo necesita) | — | listo | Sin rig ni animaciones (decisión 2026-10-12): Mixamo deforma su vestido de una pieza y el pelo largo. Modelo estático en pose de reposo; en Godot un `Tween` de respiración (sube/baja ~2 cm en bucle) y giro hacia Kaelen; el abrazo se resuelve con fundido de cámara. `assets/characters/elysia/elysia.glb` (1.60 m, pies en z=0), generado con `_source/tools/export_elysia.py` (fuerza materiales opacos: el vestido salía semitransparente). |
| Esbirros 3 | `TheWrapper V2/MonsterPSX.fbx` | Sí, propio (`MonsterPSX_Rig`) | `idle`, `walk`, `run`, `attack`, `hurt`, `scream` | listo | `assets/minions/thewrapper/thewrapper.glb` (2.00 m). Se borraron las mallas `WGT_*` (formas de control del rig). No tiene `death`: tween o caída en Godot. |
| Esbirros 2 | `Plague Arcanist/Plague Arcanist/Plague Arcanist.fbx` | Sí, Mixamo | `idle`, `idle_alt`, `walk`, `strafe`, `attack` (zarpazo), `attack_cast` (hechizo al frente), `attack_leap`, `taunt`, `knockdown`, `hurt`, `death` | listo | `assets/minions/plague_arcanist/plague_arcanist.glb` (1.80 m). `hurt` (frames 1–15) y `death` (frames 1–42) son recortes de `knockdown`: el pack no trae muerte propia. |
| Élite 3 (opcional) | `aura_battler_dunbine_-_vierres/scene.gltf` (1148 tris) | No (no lo necesita) | — | listo | Mecha rígido: flotar, embestida y giro con tweens en Godot. |
| Esbirros 1 | `Skeleton` → Mixamo (`_source/mixamo/skeleton/`) | Sí, Mixamo | `idle`, `walk`, `attack`, `hurt`, `death` | listo | `assets/minions/skeleton/skeleton.glb` (1.75 m). |
| Élite 1 | `knight__ps1_psx` → Mixamo (`_source/mixamo/knight/`) | Sí, Mixamo | `idle`, `walk`, `attack`, `attack_2`, `combo`, `hurt`, `death` | listo | `assets/minions/knight/knight.glb` (2.10 m). `walk` es `Sword And Shield Run` (no hay caminar): reproducirlo más lento. Espada: `assets/minions/knight/knight_sword.glb` (1.10 m, ver *Armas*) → engancharla en Godot a `mixamorig:RightHand`. |
| Jefe 1 | `bonedragon/bone dragon.fbx` | Sí, ~70 huesos (los pesos de los huesos de control IK se pasaron al hueso FK más cercano) | `idle` (bucle), `roar`, `bite`, `tail_sweep`, `stomp`, `death` | listo | `assets/bosses/bonedragon/bonedragon.glb`, generado con `_source/tools/animate_bonedragon.py` (poses clave por script; editable en `_source/models/bonedragon/bonedragon_animated.blend`). Mide ~7.7 m de largo: escala 1. `bite` y `stomp` mueven el hueso `root`; `death` termina tumbado de costado. |
| Jefe 2 | `blackhorn/Blackhorn of the Shattered Peaks.fbx` (reemplaza a Dead Oath Hunter, 2026-10-14) | Sí, Mixamo | 8 propios: `idle`, `taunt`, `roar`, `walk`, `run`, `charge`, `attack_pounce`, `attack_slam`; + `hurt` y `death` de Mixamo | listo | `assets/bosses/blackhorn/blackhorn.glb` a **3.20 m** con los pies en el suelo (`export_multi_action.py -- blackhorn`). `hurt`/`death` descargados de Mixamo en `_source/mixamo/blackhorn/anims/`. |
| Reserva (esbirro) | `straw_reaper/THE STRAW REAPER new.fbx` | Sí, Mixamo | 9 clips Mixamo sin nombre (17–366 frames) + `Scarecrow anim` (701 frames, todas pegadas) | falta animación | Solo si un esbirro falla o se ve peor. Identificar y nombrar clips como se hizo con el Hunter. Hoz incluida. Uso comercial permitido (crédito opcional a imaginais). |
| Jefe 3 | `mecha-king-ghidorah/source/Mecha King Ghidorah.fbx` (26k → 9.1k tris) | Sí, estilo MMD (nombres en japonés; 3 cuellos, 2 colas, alas) | `idle` (bucle), `roar`, `bite`, `tail_sweep`, `beam`, `death` | listo (corregido en la Tarea 13) | `assets/bosses/ghidorah/ghidorah.glb`, generado con `_source/tools/animate_ghidorah.py` (reduce la malla y crea las poses; editable en `_source/models/mecha-king-ghidorah/ghidorah_animated.blend`). Mide 4.15 m de alto y 7.1 m de largo con las colas: **escalar ×2.4 en Godot** (10.2 m de alto, 17 m de largo con las colas extendidas, §7.4 pide ~10 × 14 × 14). Colas subidas 40° en todos los clips (colgaban 2.5 m bajo el suelo). `death` cae de costado. En `bite` la cabeza central baja a 1.47 m (hueso, ya con ×2.4; la mandíbula a 1.1 m y el punto más bajo de la malla a 0.4 m) y las laterales a 2.2 m; el rayo de `beam` es un efecto en Godot (frames 27–65). |
| Reserva (jefe 3) | `psx_insectoid_demon/scene.gltf` (622 tris) | No | — | falta rig | Solo si Ghidorah falla. No humanoide: rig manual en Blender. |
| Reserva | `DoriOri.fbx` | Sí (`root`) | Solo `Pose` | falta animación | Sin uso previsto. |

Procedimiento Mixamo paso a paso: [`guia-mixamo.md`](guia-mixamo.md).

## Cómo se generan los `.glb`

| Personajes | Script | Comando |
|---|---|---|
| Kaelen, Skeleton, Knight | `_source/tools/build_characters.py` (tabla clip ← animación de Mixamo) | `blender -b --factory-startup -P _source/tools/build_characters.py -- kaelen` |
| Plague Arcanist, TheWrapper, Blackhorn | `_source/tools/export_multi_action.py` (varias acciones en un FBX; admite clips de otros FBX en `extra_clips`) | `blender -b --factory-startup -P _source/tools/export_multi_action.py -- plague_arcanist` |
| Bone Dragon, Ghidorah | `_source/tools/animate_bonedragon.py`, `animate_ghidorah.py` | ver el script |

Todos dejan las animaciones *in place* (salvo `death`), marcan `idle`/`walk`/`run` como bucle (`-loop`), escalan el personaje a su altura de §7.4 midiendo el frame 1 de su `idle` y apoyan los pies en z = 0 (`normalize_height` en `combine_mixamo.py`).

`dragon_anim.py` escribe rotaciones y desplazamientos en ejes del **mundo**: el armature de Ghidorah viene del FBX girado 90° y escalado ×0.01, y antes eso convertía los giros horizontales en balanceos laterales.

## Animaciones de Blackhorn (jefe 2)

Identificadas con capturas de cada acción del FBX (la acción de 860 frames, con todas pegadas, se descarta). Todas *in place* salvo `death`.

| Clip | Frames | Qué hace | Uso sugerido |
|---|---|---|---|
| `idle` | 27 | Agazapado, respirando | Reposo (bucle) |
| `taunt` | 163 | Se yergue y flexiona los brazos | Entrada / pausa entre ataques |
| `roar` | 86 | Abre los brazos y echa la cabeza atrás | Transición a fase 2 |
| `walk` / `run` | 44 / 44 | Caminar / correr | Acercarse |
| `charge` | 27 | Carrera rápida en cuatro patas | Embestida (fase 2; el código lo mueve) |
| `attack_pounce` | 106 | Se lanza y da un zarpazo hacia abajo | Ataque a media distancia |
| `attack_slam` | 81 | Salta y golpea el suelo | Ataque de área cercano |
| `hurt` | 32 | Se encoge al recibir el golpe (Mixamo) | Reacción |
| `death` | 110 | Se desploma (Mixamo) | Muerte |

## Armas

| Arma | Archivo | Medida | Notas |
|---|---|---|---|
| Espada del Knight | `assets/minions/knight/knight_sword.glb` | 1.10 m de largo | Generada con `_source/tools/export_knight_sword.py` desde `sword.fbx` (venía a ~140 unidades y en diagonal). Hoja a lo largo de +Y en Godot (punta arriba); origen en el centro de la empuñadura (pomo a −0.14 m, guarda a ~+0.14 m). |
| Mandoble de Kaelen | `assets/weapons/greatsword/greatsword.glb` (+ `greatsword_bakedtexture.png`) | 1.00 m de largo (0.37 m de ancho) | Copia de `demonic weapons pack/greatsword/demonicgreatswordgodot.glb` (textura incrustada). Más corto de lo previsto (1.4–1.6 m): escalarlo ×1.4–1.5 en el `BoneAttachment3D`. Origen en el centro del arma, no en la empuñadura. Hoja a lo largo de +Y. |

Los `BoneAttachment3D` (a `mixamorig:RightHand`) los monta el equipo en Godot.

## Estética PSX (Godot-PSX-Starter-kit)

- Original (Godot 3.3, MIT): `_source/godot-psx-starter-kit/` (sin `project.godot`; solo referencia).
- Portado a Godot 4: `shaders/psx/` con `psx_lit`, `psx_unlit` y variantes `_alpha_scissor`, `_transparent`, `_metal`; `shaders/psx/postprocess/` con `pp_band_dither` (+ `psxdither.png`), `vhs`, `vhspause`, `ntsc`, `ntscbasic`, `tv`, `grain`, `simplegrain`, `glitch`, `simpleglitch`, `lcd_post_process`, `post_process_blur`, `lensdistortion`, `jpegcompression`, `bandw`.
- Cambios del port: `hint_albedo`/`hint_color` → `source_color` (texturas con `filter_nearest`), `SCREEN_TEXTURE` → `hint_screen_texture`, `ALPHA_SCISSOR` → `ALPHA_SCISSOR_THRESHOLD`, sin `const PI` (ya existe en Godot 4), y se quitó `POSITION /= abs(POSITION.w)` (en Godot 4 rompe la profundidad: se pierde la deformación afín de texturas y se mantiene el temblor de vértices). Los 23 compilan en Godot 4.7.
- Material base: `assets/materials/psx_base.tres` (`ShaderMaterial` con `psx_lit`; duplicarlo y poner `albedoTex` por modelo). Entorno: `assets/environment/base_env.tres` (niebla gris-azulada 6–30 m, cielo en gradiente, ambiente tenue).
- Escena de prueba: `scenes/levels/psx_test.tscn` — Kaelen y un esqueleto en un `SubViewport` de 320×240 mostrado en un `TextureRect` (filtro nearest, 4:3 con barras) con `pp_band_dither` (`col_depth` 15). `psx_test.gd` (`apply_psx`) pone a cada superficie un duplicado de `psx_base` con la textura de su material original. `pp_band_dither` se cambió a `UV` en vez de `SCREEN_UV` para que funcione con barras laterales.
- Licencia MIT (`shaders/psx/LICENSE-psx-starter-kit.txt`): va en los créditos.

Licencias y créditos: [`creditos.md`](creditos.md).

## Prioridad de trabajo

1. ~~Animaciones de Bone Dragon y Ghidorah~~ (hecho, 2026-10-13).
2. ~~Kaelen, esbirros y élite~~ (hecho, 2026-10-13). Pendiente: probar todos los `.glb` en `scale_reference` de Godot.

## Revisar un `.glb` en Blender

Al importar un `.glb`, Blender dibuja cada hueso con una esfera (objeto `Icosphere`). En modelos con muchos huesos (Ghidorah tiene 118) las esferas se amontonan y tapan la malla: parece una "papa" con contorno naranja (es el *Armature* seleccionado). No es un error del modelo y Godot no dibuja los huesos. Para verlo: seleccionar el *Armature* → *Object Data* → *Viewport Display* → desmarcar **Shapes** (o ocultarlo con `H`), y `Home` para encuadrar. Alternativa: abrir los `.blend` de trabajo (`bonedragon_animated.blend`, `ghidorah_animated.blend`), que no tienen ese problema.

## Verificación en Godot (Tarea 11, 2026-10-14)

Medido con el esqueleto y la malla en `scenes/levels/scale_reference.tscn` (skinning calculado en CPU; el suelo de la escena se amplió a 140 m para que quepa Ghidorah). `scale_reference.gd` ahora lista también las animaciones de los jefes.

**Blackhorn** (escala 1): 3.20 m exactos con los pies en y = 0.000 en `idle`. 10 clips reproducen sin errores; picos de altura 3.81 m (`run`/`walk`, brazos arriba). Pies entre −0.06 y +0.15 m en todos los clips. Diferencias con lo documentado:
- `idle` y `charge` duran lo mismo (0.90 s, bucle) y `walk` y `run` también (1.47 s, bucle): parecen el mismo clip duplicado. Comprobar si hay que usar velocidades distintas desde Godot.
- `death` termina con el cuerpo tumbado **0.83 m por encima del suelo** (el hueso de la cadera no baja en el clip de Mixamo): hay que bajar el modelo ~0.8 m al terminar la muerte (tween en `Boss`) o recortar el clip.
- `hurt` levanta los pies ~0.12 m.

**Ghidorah**: lo documentado ("~3.5 m, escalar ×3") no es cierto. El `.glb` mide **4.15 m** de los pies a la punta del ala/cabeza más alta y 5.8 m de largo (cuerpo + colas), 3.8 m de envergadura. Los huesos llegan a 3.3 m (cuernos), por eso salía 3.5. Con ×3: 12.5 m de alto, 17.4 m de largo, 11.3 m de envergadura (§7.4: 10 × 14 × 14). Con **×2.4** sale 10.0 m de alto y 13.9 m de largo (envergadura 9.1 m): es el factor que mejor cuadra con §7.4. Los pies sí quedan en y = 0.01.
- **Defecto: las dos colas cuelgan bajo el suelo.** En reposo la punta de cada cola está 2.0 m (hueso) / 2.5 m (malla) por debajo de los pies; con ×3 son 7.4 m bajo el suelo (6 m con ×2.4). Atraviesan el piso en todos los clips.
- **Arreglado en la Tarea 13** (ver *Corrección de Ghidorah* más abajo).
- Sin deformaciones evidentes de la malla en ningún clip (capturas de 3 fotogramas por clip revisadas).

Tabla de animaciones (`AnimationPlayer.get_animation_list()`, duraciones reales):

| Jefe | Clip | Duración | Bucle |
|---|---|---|---|
| Blackhorn | `idle` | 0.90 s | sí |
| Blackhorn | `taunt` | 5.43 s | no |
| Blackhorn | `roar` | 2.87 s | no |
| Blackhorn | `walk` | 1.47 s | sí |
| Blackhorn | `run` | 1.47 s | sí |
| Blackhorn | `charge` | 0.90 s | sí |
| Blackhorn | `attack_pounce` | 3.53 s | no |
| Blackhorn | `attack_slam` | 2.70 s | no |
| Blackhorn | `hurt` | 1.07 s | no |
| Blackhorn | `death` | 3.67 s | no |
| Ghidorah | `idle` | 2.54 s | sí |
| Ghidorah | `roar` | 2.92 s | no |
| Ghidorah | `bite` | 2.67 s | no |
| Ghidorah | `tail_sweep` | 2.67 s | no |
| Ghidorah | `beam` | 3.33 s | no |
| Ghidorah | `death` | 4.17 s | no |

Otros modelos en `scale_reference` (esqueleto): Bone Dragon sale 4.92 m de alto y 8.6 m de largo con el suelo en −1.08 m (huesos de las colas/alas bajo el suelo); PlagueArcanist 1.89 m (doc. 1.80).

## Pendiente de medir al importar

Factor de escala y altura en `scale_reference` para cada modelo (se completa al exportar el `.glb`).

## Corrección de Ghidorah y jefes 2 y 3 (Tarea 13, 2026-10-14)

Medido en Godot con el esqueleto y la malla (skinning en CPU, 25 muestras por clip), escala ×2.4, antes y después de regenerar `ghidorah.glb`:

| Clip | Hueso más bajo (antes → después) | Malla más baja (antes → después) | Cambio |
|---|---|---|---|
| `idle` | −4.89 → 0.00 m | −5.95 → −0.01 m | colas a la altura de los pies |
| `roar` | −4.89 → 0.00 | −5.95 → −0.01 | alas abiertas hacia arriba |
| `bite` | −5.08 → 0.00 | −6.14 → −0.01 | torso inclinado 45° y cuellos laterales 60° |
| `tail_sweep` | −4.89 → 0.00 | −5.95 → −0.01 | |
| `beam` | −4.88 → 0.00 | −5.95 → −0.01 | |
| `death` | −10.66 → 0.00 | −12.27 → −0.17 (durante la caída; al final 0.02) | cae de costado: `ROOT` con roll 80° (+0.6 m de altura y 0.5 m en X), ala del lado que cae plegada hacia arriba |

- Cambios en `_source/tools/animate_ghidorah.py`: base de cada cola +40° (antes de `bake()`), `wings(angle)` ahora abre las alas hacia arriba (con el signo anterior colgaban hasta 0.6 m bajo el suelo al abrirlas), `bite` con `UPPER` 45° y cuellos laterales 60°, `CENTER` sin bajar en `bite`/`tail_sweep` (los pies se hundían), `death` de costado. Constantes al inicio del script. Nombres de clip y marcas de bucle sin cambios (`idle-loop` → `idle` con bucle).
- Altura de la cabeza en `bite` (escala ×2.4): hueso de la cabeza central 1.47 m, mandíbula 1.12 m, vértice más bajo de esa cabeza 0.37 m; cabezas laterales 2.2 m (hueso) / 1.2 m (malla). Las tres caen delante del cuerpo (z = 4.3 a 5.3 m). Con la espada (alcance ~1.5 m) se golpean sin saltar.
- Longitud: con las colas horizontales mide 17.2 m (z de −12.8 a +4.4), no 14: las colas miden ~7 m a escala 1. Pegado a la pared norte de `arena_3` (BossStart z = −12, arena de ±20) la cola atraviesa el muro (solo visual).
- Escalas en Godot: Blackhorn 1.0 (3.20 m), Ghidorah 2.4 (en `boss_ghidorah.tscn` y `scale_reference.tscn`).
- `BoneAttachment3D` sobre estos esqueletos (escala 0.01 del armature) deforma las `Area3D` hijas, por eso las zonas que siguen huesos (garras de Blackhorn, cabezas, torso y mordida de Ghidorah) son `Area3D` sueltas movidas por un `RemoteTransform3D` (solo posición) colgado del `BoneAttachment3D`.

### Jefes 2 y 3 en Godot (`boss_blackhorn.tscn`, `boss_ghidorah.tscn`)

| Jefe | Ataque (id, clip) | Rango | Daño | Aviso | Activo | Recuperación | Fase | Zona |
|---|---|---|---|---|---|---|---|---|
| Blackhorn (500 PV) | `slam`, `attack_slam` | 0–4 m | 20 | 1.35 s | 0.45 s | 0.9 s | 1 | esfera r 3 alrededor |
| | `pounce`, `attack_pounce` | 2–7 m | 18 | 1.9 s | 0.5 s | 1.1 s | 1 | caja 2×2×4 al frente + garras (esferas r 0.6 en las manos); avanza 3 m |
| | `charge`, `charge` | 8–16 m | 25 | 1.0 s | 0.9 s | 1.4 s | solo 2 | caja 1.5×2.5×3 al frente; avanza 12 m (aviso: carril 1.5 × 15 m) |
| Ghidorah (600 PV) | `bite`, `bite` | 0–6 m | 12 | 1.1 s | 0.6 s | 1.0 s | 1 | esfera r 1.5 en la mandíbula central |
| | `tail_sweep`, `tail_sweep` | 0–8 m | 10 | 1.2 s | 0.8 s | 1.2 s | 1 | caja 2.5×3×6 detrás (a 3.5–9.5 m) y el cuerpo gira 360° (aviso: disco r 9.6) |
| | `beam`, `beam` | 8–20 m | 14 | 1.1 s | 1.5 s | 1.3 s | 1 | caja 1.5×1.5×20 al frente (aviso: línea; efecto visual amarillo mientras está activo) |

Daño pensado para la vida máxima de Kaelen en cada arena (100/70/40 PV): ~25–30 % por golpe. Los clips `idle`/`charge` de Blackhorn duran lo mismo (0.90 s) y `walk`/`run` también (1.47 s): parecen duplicados; el clip `charge` se usa también como aviso de la embestida (corre en el sitio durante 1 s).

`scripts/ai/attack_driver.gd` (nodo `AttackDriver`, hijo del jefe) cubre lo que `Boss` aún no hace, sin tocar `boss.gd`: avance durante `ACTIVE` (embestida, salto), aproximación para ataques de largo alcance (`Boss` solo ataca a menos de `engage_range`), `walk`/`run` al avanzar (`Boss.walk_animation` no se usa), garras con el zarpazo, cabezas de Ghidorah golpeables solo mientras dura `bite` (+0.25 s), efecto del rayo y apoyo del cuerpo en el suelo al morir (la `death` de Blackhorn terminaba 0.83 m en el aire: el modelo baja ~1 m en la animación).
