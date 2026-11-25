# AGENTS.md: Descending to my Heaven

Guía única del proyecto para quien se incorpora al equipo: qué es el juego, en qué estado está, cómo ejecutarlo y probarlo, cómo está organizado el código y qué falta. Sustituye a la antigua carpeta `docs/`.

- **Fecha de esta versión:** 2026-10-21
- **Juego:** boss rush 3D en tercera persona, estilo soulslike y PSX. Kaelen sube un templo de tres pisos sobre una isla flotante y derrota a tres jefes para llegar a Elysia.
- **Motor:** Godot 4.7.2 estable, GDScript con tipos estáticos, renderizador `gl_compatibility` (Compatibility). Resolución interna 640×360, ventana 1280×720.
- **Rama de trabajo:** `wt/combat-dynamism` (worktree `../Descending-wt-combat`), la única que se sube. **No se fusiona con `main` ni se hace push a `main`** (sección 18.1). `main` (6034e77) contiene el trabajo anterior de `feat/aza`, `wt/export` y la documentación.
- **Equipo:** Paula Sofia Gonzalez Zambrano, David Alejandro Aza Jojoa y Stehven Alexander Obando Cordoba.
- **Repositorio privado.** Varios assets no pueden redistribuirse (ver sección 12).

---

## 1. Estado actual

### 1.1 Plan de trabajo (7 días, día 5 en adelante)

| Tarea | Estado | Pendiente |
|---|---|---|
| T1–T14: contrato, combate, Kaelen, esbirros, Orquestador, jefes 1–3, menús, arenas, exterior | Hechas | Revisión a mano de algunas animaciones |
| T15: flujo completo, final y créditos | Hecha | Partida completa a mano (menú → exterior → 3 jefes → final → créditos) con el checklist de la sección 14 |
| T16: esbirros por nivel y élites | Hecha | Revisar en juego animaciones de ataque y muerte, espada del Knight, hoz del Straw Reaper y caída de TheWrapper |
| T17: audio completo | Hecha | Licencias "por confirmar" (sección 12) |
| T18: pulido y playtest | Casi hecha | **Playtest con 2 personas externas** (plantilla en la sección 14); decoración de arenas (pendiente); revisar en juego el combate nuevo (sección 17); commit por persona |
| T19: congelación, exportación Windows, tag `v1.0` | En curso | Exportación Windows lista (sección 2.6). Ya hay una release candidata `v1.0.0-rc1` en GitHub con el `.exe` (ver sección 2.6). Falta: congelación, probar el `.exe` en otra PC, revisar créditos, `v1.0` (Web, si funciona) |

### 1.1b Ajustes del exterior y los menús (2026-11-05 y 2026-11-06, sin commit, pendiente de prueba del equipo)

- **Menús:** `scripts/ui/menu_nav.gd` (`MenuNav`): el ratón mueve el foco (un solo resaltado; el tema ya no dibuja "hover" aparte en `Button` y `CellButton`) y las flechas siguen vecinos explícitos, sin dar la vuelta. Las opciones recalculan la cadena en cada pestaña (`_wire_focus`); con las opciones abiertas, los botones de la pausa no reciben foco. Comprobado en `ui_flow`.
- **Pantalla:** los modos se llaman Ventana, Pantalla completa en ventana (`MODE_FULLSCREEN`) y Pantalla completa (`MODE_EXCLUSIVE`); Opciones muestra "Aplicado: modo (tamaño)". En una prueba con ventana real el cambio de modo ya funcionaba.
- **Isla:** aplanada en el generador (`EXTERIOR.flatten`: altura = ref + k·(h − ref), ref 2,0, k 0,5; malla y colisión) y ampliada con tres piezas de tierra (`EXTERIOR.extensions`: una detrás del inicio y una a cada lado, con colisión, para que haya bosque detrás de Kaelen). Los tres agujeros (ojos y nariz) son estanques con fondo de barro (`Island/Ground/Bed1..3`), así que ninguno queda sin fondo; el nivel del agua es la mediana del borde. Los estanques de los ojos se ajustaron al tamaño del agujero (≥ 9 m del sendero); el de la nariz queda junto al camino, por diseño.
- **Bosque:** 104 árboles sobre la isla y las ampliaciones, puestos con rayos (`EXTERIOR.island_trees`: suelo a 1,5/3/5/8 m en 8 direcciones, escalón ≤ 1 m, base = suelo más bajo bajo el tronco − 0,35 m, zona libre detrás del inicio para la cámara) con la misma niebla que el suelo (25–115 m) para que de lejos no parezcan despegados; y el bosque lejano en niebla (tres anillos `Forest/Ring1..3`, bases bajo la capa de bruma de y = −4) alrededor de toda la isla. Pilares del sendero: se omiten los que caen sobre agua, vacío, curvas interiores o a otra altura. Cielo de atardecer en `EXTERIOR.sky`.
- **Cambios temporales** (para quitarlos basta borrar el nodo o poner la constante a `false`): `TempClouds` en `exterior_gameplay.tscn` (nubes en el cielo y alrededor de la isla) y `IntroDirector.SWORD_PICKUP` (Kaelen recoge la espada con `draw_sword` mientras habla; el plano cercano se coloca del lado opuesto a la espada, con luz suave y avance lento). La textura de tierra temporal se probó y se retiró (parecía superpuesta).
- **Estanques (2026-11-24):** el agua ya no es una elipse: se construye con las celdas de 1 m del agujero (vacío o suelo claramente bajo el agua, conectado al centro, más 3 celdas de margen que quedan bajo el borde) y tiene fondo con colisión (`Island/Ground/Bed1..3`); el shader `water_psx` ya no recorta nada. Antes quedaban huecos de cielo junto al agua.
- **Final (2026-11-24):** Elysia ahora tiene rig y tres clips (`idle` en bucle, `appear` al mostrarse, `hug` en el abrazo; `_source/tools/rig_elysia.py`, original sin rig en `_source/models/elysia_static.glb`; pesos calculados por geometría, sin auto-pesos ni Mixamo; ya no está en pose de brazos abiertos). Kaelen cierra los brazos alrededor de ella con `HugArms` (`SkeletonModifier3D`, solver de dos huesos), suelta el mandoble y Elysia se acerca hasta que su cuerpo queda a `HUG_BODY_GAP` (0,34 m; el origen del modelo de Elysia está ~1 m delante de su cuerpo, por eso se mide al centro de su malla). Tras la última línea se quedan abrazados `HOLD_TIME` (8 s) mientras la cámara se aleja y la isla cae, y solo entonces el fundido. `EndingCam2` pasó a un perfil lateral de la pareja (desde el eje Kaelen tapaba a Elysia). Pendiente de revisión del equipo en pantalla: los brazos de `hug` de Elysia son aproximados (se comprobó con capturas, no con un abrazo "perfecto").
- **Final, segunda pasada (2026-11-24):** cada línea tiene su propia cámara (`SHOT_KINDS`, `shot_transform`: de frente, sobre el hombro, contrapicado, tres cuartos, perfil o general) que enfoca a quien habla y deriva despacio; se quitó el balanceo y el rebote de todo el cuerpo de Elysia. Elysia habla con el clip `talk`, camina despacio hacia Kaelen (`walk`, `STEP_DOWN_TIME` 6 s, sin salto) y extiende los brazos (`reach`) antes del abrazo (`hug`). Clips nuevos en `rig_elysia.py`. Pendiente de revisión en pantalla.
- **Final, tercera pasada (2026-11-24):** Elysia gira lentamente (`ELYSIA_LOOK_TIME` 2,6 s) alrededor de su propio cuerpo, no de su origen (que está ~1 m delante de su cuerpo y hacía una curva rara); todo giro, inclinación y paso se calcula sobre el punto del suelo bajo su cuerpo (`_set_elysia_origin`, `_body_floor`, `_feet_height`). Kaelen deja la guardia mientras hablan: `HugArms` en modo `stance` (nodo `StanceArms`: brazos caídos, espada clavada junto al pie, mirando a Elysia) que se apaga al abrazar. La entrada de la sala se tapa con una niebla negra (`EntranceFog`, un tapón negro y capas suaves) para que no se vea el jefe. Abrazo: `HUG_BODY_GAP` 0,55 m entre cuerpos, frente a frente, ella desplazada 0,12 m (`HUG_HEAD_OFFSET`) para que las cabezas se crucen por el hombro, e inclinación de solo 0,04 rad (`EMBRACE_LEAN`; con 0,14 cada una se inclinaba hacia la otra y se atravesaban). Kaelen quieta: `Player.idle_anim_scale` (0,2) frena su idle, y los brazos de la postura quedan pegados al cuerpo. Los brazos del abrazo mezclan la postura quieta y el abrazo en el espacio (`HugArms.hug_blend`, un solo modificador), y las manos van a los costados de la espalda de Elysia (`BACK_OFFSET` 0,02, `LATERAL` 0,17) para que los codos queden doblados, no estirados. Pendiente de revisión en pantalla.
- **Tutorial:** el muñeco sale siempre en el eje del sendero, 14 m al norte de `PlayerStart`.

### 1.2 Lo último que se hizo (2026-10-14 a 2026-10-21)

- **Oleada 1 de la sección 18 (2026-10-21, sin commit hasta que el equipo lo pruebe):** combo que se cierra en el 3.er golpe, rodada con recuperación (`roll_to_run`) y ataque tras rodada; aturdimiento solo a esbirros (0,6 s / 0,35 s élites); espantapájaros del Straw Reaper en el tutorial; rugido de fase 2 de 1,5 s, invulnerable y con onda; Bone Dragon más rápido y con menos tiempo muerto; arreglo del jefe que perseguía sin atacar; atajos F3/F5/F6 solo en depuración; islotes, bosque más lejano y torre de tres cuerpos en el exterior. Detalle y cifras en la sección 18.6.
- **Ronda 2 (2026-10-20, misma rama, sección 17):** auras de aviso estilo God of War (amarilla = esquivable rodando, roja = sal de la zona) y avisos de suelo con shader propio; retroceso al golpear (el 3.er golpe empuja más) y aturdimiento de 1,2 s con el ataque fuerte (centrado); hechizo del Plague con círculo mágico, orbe e impacto; los esbirros se burlan al morir Kaelen y caen al morir el jefe; cola de Ghidorah con zona segura; techo del piso 2 y rayas del piso 3 corregidos; subida entre pisos dirigida con carga en segundo plano; final precalentado y con coreografía; introducción con historia y tutorial de controles.
- **Combate más dinámico (2026-10-20, rama `wt/combat-dynamism`, sección 17):** varios ataques por esbirro con sus propios clips, caída escalonada de TheWrapper, ataque fuerte de Kaelen (`jump_attack`), caminar lateral con objetivo fijado, combos de jefes en fase 2 y una amenaza nueva por piso.

- Transición con cartel entre pisos (cortinilla iris, nombre del piso y jefe, unos 2,1 s).
- Final: corte al encuentro (fundido a negro y colocación de Kaelen antes de la primera línea), caída de la isla con viento y blips de voz normalizados.
- Frasco de curación con 10 cargas por nivel, pausa de impacto, parpadeo al recibir golpe, sacudida de cámara y brazo más largo con jefes grandes.
- Opciones completas: controles reasignables, volumen por bus, pantalla, idioma.
- Correcciones de mapa: cámara atascada en la pared del sendero, arco de la puerta del templo, baldosas del kit que desaparecían (ahora `kit_std.tres`), escaleras (cuñas de colisión `EntryRamp`/`ExitRamp`), huecos de la isla con estanques, vacío del horizonte con niebla y árboles lejanos.
- Ajustes de combate: daño de Kaelen duplicado (20/20/36), repulsión de jefes más fuerte, tácticas del jefe (sección 8).

Detalle histórico de decisiones: `git log` de `feat/aza`.

---

## 2. Cómo ejecutar y probar

### 2.1 Abrir el juego

1. Clonar el repo con Git LFS instalado (`git lfs install`). Si un `.glb`, `.png` o `.ogg` ocupa 1 KB, falta LFS: ejecutar `git lfs pull`.
2. Abrir Godot 4.7.2 → **Importar** → elegir `project.godot`.
3. Ejecutar (F5). La escena principal es `scenes/ui/main_menu.tscn`.
4. La carpeta `_source/` no aparece en Godot a propósito (tiene `.gdignore`).

En los comandos siguientes, `godot` es el ejecutable de Godot 4.7.2 (en Windows, la versión de consola `Godot_v4.7.2-stable_win64_console.exe`), ejecutado desde la raíz del repo.

### 2.2 Pruebas unitarias

```
godot --headless --path . -s res://tests/run_tests.gd
```

Pasa si termina con `N/N passed` y código de salida 0. **Número actual de pruebas: 444.** Cada prueba crea sus propios nodos y los libera al terminar.

### 2.3 Pruebas de flujo (escenas)

```
godot --headless --path . res://tests/flow/<nombre>.tscn
```

Pasa si imprime `FLOW: OK`. Los trece flujos:

| Flujo | Comprueba |
|---|---|
| `death_flow` | Muerte real con los autoloads: pantalla de muerte, reintento |
| `dialogue_flow` | Final con diálogo en la arena 3: avance solo por pulsación (con `-- shots <carpeta>` en ventana, mide el bus UI y guarda capturas) |
| `ending_cut_flow` | El final mueve a Kaelen solo con la pantalla en negro |
| `ending_finish_flow` | El final siempre avanza aunque haya un fundido en curso |
| `hit_feedback_flow` | Pausa de impacto y parpadeo |
| `transition_flow` | Cartel entre pisos: no se dispara dos veces, Kaelen bloqueada, se puede saltar |
| `ui_flow` | HUD y menú de opciones (captura de tecla cancelada al ocultarse) |
| `minion_attacks_flow` | Cada ataque de cada esbirro golpea a Kaelen en su arena con el daño exacto; muertes y cadáveres; retroceso y aturdimiento; hechizo (círculo, orbe, aura); burla al morir Kaelen; carrera del piso 3 |
| `kaelen_moves_flow` | Ataque fuerte (salto, golpe a 1,6–3,6 m, remate del combo), avance al atacar con objetivo fijado y caminar lateral |
| `boss_combo_flow` | Cada jefe encadena combos en fase 2 y nunca en fase 1; el aura de aviso sube poco a poco y se apaga |
| `floor_climb_flow` | Entrada al templo, llegada a la arena, carga en segundo plano, subida por la escalera y llegada al siguiente piso; el reintento no repite la llegada |
| `ending_staging_flow` | Coreografía del final: temblores, Elysia baja del escalón sin hundirse y nunca se solapan (≥ 0,65 m), abrazo |
| `intro_tutorial_flow` | Introducción (planos, bloqueo, se salta con pausa) y cada paso del tutorial con la tecla real y la del mando |

### 2.4 Regenerar niveles

```
godot --headless --path . -s res://scripts/tools/level_builder.gd          # todos
godot --headless --path . -s res://scripts/tools/level_builder.gd -- arena_2  # uno
```

- Genera `scenes/levels/exterior.tscn`, `arena_1.tscn`, `arena_2.tscn` y `arena_3.tscn`.
- **Regla:** esas cuatro escenas se sobrescriben. **Nunca se editan a mano ni se les añaden nodos.** Los cambios van en las tablas `LEVELS` y `EXTERIOR` de `level_builder.gd`. El generador no escribe nunca `*_gameplay.tscn` (tiene un `assert`).
- Para probar sin tocar las escenas: opción `-- out=<carpeta>/`.
- Lo que se añade a un nivel va en `arena_N_gameplay.tscn` (instancia el nivel como hijo `Level`) o en `exterior_gameplay.tscn`.

### 2.5 Simulaciones y herramientas (`scripts/tools/`)

| Herramienta | Qué hace | Cómo se ejecuta |
|---|---|---|
| `orchestrator_sim.gd` | Intensidad del Orquestador en las tres arenas (perfiles `skilled`, `average`, `weak`) | `godot --headless --path . -s res://scripts/tools/orchestrator_sim.gd` |
| `boss_pressure_sim.gd` | Repulsiones y tiempo para matar a cada jefe con Kaelen simulada (perfiles `steady` y `opportunist`) | `godot --headless --path . -s res://scripts/tools/boss_pressure_sim.gd` |
| `boss_tactics_sim.gd` | Tácticas del jefe frente a Kaelen simulada (`aggressive` y `evasive`); acepta `-- boss=Ghidorah runs=4 secs=120` | `godot --headless --path . -s res://scripts/tools/boss_tactics_sim.gd` |
| `boss_hitbox_map.gd` | Dibuja qué zonas del suelo alcanza cada ataque y mide la zona libre | `godot --headless --path . -s res://scripts/tools/boss_hitbox_map.gd` |
| `ghidorah_profile.gd` | Tiempo de cada fotograma en los ataques de Ghidorah (necesita ventana) | `godot --path . --resolution 1280x720 -s res://scripts/tools/ghidorah_profile.gd` |
| `uid_cache_check.gd` | Comprueba que la caché importada de cada modelo (`.godot/imported/`) apunta a los UID actuales de sus texturas; sale con 1 si hay modelos obsoletos e indica cómo reimportarlos. Pasarlo antes de exportar | `godot --headless --path . -s res://scripts/tools/uid_cache_check.gd` |

Scripts de Python (necesitan Python con las librerías de cada uno):

| Script | Uso |
|---|---|
| `gen_menu_bg.py` | Genera el fondo del menú (`assets/ui/menu/`). Necesita Pillow |
| `make_music_loops.py` | Genera las versiones `*_loop.ogg` de la música. Necesita numpy e imageio-ffmpeg |
| `make_ui_sounds.py` | Recorta y normaliza los sonidos de interfaz. Necesita numpy y scipy |
| `make_dialogue_blips.py` | Prepara los blips de voz del final. Recibe la carpeta del pack |

Los scripts de Blender y de exportación de modelos están en `_source/tools/` (sección 9.5).

---

### 2.6 Exportar a Windows (.exe)

Solo escritorio Windows por ahora. El preset `Windows Desktop` está en `export_presets.cfg` (x86_64, release).

- **Plantillas de exportación:** hacen falta las oficiales de Godot 4.7.2 estable en `%APPDATA%\Godot\export_templates\4.7.2.stable\` (con `version.txt`). Se descargan de la release `4.7.2-stable` de godotengine (`Godot_v4.7.2-stable_export_templates.tpz`), verificando el SHA-512 con `SHA512-SUMS.txt`. Para Windows basta con `windows_release_x86_64.exe`, `windows_debug_x86_64.exe` (y sus `_console`) más `version.txt`; el `.tpz` completo pesa 1,2 GB. También se puede instalar desde el editor: Proyecto > Exportar > Gestionar plantillas.
- **Exportar (release):**
  ```
  Godot_v4.7.2-stable_win64_console.exe --headless --path <repo> --import
  Godot_v4.7.2-stable_win64_console.exe --headless --path <repo> --export-release "Windows Desktop" <repo>/export/windows/DescendingToMyHeaven.exe
  ```
  Para una build de depuración (genera además `DescendingToMyHeaven.console.exe` con la consola de errores): `--export-debug "Windows Desktop" <repo>/export/windows-debug/DescendingToMyHeaven.exe`.
- **Resultado:** un solo `.exe` con el `.pck` incrustado (`embed_pck=true`), de unos 174 MB (166 MiB). No necesita instalación. La carpeta `export/` está en `.gitignore`: no se versiona.
- **Filtros:** se exportan todos los recursos (`export_filter="all_resources"`), salvo `tests/*`, `scripts/tools/*`, `_source/*`, `assets/audio/bgm/source/*`, `*.py` y `AGENTS.md`. `assets/credits.txt` (lo lee la pantalla de créditos) va en `include_filter`. Los scripts se empaquetan como binarios tokenizados.
- **Sin firma de código** (`codesign` desactivado): Windows SmartScreen puede avisar al ejecutarlo en otra PC ("Más información" > "Ejecutar de todas formas").
- **Icono:** el proyecto aún no define un icono propio (`config/icon` vacío), así que el `.exe` usa el de Godot. Si se añade uno, ponerlo también en `application/icon` del preset.
- **Prueba hecha:** el `.exe` arranca en el menú, las traducciones (es/en), los créditos, las 7 músicas y todas las escenas de `scenes/` cargan sin errores. Quedan avisos inofensivos de UID inválido en los `.import` de `islet_small.glb` y `straw_reaper.glb` (Godot usa la ruta de texto). Falta probarlo en una PC distinta a la de desarrollo.

#### Release en GitHub

- **Release:** `v1.0.0-rc1`, marcada como *pre-release* ("release candidate"). La v1.0 definitiva se publica tras el playtest externo y la congelación de la Tarea 19.
- **Enlace:** https://github.com/SoFzzz/Descending-to-my-Heaven/releases/tag/v1.0.0-rc1
- **Archivo:** `DescendingToMyHeaven.exe` (Windows x86_64, un solo archivo de unos 166 MB con el `.pck` incrustado). SHA-256: `F4D7FED830464D7F90B0FA4F1F0BB19692A56013BC247454F55E270FA854ABC4`. Exportado desde el commit `42d2dcb` de `main`.
- **Cómo jugar:** descargar el `.exe` de la release y ejecutarlo. SmartScreen puede avisar porque no está firmado ("Más información" > "Ejecutar de todas formas"). No requiere instalación. Los ajustes se guardan en `%APPDATA%\Godot\app_userdata\Descending to my Heaven\`.
- **Cómo publicar una nueva:** exportar como indica esta sección; en GitHub, pestaña *Releases* > *Draft a new release*, con una etiqueta nueva sobre `main`, y adjuntar el `.exe`. El repositorio es privado y la release también: no hacer pública la release, porque varios assets no se pueden redistribuir.

---

## 3. Estructura del repositorio

```
Descending-to-my-Heaven/
  AGENTS.md          este archivo
  project.godot      configuración: autoloads, mapa de entradas, capas, idioma
  default_bus_layout.tres   buses de audio: Master, Music, SFX, UI
  assets/            lo que usa el juego (GLB, texturas, audio, fuentes), con LFS
  _source/           material original (modelos, packs de audio, scripts de Blender); Godot no lo importa
  addons/            storm_wind y magic_circles (copiados, sin plugin activo)
  localization/      translations.csv (claves tr() en es/en) y los .translation generados
  resources/         recursos de Godot: ataques de jefes (attacks/*.tres), variantes de audio (audio/)
  scenes/            escenas (ver abajo)
  scripts/           código GDScript (ver abajo)
  shaders/           shaders PSX (psx/) y postproceso (psx/postprocess/)
  tests/             pruebas unitarias (test_*.gd) y flujos (flow/)
```

### 3.1 `scripts/`

| Carpeta | Contenido |
|---|---|
| `ai/` | Jefes (`boss`, `boss_brain`, `boss_attack`, `boss_repel`, `boss_tactics`), esbirros (`minion`, `minion_brain`), Orquestador (`orchestrator`, `orchestrator_model`, `squad_tactics`), fichas de ataque (`attack_tokens`), memoria de combate (`combat_memory`), overlay F3 (`debug_overlay`) |
| `audio/` | `audio_manager.gd`: música, sonidos 3D, sonidos de UI, ducking |
| `combat/` | `health`, `stamina`, `hitbox`, `hurtbox`, `hit_flash` (parpadeo), `hit_stop` (pausa de impacto) |
| `environment/` | `forest_ring.gd`: anillos de árboles lejanos del exterior |
| `game/` | `game_state`, `events`, `user_settings`, `arena_config`, `level_gameplay`, `arena_gameplay`, `arena_mood`, `ending_director`, `ending_room` |
| `player/` | `player_controller` (Kaelen), `camera_rig`, `lock_on` |
| `tools/` | Generador de niveles, simulaciones y scripts de Python (sección 2.5) |
| `ui/` | Menús (`main_menu`, `pause_menu`, `options_menu`, `death_screen`), `hud`, `dialogue_box`, `typewriter`, `transition`, `credits`, `island_silhouette`, `menu_stars` |
| `vfx/` | `impact_fx` (chispas y polvo), `beam_vfx` y `ghidorah_beam_aim` (rayo), `repel_wave` (onda de la repulsión), `shader_warmup` (precalienta shaders) |

### 3.2 `scenes/`

| Carpeta | Escenas |
|---|---|
| `player/` | `kaelen.tscn` |
| `enemies/` | `minion_base` y variantes por arena: `minion_skeleton`, `minion_knight_elite`, `minion_plague`, `minion_plague_elite`, `minion_wrapper`, `minion_reaper_elite`; `training_dummy` |
| `bosses/` | `boss_base` (herencia) y `boss_bonedragon`, `boss_blackhorn`, `boss_ghidorah` |
| `levels/` | Generadas: `exterior`, `arena_1`, `arena_2`, `arena_3`. Gameplay: `exterior_gameplay`, `arena_1_gameplay`, `arena_2_gameplay`, `arena_3_gameplay`. Pruebas y referencia: `test_arena`, `scale_reference`, `psx_test` |
| `props/` | `ending_room.tscn`: sala rota del final |
| `ui/` | `main_menu`, `options_menu`, `pause_menu`, `hud`, `death_screen`, `transition`, `dialogue_box`, `credits`, `debug_overlay` |

### 3.3 Autoloads (`project.godot`, sección `[autoload]`)

| Autoload | Función |
|---|---|
| `Events` | Señales globales: `player_damaged`, `player_died`, `enemy_died`, `boss_phase_changed`, `boss_defeated`, `arena_entered`, `arena_cleared`, `hit_landed` |
| `GameState` | Nivel actual (0 a 2), vida máxima por nivel (`MAX_HP_BY_LEVEL` = 100, 70, 40), avance de nivel, reinicio de arena tras morir, menú principal, bandera `cutscene_active` |
| `AttackTokens` | Máximo 2 esbirros atacando a la vez (`request`, `release`, `reset`, `holders_count`) |
| `Orchestrator` | Oleadas de esbirros, puntos de aparición, intensidad y fases; `begin_arena`, `end_arena`, `get_debug_info` |
| `AudioManager` | `play_music` (con fundido), `play_sfx_3d`, `play_ui`, `duck_music`; pool de reproductores 3D |
| `UserSettings` | Opciones del jugador, guardadas en `user://settings.cfg` (`ConfigFile`) y aplicadas al arrancar |

---

## 4. Flujo del juego

```
Menú principal → Exterior (isla, sendero, templo) → puerta del templo
  → [cartel] Piso 1: arena 1 (Bone Dragon) → reja de salida + escalera
  → [cartel] Piso 2: arena 2 (Blackhorn)   → reja de salida + escalera
  → [cartel] Piso 3: arena 3 (Ghidorah)    → la puerta norte se abre al morir el jefe
      → pasillo (~20 m) → sala de Elysia → final (diálogo y abrazo)
      → caída de la isla → créditos → menú principal
```

| Nivel | Vida máxima | Jefe | Esbirros | Música |
|---|---|---|---|---|
| Exterior | — | — | — | Ambiente del bosque (`Forest Night`) |
| Arena 1 (Catacumba) | 100 | Bone Dragon | Skeleton + élite Knight | `ancient creature battle` |
| Arena 2 (Claustro) | 70 | Blackhorn | Plague Arcanist + élite | `hellhound battle` |
| Arena 3 (Ruinas) | 40 | Mecha King Ghidorah | TheWrapper + élite Straw Reaper | `LVS04_10_Battlefield` |
| Final y créditos | — | — | — | `celtic melancholy` (la de menú es `sadness piano4`) |

- **Muerte:** "HAS MUERTO" con fundido. Reintentar recarga la arena actual (la vida vuelve a 100/70/40 según el nivel, el jefe se reinicia y se rellenan las curas). Desde la pantalla de muerte también se puede ir al menú o salir.
- **Pausa** (Esc / Start): continuar, opciones, volver al menú o salir. Bloqueada durante el final.
- **Transición:** entrar al templo y subir de piso usan el cartel con cortinilla iris (0,5 s de cierre, cartel, 0,6 s de apertura). Reintentar usa un fundido corto (0,25 s) sin cartel.
- **Curación (frasco):** 10 cargas por nivel. Cura el 38 % de la vida máxima (38, 27 o 15 HP) en 0,9 s. Kaelen camina al 35 % de velocidad y el modelo brilla en verde. Un golpe, rodar, atacar o morir la cancela sin gastar la carga. No se puede usar con la vida llena, sin cargas, en ataque, rodada, daño, muerte o escenas dirigidas.

---

## 5. Controles y opciones

### 5.1 Controles por defecto

| Acción | Teclado y ratón | Mando Xbox |
|---|---|---|
| Mover | W A S D | Stick izquierdo |
| Cámara | Ratón | Stick derecho (zona muerta 0,2) |
| Atacar | Clic izquierdo | X y RB |
| Ataque fuerte | Clic derecho | RT |
| Rodar | Espacio | B |
| Curarse | R | Y |
| Fijar objetivo (lock-on) | Clic central (rueda) o Q | R3 |
| Pausa | Esc | Start |
| Menús: moverse / aceptar / volver | Flechas / Enter / Esc | D-pad o stick / A / B |
| Diálogos del final: avanzar | Enter, Espacio, clic izquierdo | A, RB, X |
| Opciones: cambiar pestaña | Ratón | LB / RB |
| Pantalla completa | Alt + Enter | — |
| Depuración (solo en compilaciones de depuración, `OS.is_debug_build()`; no existen en el `.exe` de release) | F3 (overlay IA), F5 (salta de nivel), F6 (invulnerable), F7 (cada golpe de Kaelen mata de un solo golpe, para demostraciones) | — |

Las acciones de teclado y mando se pueden reasignar; los sticks de movimiento y cámara son fijos.

### 5.2 Opciones (`scenes/ui/options_menu.tscn`)

Se abren desde el menú principal y desde la pausa. Cuatro pestañas:

- **Controles:** elegir acción, pulsar la nueva tecla o botón (Esc cancela). Si ya estaba asignada, se intercambian. Sensibilidad de cámara y "Restaurar por defecto".
- **Volumen:** General, Música, Efectos e Interfaz (en vivo). Las voces del final van por el bus de Interfaz.
- **Pantalla:** modo ventana, pantalla completa sin bordes o pantalla completa exclusiva; resolución de ventana (1280×720, 1920×1080, 2560×1440); VSync; límite de FPS (sin límite, 30, 60, 120).
- **Idioma:** español o inglés, desde `localization/translations.csv`.

Todo se guarda en `user://settings.cfg`. Los valores no válidos vuelven a los de por defecto.

---

## 6. Kaelen (jugador)

Estados: `MOVE`, `ROLL`, `ATTACK`, `HURT`, `DEAD`, más el subestado de curación dentro de `MOVE`.

| Parámetro | Valor |
|---|---|
| Vida máxima | 100 / 70 / 40 según el nivel |
| Estamina | 100; regenera 30/s tras 0,6 s sin gastar |
| Costes | Rodar 25; atacar 20; ataque fuerte 35 |
| Rodada | 0,6 s a 7 m/s; i-frames de 0,05 a 0,40 s. Clip `roll_to_run`: tras el desplazamiento, ≈ 0,26 s de recuperación (levantarse) sin i-frames, en la que no se puede rodar ni curar pero sí moverse. Una rodada pulsada al final o durante la recuperación espera en el buffer y sale al terminar (rodadas seguidas cada ≈ 0,86 s). Un ataque corta la recuperación (ataque tras rodada, ≈ 0,62 s desde el inicio de la rodada) |
| Combo | 20 / 20 / 36 (ventana de encadenado 0,4 s; buffer de entrada 0,2 s). El 3.er golpe **cierra el combo**: no encadena nada y su recorrido dura hasta 1,0 s (`FINISHER_END`); un ataque pulsado al final vuelve a empezar desde el golpe 1. El ataque fuerte sigue sirviendo de remate tras los golpes 1 y 2 |
| Mandoble | Hoja de ≈ 1,95 m (antes 2,3 m: se veía demasiado grande). Caja de 1,85 m a lo largo de la hoja, hasta la punta visible; alcance efectivo ≈ 2,35 m. Un golpe por activación |
| Ataque fuerte | Clip `jump_attack` a ×1,25: salta unos 2 m hacia delante y golpea al aterrizar (45 de daño, ventana 0,92–1,20 s, polvo y sacudida a 1,02 s); vuelve a `MOVE` a 1,48 s. Desde `MOVE` o como remate en la ventana del combo. Misma superarmadura que el combo |
| Con objetivo fijado | Camina a 3,2 m/s mirando al objetivo (mezcla `BlendSpace2D` con `strafe_left/right` y `walk_back`, clips a 2 m/s). Cada golpe del combo avanza hasta ≈ 0,75 m hacia el objetivo si está a más de 1,8 m |
| Tras recibir un golpe | 0,4 s de `HURT` y 1 s de i-frames. Superarmadura (mitad de daño, sin interrupción) en los golpes 1 y 2 y en la ventana de daño del remate y del ataque fuerte; **no** en el recorrido del remate ni en el aterrizaje del ataque fuerte, donde un golpe la interrumpe con daño completo |
| Sacudida de cámara | Si un golpe quita el 15 % o más de la vida máxima |
| Escalones | Sube escalones de hasta 0,35 m (`MAX_STEP`) |

Feedback de combate:

- **Pausa de impacto** (`hit_stop.gd`): 60 ms al acertar, 40 ms al recibir daño, con `Engine.time_scale` a 0,05. No se apila y siempre se restaura.
- **Parpadeo** (`hit_flash.gd`): 0,1 s, blanco en enemigos y rojo en Kaelen. Es un uniform del shader `psx_lit`.
- **Chispas y polvo** (`impact_fx.gd`): según la superficie del `Hurtbox`, con reservas fijas de partículas. Hueso: chispas y polvo claro; metal: chispas grandes; orgánicas (`ImpactFx.ORGANIC`, salpicadura y neblina del color de la criatura): `flesh` rojo oscuro (TheWrapper, Blackhorn, Kaelen), `ichor` verde (Plague Arcanist) y `straw` paja (Straw Reaper).

Lock-on (`lock_on.gd`): cada enemigo fijable tiene un `Marker3D` llamado `LockOnPoint`. Se suelta si el objetivo muere o se aleja más de 15 m (25 m para jefes). Con un jefe a más de 8 m el brazo de la cámara se alarga hasta 3 m.

---

## 7. Enemigos

### 7.1 Jefes

Los tres jefes comparten `boss_base.tscn` y se diferencian por modelo, recursos de ataque y valores. Fase 2 al 50 % de vida: +25 % de velocidad de ataque, más presupuesto para el Orquestador y **combos**. La embestida de Blackhorn (`charge`) existe solo en fase 2.

**Avisos (`AttackWarning`, estilo God of War):** cada `BossAttack` tiene `warning` (1 = amarillo: una rodada a tiempo lo atraviesa; 2 = rojo: la rodada no lo cubre, hay que salir de la zona o meterse en su zona segura). El modelo del atacante recibe un aura (uniform `aura` de `psx_lit`, borde Fresnel) que **sube poco a poco** durante el primer 45 % del aviso (mínimo 0,25 s), se mantiene en el golpe y se apaga en 0,35 s; nunca aparece ni desaparece de golpe. El aviso del suelo usa el mismo color con `shaders/telegraph_ground.gdshader` (borde que ondula, ruido, tramado PSX y un relleno que llega al borde cuando impacta). Rojos: los dos coletazos y el rayo. La cola de Ghidorah golpea **de 3 m hacia fuera** (aviso en anillo): pegarse al cuerpo es la zona segura (antes no había hueco; prueba `test_ghidorah_tail_has_a_safe_spot_at_the_body`); su giro dura 1,0 s.

**Combos de fase 2** (`BossAttack.combo_next`, `Boss.combo_follow_up`): pasado el 35 % de la recuperación, el jefe encadena el ataque siguiente con un aviso al 85 % y un destello naranja. Solo uno por cadena, solo si Kaelen está en el rango del siguiente (±2 m) y nunca si toca una repulsión. Bone Dragon: `bite` → `tail_sweep`, `stomp` → `bite`, `tail_sweep` → `bite`. Blackhorn: `slam` → `pounce`, `pounce` → `slam`. Ghidorah: `bite` → `tail_sweep`, `tail_sweep` → `beam`.

| Jefe | Arena | Vida | Ataques (id: distancia) | Notas |
|---|---|---|---|---|
| Bone Dragon | 1 | 500 | `bite` (mordida, avanza 1,5 m; aviso en franja de 3,4 × 5,7 m), `tail_sweep` (coletazo), `stomp` (pisotón) | 8 m de largo. Se desliza con `idle`. Sin collider en la cola. Cabeza con daño ×1,25. Desde la oleada 1: 3,6 m/s (antes 3,0), `attack_cooldown` 0,15 s, avisos 0,9 / 0,9 / 1,0 s y recuperaciones 0,6 / 0,6 / 0,7 s (sección 18.6) |
| Blackhorn | 2 | 625 | `slam` (golpe al suelo, 0–4 m), `pounce` (zarpazo con salto, 2–7 m), `charge` (embestida, 8–16 m, solo fase 2) | 3,20 m. Se desplaza con `run`. Burla (`taunt`) durante la espera. Rugido de transición a fase 2 |
| Mecha King Ghidorah | 3 | 750 | `bite` (0–6 m), `tail_sweep` (0–8 m), `beam` (rayo, 8–20 m) | Escala ×1,95 (8,1 m de alto). Cabezas golpeables solo durante `bite`. El rayo se fija al 70 % del aviso y el impacto se esquiva apartándose |

Cada ataque es un recurso `BossAttack` (`resources/attacks/*.tres`) con rango, aviso (`telegraph_time`), activo, recuperación, peso, daño y hitboxes por hueso o zona. Los avisos del suelo tienen el mismo tamaño que la zona de daño.

**Repulsión (anti-ráfagas).** Un jefe reacciona si se cumple cualquiera de estas condiciones (y el enfriamiento de 7 s ha terminado):

1. Recibe el 10 % de su vida máxima en 4 s.
2. Recibe 3 golpes en 3 s.
3. Kaelen permanece a 3,2 m o menos durante 7 s.

**Rugido de fase 2 (oleada 1):** dura 1,5 s (`PHASE2_ROAR_TIME`), el jefe es invulnerable y reutiliza la onda de la repulsión (mismo empuje, 0,35 s después). Consume la recarga de la repulsión (7 s). Mientras el jefe es invulnerable (rugido de fase 2 o repulsión), sus `Hurtbox` tienen `guard` = el jefe y `can_be_hit()` devuelve false: el golpe de Kaelen se ignora entero (sin pausa de impacto, sonido, chispas ni parpadeo).

**Persecución:** si la meta es `ATTACK`, Kaelen está al alcance de algún ataque y el jefe no gana 0,5 m en 0,6 s (`BossBrain.CHASE_PATIENCE`, `CHASE_PROGRESS`), compiten todos los ataques que la alcanzan, no solo los de apertura. Antes, el Bone Dragon (sin ataques de apertura y más lento que Kaelen con objetivo fijado) y Ghidorah (entre 5 y 8 m) la perseguían sin atacar nunca.

La reacción interrumpe lo que esté haciendo, ruge (invulnerable, hasta 1,6 s) y 0,35 s después lanza una onda de 7 m de radio. Si Kaelen está dentro, sale empujada a 18 m/s (unos 4,5 m). La rodada solo la esquiva si sus i-frames cubren el instante de la onda.

**Selección de ataque (`boss_brain.gd`).** Puntaje = peso × ajuste por distancia (0 fuera del rango) × 0,3 si repite el último ataque × bonus si Kaelen esquiva siempre hacia un lado × 1,25 en fase 2. Elige por sorteo ponderado entre los dos mejores.

### 7.2 Esbirros

- **Tipos:** normal (coste 1, 30 PV, daño 20) y élite (coste 3, 90 PV, daño 30; cada grupo lleva exactamente un élite).
- **Por arena:** Skeleton y Knight (arena 1); Plague Arcanist y su élite con tinte verdoso (arena 2); TheWrapper y Straw Reaper (arena 3).
- **Máquina de estados** (`minion_brain.gd`): `IDLE`, `CHASE`, `CIRCLE`, `ATTACK`, `RECOVER`, `STUNNED`, `DEAD`. Detecta a 12 m con cono de 110° y línea de visión.
- **Fichas de ataque:** máximo 2 atacando a la vez. Pide ficha a 4 m y la suelta a 6 m. Tras atacar o recibir un golpe espera 2 s.
- **Ataques:** cada esbirro tiene 2 o 3 recursos `MinionAttack` (`resources/attacks/minions/*.tres`: clip, aviso, ventanas de golpe, recuperación, rango, peso, avance y zona en el suelo). Elige por sorteo ponderado entre los que alcanzan a Kaelen y penaliza repetir (×0,35). Sin lista, el golpe clásico (aviso 0,5 s, activo 0,3 s, recuperación 0,8 s).

| Esbirro | Ataques |
|---|---|
| Skeleton | `swing`; `lunge` (estocada con avance, 1,4–3 m) |
| Knight (élite) | `slash`; `heavy` (×1,3); `combo` (3 golpes ×0,9 con avance) |
| Plague Arcanist | `claw`; `cast` (círculo verde de 1,6 m donde está Kaelen, 3–7 m; la sigue el 60 % del aviso de 1 s) |
| Plague (élite) | `claw`, `cast` y `leap` (salto de 2,4 m, 2,2–3,8 m) |
| TheWrapper | `charge`; `scream` (círculo de 2,6 m alrededor de él, ×0,75) |
| Straw Reaper (élite) | `reap`; `sweep` (×1,2); `combo` (3 golpes ×0,9) |

- **Amenaza por piso:** piso 1, estocadas y combos; piso 2, ataque a distancia (`cast`; los esbirros con alcance largo piden ficha desde más lejos); piso 3, **corredores**: TheWrapper corre a 6 m/s con `run` y el Straw Reaper a 5 m/s con `lurch` mientras Kaelen está a más de 6–7 m.
- **Muerte sin clip (TheWrapper):** tambaleo con su clip `hurt`, se dobla y gira, cae de espaldas, rebota, levanta polvo y se queda quieto.
- **Retirada:** un esbirro normal con menos del 30 % de vida se aleja unos 3,5 s hasta unos 9 m de Kaelen y vuelve. Solo una vez por vida.
- **Al recibir un golpe:** cualquier golpe de Kaelen aturde 0,6 s a un esbirro normal y 0,35 s a un élite (`Minion.STUN_NORMAL`, `STUN_ELITE`; élite = esbirro con `sfx_spawn`, los de coste 3). Los jefes nunca se aturden. Retroceden (normal ≈ 0,38 m; el 3.er golpe del combo ≈ 1,3 m) y el cuerpo se inclina hacia atrás un instante; los élites retroceden la mitad. La pausa de impacto es de 35 ms en golpes normales y 70 ms en el 3.º y el fuerte.
- **Hechizo del Plague (`cast`):** círculo mágico de veneno (addon Magic Circles) que se dibuja en el sitio de Kaelen durante el aviso, un orbe que sale de la mano y cae sobre él al impactar (chispas, neblina y onda); si se interrumpe, el orbe se deshace. Recarga de 4 s, así mezcla el zarpazo. Los ataques especiales de esbirros llevan aura amarilla.
- **Al morir Kaelen:** los esbirros se quedan y se burlan (`taunt` del Plague, `scream` de TheWrapper); al morir el jefe, los esbirros vivos caen como cualquier otro.
- **Muerte y cadáveres:** el clip de muerte se recorta y acelera para que el cuerpo toque el suelo en 1,5 s como mucho (`death_clip_start`, `death_land_at`, `death_fall_time`; el Skeleton y el Straw Reaper se tambaleaban 2,3 s y antes se borraban de pie a los 2 s). Al caer levanta polvo, queda 2,5 s en el suelo (`corpse_time`) y se hunde 0,9 m en 1 s con una nube de polvo antes de liberarse.
- **Navegación:** `NavigationAgent3D` con evitación, sobre la capa `small` (radio 0,5 m).

---

## 8. Inteligencia artificial

Inspirada en *Three States and a Plan: The A.I. of F.E.A.R.* (Jeff Orkin, GDC 2006): comportamiento complejo que sale de órdenes simples, una memoria compartida y una coordinación legible para el jugador. No es un planificador: son metas puntuadas por utilidad, una memoria de combate y un coordinador de escuadra.

### 8.1 Orquestador (`orchestrator.gd` + `orchestrator_model.gd`, lógica pura)

**Intensidad (0 a 100):** sube con el daño recibido (×1,5), con la vida baja (menos del 30 %, +5/s) y con esbirros a menos de 5 m (+2/s cada uno). Baja 8/s, o 15/s si no hay enemigos cerca.

**Fases:**

| Fase | Comportamiento |
|---|---|
| `BUILD_UP` | Genera oleadas. Pasa a `PEAK` con intensidad de 80 o más |
| `PEAK` | Deja que los esbirros actuales presionen durante 5 s. No genera nada |
| `RELAX` | Respiro de 10 a 20 s. Vuelve a `BUILD_UP` si la intensidad está por debajo de 30. Con la vida por debajo del 25 %, se fuerza |

**Oleadas:** una oleada de 2 o 3 esbirros (nunca más de 3 vivos) elegidos por presupuesto (base del nivel × rendimiento de Kaelen × 1,5 en fase 2). Cuando muere la última, empieza la **ventana del jefe**: 12 s × entre 0,9 y 1,3 según la intensidad, sin apariciones, para que el jugador ataque al jefe. Después, otra oleada. Se reemplaza un esbirro por el élite del grupo. No genera durante ataques especiales del jefe.

**Puntos de aparición:** `Marker3D` del grupo `spawn_point`, sobre la navegación. Prioridad: fuera del cono de cámara y a más de 8 m; si no hay, a más de 14 m aunque se vean; si falla, el más lejano a más de 8 m.

**Overlay F3** (textos en inglés): `Intensity`, `Phase`, `Budget`, `Cycle`, `Live minions`, `Tokens`, la **meta táctica del jefe** (`Boss goal`) y el **comportamiento detectado de Kaelen** (`FLEEING`, `WITH MINIONS`, `GLUED`, `PASSIVE`).

### 8.2 Memoria de combate (`combat_memory.gd`, lógica pura)

Se actualiza a 10 Hz. Guarda posición y velocidad suavizadas de Kaelen, la variación de distancia y una posición prevista a 1 s (velocidad limitada a 7 m/s). Detecta:

| Comportamiento | Cuándo |
|---|---|
| `FLEEING` | Se aleja del jefe a más de 1 m/s con velocidad mayor de 2,2 m/s durante 0,8 s (a más de 4,5 m) |
| `WITH MINIONS` | Fija o golpea a un esbirro, o un esbirro está más cerca que la mitad de su distancia al jefe |
| `GLUED` | Se queda a 3,8 m o menos durante 2 s |
| `PASSIVE` | Lejos (7 m o más) durante 3 s sin atacar ni huir |

Marcas aparte: *distraída* (con esbirros o de espaldas al jefe) y *rodeando*.

### 8.3 Metas tácticas del jefe (`boss_tactics.gd`, lógica pura)

Fuera de un ataque, el jefe reevalúa cada 0,5 s (y al terminar una recuperación o un rugido). La meta actual puntúa ×1,3 (histéresis) y dura al menos 1 s.

| Meta | Se activa cuando | Qué hace |
|---|---|---|
| `ATTACK` | Por defecto | Se acerca y ataca |
| `CUT OFF` | Kaelen huye a más de 6 m o está pasiva a más de 10 m | Va al punto previsto a 1,5 s y solo lanza ataques de apertura (embestida, salto, rayo) |
| `WAIT` | Combo largo, repulsión reciente, vida por debajo del 30 % o Kaelen pasiva | No ataca: se retira a unos 8 m y la rodea a ritmo lento. Blackhorn se burla |
| `PINCER` | Hay esbirros con Kaelen entre 4 y 18 m | Se planta a 6 m de su lado, ruge brevemente (1,1 s) y el Orquestador manda a los esbirros a los puntos de cerco |

**Emboscada:** si Kaelen está distraída y el jefe no la alcanza, se acerca lento y su siguiente aviso dura ×1,3.

**Especialización por jefe:**
- Blackhorn: la embestida y el salto apuntan al punto previsto de Kaelen si se mueve rápido.
- Bone Dragon: el coletazo puntúa ×2,2 si Kaelen intenta rodearlo.
- Ghidorah: usa el rayo para cortar la huida, apuntando delante de la dirección de Kaelen.

### 8.4 Coordinación de escuadra (`squad_tactics.gd`)

- En `PINCER`, cada 0,35 s calcula un punto de cerco por esbirro libre, a 3,6 m de Kaelen y en el lado opuesto al jefe. Los reparte por cercanía y les da una orden (`order_to`) que dura 0,9 s y se renueva mientras dure la pinza.
- **Amenazas compartidas:** con el jefe en aviso o ataque, `AttackTokens` no reparte fichas nuevas si Kaelen está a 10 m o menos del jefe (0 fichas con el jefe cerca, 1 con una amenaza lejana como el rayo, 2 sin amenaza). Así no se acumulan el ataque del jefe y el de los esbirros.

### 8.5 Medición

| Herramienta | Resultado resumido |
|---|---|
| `orchestrator_sim.gd` | La intensidad oscila en las tres arenas (media de 45 a 69 puntos de oscilación, entre 0,2 y 2 entradas a PICO por minuto). Por eso el daño recibido se escala a la vida máxima (×1,0, ×1,2 y ×1,8) |
| `boss_pressure_sim.gd` | Repulsiones en 30 s: de 0,8–2,3 a 2,3–3,0 según jefe y perfil. El tiempo para matar sube entre 0,4 y 12,4 s |
| `boss_tactics_sim.gd` | Contra Kaelen pegada al jefe, las esperas reducen el daño recibido un 9–16 % sin cambiar el tiempo para matar. Contra Kaelen que huye, el tiempo para matar sube un 20–26 % |

Las simulaciones usan Kaelen simulada, así que los tiempos reales serán mayores.

---

## 9. Niveles, arte y rendimiento

### 9.1 Exterior

- Isla `float-islands` (`IslandSkull`, ≈ 104 m) con colisión trimesh. Sendero de unos 69 m que rodea la nariz de la isla (unos 14 s caminando).
- Templo escalonado (`level_builder._temple`): puerta con arco, columnas, torre de tres cuerpos (catacumba, claustro y ruinas, uno por piso) con linterna, pináculo y aguja: 52,2 m desde la puerta, alas con tejado, árbol, piedras y columnas caídas. Solo diseño, con las mismas texturas.
- Tres huecos en la isla (ojos y nariz) con estanques de agua (`water_psx`). Sin colisión: las paredes invisibles impiden llegar.
- Vacío cubierto: niebla en tres capas y tres anillos de árboles lejanos a 125–245 m (`forest_ring.gd` con `MultiMeshInstance3D`, `fade_far` 260 m). Se funden con la bruma.
- Anillo de 14 islotes a 92–117 m y 7 masas de terreno a 173–223 m con los `.glb` de islotes existentes (`level_builder._islet_rings`, una `MultiMesh` por modelo, sin colisión) para que la isla parezca enorme.
- Mallas estáticas del templo fusionadas (`level_builder._merge_static`): el exterior pasa de 200 a 20 `MeshInstance3D` y de unas 223 a 59 draw calls estimadas; triángulos ≈ 90,7 k → 106,5 k; carga sin ventana 147 → 222 ms. Rendimiento con ventana: antes de la oleada 1, unos 205 a 223 FPS en GTX 1050 sin VSync; **después, no medido** (pendiente de la sesión con ventana).
- `ExitTrigger` en la puerta del templo: avanza a la arena 1.

### 9.2 Arenas

| | Arena 1: Catacumba | Arena 2: Claustro | Arena 3: Ruinas |
|---|---|---|---|
| Forma y tamaño | Rectangular, 32 × 32 m, techo 8 m | Octogonal, 24 m, techo 8 m (bóveda) | 40 × 40 m, sin techo, muros de 12 m |
| Pilares | 4 gruesos con cadenas | 6 columnas finas | Pilares rotos y escombros |
| Ambiente | Marrón cálido, antorchas | Azul pálido, velas, candelabro | Gris neutro, viento |
| Iluminación (`arena_mood.gd`) | Ámbar, niebla 4–46 m | Azul, niebla 8–34 m | Arena pálida, niebla 12–80 m |
| Tinte al ganar | Ámbar | Azul | Oro pálido |

Reglas comunes: entrada al sur con reja (`GateEntry`, se cierra al entrar), salida al norte (`GateExit`, se abre al morir el jefe), `ExitTrigger`, `PlayerStart`, `BossStart`, seis `Marker3D` del grupo `spawn_point`, navegación horneada al generar (capa `small` radio 0,5 m y capa `large` radio 2,5 m).

**Correcciones de geometría (2026-10-20):** la arena 2 (octógono) tiene una losa de techo de respaldo como la del suelo (por los huecos de las celdas diagonales se veía el cielo); en las arenas rectangulares de kit el suelo CSG de los pasillos empieza donde acaban las baldosas del kit bajo la puerta (dos suelos en el mismo plano hacían rayas).

**Subida entre pisos:** pasada la reja de salida (`ClimbTrigger`, creado en tiempo de ejecución por `level_gameplay.gd`) Kaelen sube sola la escalera (`Player.scripted_walk`, la cámara se coloca detrás) y sigue andando mientras se cierra la cortinilla; en el templo entra caminando por la puerta. Al llegar (`GameState.arrival_walk`), aparece en el rellano de entrada, camina hasta `PlayerStart` mientras sale una línea sobre el guardián del piso (`Narration`, `FLOOR_LORE_*`) y la reja se cierra detrás; el jefe y las oleadas esperan. El piso siguiente se carga en segundo plano (`GameState.preload_scene`) al morir el jefe o al llegar al exterior. Salidas de seguridad por tiempo si algo bloquea la caminata.

**Sala de Elysia (final, dentro de `arena_3`):** pasillo de 6 m de ancho y unos 20 m hasta la sala de 12 × 12 m con el altar. El muro norte tiene un hueco irregular hacia el cielo (cortes `BreakWall*` y `BreakCeil*`), cerrado por una barrera invisible. `ending_room.tscn` añade cielo, escombros y nubes. La caída (`start_fall()`) acelera el movimiento de nubes e islotes y el viento (`StormFX`) durante 2,5 s.

### 9.3 Look PSX

- Shader `psx_lit` (Godot-PSX-Starter-kit, MIT, portado a Godot 4): vértices que tiemblan, iluminación por vértice, texturas con filtro nearest. Variantes `alpha_scissor`, `transparent` y `metal`. Todos los modelos usan el mismo estilo.
- Postproceso `pp_band_dither` (reducción de color con dithering).
- Texturas nearest, sin mipmaps y de 256 px como máximo. Excepción: los bloques CSG generados (`level_builder._mat`, pasillos, escaleras y templo) y las piedras de la sala final usan texturas de 512 px con filtro *nearest con mipmaps*; sin mipmaps se veían como ruido a pocos metros ("textura dañada" al final de los pasillos de salida).
- Kit de piezas `dungeon_kit.meshlib` (de `PSX_Dungeon`) con material `kit_std.tres`. Las arenas 1 y 3 usan `GridMap`; la arena 2 usa baldosas y muros girados 45°.

### 9.4 Efectos (VFX)

| Efecto | Pack | Dónde |
|---|---|---|
| Rayo de Ghidorah | Beam VFX (Binbun, CC0) | `assets/vfx/beam/`, nodo `BeamVisual` |
| Racha de viento del final, chispas, polvo y humo | Storm & Wind 3D Free (CC BY 4.0) | `addons/storm_wind/` |
| Sellos de la repulsión y de la fase 2, onda del rayo | Magic Circles 3D Free (CC BY 4.0) | `addons/magic_circles/` |
| Estanques | Textura de agua SBS (CC0) | `assets/environment/textures/` |

`shader_warmup.gd` dibuja una vez cada efecto y aviso fuera de pantalla al cargar, para evitar tirones en el primer uso (en Ghidorah bajó el peor fotograma de 71–125 ms a unos 20 ms).

### 9.5 Assets de personajes: cómo se generan

- **Kaelen, Skeleton, Knight:** Mixamo. `_source/tools/build_characters.py`.
- **Plague Arcanist, TheWrapper, Straw Reaper, Blackhorn:** `_source/tools/export_multi_action.py` (varias acciones en un FBX).
- **Bone Dragon, Ghidorah:** animaciones por script (`animate_bonedragon.py`, `animate_ghidorah.py`, `dragon_anim.py`).
- Otros: `export_elysia.py` (estática, sin rig), `export_dungeon_kit.py`, `export_float_island.py`, `export_knight_sword.py`.

Ejecutar con Blender en modo fondo (ejemplo: `blender -b --factory-startup -P _source/tools/export_multi_action.py -- blackhorn`). El estado de cada modelo, sus clips y sus escalas están en la sección 15.

Para revisar un `.glb` en Blender: los huesos se dibujan como esferas y pueden tapar la malla. Se desmarca *Viewport Display → Shapes* del armature.

---

## 10. Audio

- **Buses:** `Master` → `Music`, `SFX`, `UI`. Desde Opciones se controlan los cuatro (General, Música, Efectos e Interfaz).
- **Música en bucle:** las pistas de jefes, menú, final y pantalla de muerte tienen versión `*_loop.ogg` (sin silencio al final, con el solape de fundido en un compás). Se activa `loop=true` en el `.import`. Los originales están en `assets/audio/bgm/source/` (con `.gdignore`).
- **Pistas por escena:** ver la tabla de la sección 4. La música de jefe arranca cuando el jefe detecta a Kaelen y se apaga con fundido al derrotarlo. En pausa baja 10 dB.
- **Ducking:** la música del final baja 7 dB durante el diálogo para que se oigan las voces.
- **SFX:** espada (swing, impacto, metal), pasos cada 2 m (piedra en las arenas, tierra en el exterior), ataques, daño y muerte de esbirros y jefes, rugidos de fase 2, rayo, antorchas, puerta de piedra, pantalla de muerte, sonidos de Kaelen (golpe, muerte, rodada, cansancio, trago de curación). Variación de tono ±10 %.
- **UI:** todos los botones suenan (pack Be Not Afraid UI).
- **Voces del final:** blips de Kaelen (graves) y Elysia (agudos), normalizados a -3 dBFS. Se alternan dos reproductores. Van por el bus UI.
- **Reproducción 3D:** `AudioManager.play_sfx_3d` usa un pool de reproductores.

---

## 11. Final: guion y claves

La isla cae porque los tres guardianes (Bone Dragon, Blackhorn y Ghidorah) la mantenían en el aire. Kaelen llega a Elysia, que lo entiende en cuanto nota el temblor. Ella le reprocha lo que ha costado a las familias de la isla, pero no puede odiarlo. Kaelen no se arrepiente: solo quería verla otra vez. Terminan aceptando caer juntos, abrazados, mientras el templo se hunde en las nubes.

- **Texto:** 19 líneas `ENDING_01` a `ENDING_19` en `localization/translations.csv` (una por clave y por hablante, en es y en). El prefijo "Kaelen:" o "Elysia:" sirve solo para saber quién habla y no se muestra.
- **Cámaras:** `ENDING_LINES` en `ending_director.gd` asigna cada línea a `EndingCam1` (lejos) o `EndingCam2` (cerca).
- **Escenas del final:** `ending_director.gd` (adjunto a `arena_3_gameplay.tscn`), `ending_room.gd`, `credits.tscn` con `assets/credits.txt`.
- **Tiempo:** el diálogo avanza con pulsación. El revelado de cada línea va a 30 caracteres por segundo.
- **Coreografía (`ending_director.gd`, `BEATS`):** temblor en `ENDING_04` (sacudida, Kaelen se tambalea con `hurt`, Elysia se inclina, polvo); en `ENDING_12` las dos se giran hacia el muro roto; en `ENDING_13` Elysia baja del escalón (primero a su altura hasta pasar el borde, luego al suelo) y queda a 0,7 m de Kaelen; en `ENDING_17` se inclinan una hacia la otra (8°) bajo el último temblor. Elysia respira y se balancea siempre.
- **Carga:** la caja de diálogo y el viento se crean al cargar la arena; mientras el cartel de entrada tapa la pantalla, las cámaras del final se activan unos fotogramas con los efectos encendidos para compilar sus shaders (antes daba tirón al empezar).

### 11.1 Introducción y tutorial

- **Intro (`intro_director.gd`, solo en partida nueva, `GameState.intro_pending`):** seis líneas (`INTRO_01`–`INTRO_06`): la isla flota por tres guardianes; Elysia fue subida al altar para velar su sueño; la ley dice que vencerlos hace caer la isla con todos; Kaelen sube igualmente porque prometió verla. Plano aéreo del templo, primer plano de Kaelen y negro; se salta con pausa.
- **Tutorial (`tutorial.gd`):** avisos abajo con la tecla **real** asignada (o los botones del mando si es lo último usado): moverse, cámara, rodar, atacar a un espantapájaros (el modelo del Straw Reaper en pose fija; aparece junto al sendero y no se rompe), ataque fuerte, fijar y moverse de lado, curarse, colores de las auras y "sube al templo". Cada aviso espera a que el jugador lo haga.

---

## 12. Créditos y licencias

`assets/credits.txt` es el texto que muestra la pantalla de créditos. Esta tabla resume el estado de cada asset. Cuando algo esté confirmado, actualizar también `credits.txt`.

**Leyenda:** OK = licencia clara y crédito anotado. Confirmar = autor o licencia sin verificar. Pendiente = todavía no tiene fuente registrada. No redistribuir = el archivo original no se puede publicar.

| Asset | Uso | Autor | Licencia | Estado |
|---|---|---|---|---|
| Ancient Elf Lady PSX | Elysia | Seifert (Peter_Seifert) | CC BY 4.0 | OK (crédito obligatorio) |
| Low poly woman knight | Kaelen | Desconocido | Desconocida | Confirmar (buscar la fuente) |
| Knight PS1 PSX | Élite 1 | crimsongcat | Sketchfab Standard | No redistribuir |
| Blackhorn of the Shattered Peaks | Jefe 2 | imaginais | Sin licencia formal; el autor autoriza su uso en juegos | Confirmar (guardar el permiso) |
| The Straw Reaper | Élite 3 | imaginais | Uso comercial permitido, crédito opcional | Confirmar (no hay `license.txt` local) |
| PSX Insectoid Demon | Reserva | Seifert | CC BY 4.0 | OK (no usado) |
| Bone Dragon | Jefe 1 | — | — | Pendiente |
| Mecha King Ghidorah | Jefe 3 | — | Fan-art de una propiedad con copyright | Pendiente (riesgo legal) |
| Skeleton | Esbirro 1 | — | — | Pendiente |
| Plague Arcanist | Esbirro 2 | — | — | Pendiente |
| TheWrapper V2 | Esbirro 3 | — | — | Pendiente |
| Floating island (Katydid) | No usado (descartado) | Katydid | CC BY 4.0 | OK (crédito obligatorio) |
| Low-Poly Fantasy RPG Items (Lite) | Decoración | Game Dev Skill Up | Ver README | Confirmar |
| PSX_Dungeon, Modular Dungeon, demonic weapons pack, Fantasy Weapon Starter Pack, float-islands, Retro PSX Style Mansion | Escenario y armas | — | — | Pendiente |
| Free PSX UI (Skin04) | Interfaz | rohhsa | CC0 1.0 | OK |
| DungeonFont | Títulos y botones | 0x72 y vrtxrry | CC0 (según metadatos) | Confirmar en la página de origen |
| dragonhpbar, Pulsing Heart, Pixel UI pack 3 | Interfaz | — | — | Confirmar |
| Menú principal (fondo) | Fondo del menú | Equipo | — | OK (generado con `gen_menu_bg.py`) |
| Beam VFX (Binbun) | Rayo | Binbun | CC0 1.0 | OK |
| Storm & Wind 3D Free | Viento, chispas, humo | heyheythere | CC BY 4.0 | OK (crédito obligatorio) |
| Magic Circles 3D Free | Sellos y onda | heyheythere | CC BY 4.0 | OK (crédito obligatorio) |
| Godot-PSX-Starter-kit | Shaders PSX | DruidCZ, MenacingMecha, Ahopness | MIT | OK |
| Free Fantasy SFX Pack (TomMusic) | Espada, pasos, antorcha, ambiente | TomMusic | Confirmar (el ReadMe no da términos) | Confirmar |
| Monsters SFX Vol.1 | Jefes, esbirros, rayo | Riria / Ririsaurus | Uso libre, no redistribuir | No redistribuir (crédito) |
| Be Not Afraid UI | Menús y pausa | Atelier Magicae | Uso libre, no redistribuir | No redistribuir (crédito obligatorio) |
| Efectos aportados (esbirros, Kaelen, jefes, arenas, puerta, pantalla de muerte) | Varios | Por confirmar | Por confirmar | Pendiente |
| Pistas BGM: sadness piano4, ancient creature battle, hellhound battle, LVS04_10_Battlefield, celtic melancholy | Menú, jefes, final | Por confirmar | Por confirmar | Pendiente |
| WIND-FALL | Viento del final | Aportado por la autora del proyecto | Confirmar | Confirmar |
| Dialogue Bleeps Pack | Voces del final | dmochas | Confirmar (sin readme) | Confirmar |
| PS1-Style Tree Pack | Árboles del exterior | — | Sin readme ni licencia | Pendiente |
| SBS Photorealistic Texture Pack 3 | Agua de los estanques | Screaming Brain Studios | CC0 | OK (opcional) |
| Blazing Honor (EpicOrderSounds) | No usada | EpicOrderSounds | Uso libre, no redistribuir | Sin uso |
| `skull dragon battle`, `black dragon battle`, `wyvern battle`, 40 Free PSX Footsteps | No usados | — | Por confirmar | Sin uso |

**Aviso:** Ririsaurus, Atelier Magicae y la licencia estándar de Sketchfab prohíben redistribuir los originales (en `_source/`). **El repositorio debe seguir privado.** Lo que se publica es el juego exportado, no los archivos originales.

---

## 13. Convenciones

- **Lenguaje:** GDScript con tipado estático (`var x: int`, `-> void`). Código y comentarios en inglés. Textos visibles siempre con `tr()`; las claves nuevas van a `localization/translations.csv` con columnas `es` y `en`.
- **Lógica pura y pruebas:** la IA y el combate están en clases sin escena (`RefCounted` como `BossBrain`, `OrchestratorModel`, `CombatMemory`, `BossTactics`, `MinionBrain`) para que las pruebas no dependan de nodos. Cada prueba empieza con `extends TestCase`.
- **Escenas generadas:** `exterior.tscn`, `arena_1.tscn`, `arena_2.tscn` y `arena_3.tscn` se regeneran con `level_builder.gd`. El resto de escenas se edita en el editor.
- **Commits:** pequeños, con prefijo (`feat:`, `fix:`, `test:`, `docs:`). Repartidos entre los tres integrantes. **No se añaden co-autores externos** a los commits del equipo.
- **Worktrees:** cada trabajo en paralelo va en su rama y su worktree (`git worktree add`), sin tocar el worktree principal. Antes de un push, `git pull --rebase` y pruebas. Las reglas de rama, worktrees de agentes y commits del trabajo actual están en la sección 18.1 (no se fusiona con `main`).
- **Git y LFS:** modelos, texturas, audio y `.blend` van con Git LFS (ver `.gitattributes`). No se sube `.godot/`. Los `.import` sí se suben.
- **Restaurar archivos `.import`:** Godot a veces reescribe los `.import` cambiando solo los finales de línea. Antes de commitear, comprobarlo con `git diff --ignore-cr-at-eol --stat`. Si solo cambian los finales de línea, restaurar **solo esos archivos** con `git restore -- <ruta>` (con `core.autocrlf=true` a veces hace falta borrar el archivo antes). Nunca restaurar todo el árbol. **Si se restaura un `.import` de una textura a la que Godot cambió el UID, hay que reimportar el modelo del que se extrajo** (borrar su `.godot/imported/<modelo>-*`): si no, la caché guarda el UID viejo y aparece "invalid UID" al cargar. `uid_cache_check.gd` lo detecta.
- **Shaders y materiales:** un único shader PSX para todo. Los cambios de paleta van por `modulate_color` o `tint`.
- **Medidas:** 1 unidad = 1 metro. Los modelos se normalizan a sus alturas (sección 9.5); nunca se confía en la escala del archivo original.
- **Tests antes de push:** ejecutar `run_tests.gd` (444 pasan) y, si se toca un flujo, su `.tscn`.

---

## 14. Riesgos y pendientes

### 14.1 Antes de la entrega (T18 y T19)

1. **Playtest con 2 personas externas.** Registrar en una plantilla: datos de la sesión, muertes por zona (causa, tiempo), checklist de cambios recientes y tabla de acciones. La plantilla anterior a esta versión está en el historial de git (commit `6eefbb6`). Checklist mínimo:
   - Kaelen no atraviesa jefes ni queda empujada dentro.
   - Los golpes conectan a la distancia de la animación.
   - No hay más de 3 esbirros vivos, con 1 élite por grupo.
   - Las escaleras se suben y bajan sin atascarse.
   - La pantalla de muerte aparece y reintentar carga la arena.
   - La música de jefe cambia al morir.
   - La vida al entrar a cada arena es 100 / 70 / 40.
   - Los sonidos de menús y pausa suenan.
   - El mando de Xbox funciona en menús, combate, cámara, rodada, lock-on y pausa.
   - Opciones e idioma se aplican al momento.
   - No hay tirones en el rayo de Ghidorah.
   - La sala de Elysia se ve completa durante el abrazo.
2. **Partida completa a mano** (T15 paso 3 y T16): menú → exterior → 3 jefes → final → créditos → menú, muriendo al menos una vez por jefe y usando la pausa.
3. **Congelación de funciones** y arreglos priorizados desde el playtest.
4. **Exportar Windows** (hecho, ver sección 2.6; `assets/credits.txt` ya está en el filtro) y Web si funciona. Probar el `.exe` en una PC que no sea de desarrollo.
5. **Tag `v1.0`** tras pasar el checklist y las pruebas.

### 14.2 Riesgos técnicos y de contenido

| Riesgo | Detalle |
|---|---|
| Peso de `ghidorah.glb` | Unos 26 MB con 9,1 k triángulos. Probablemente incluye texturas sin reducir (la regla es 256 px). Revisarlo antes de exportar |
| Licencias por confirmar | Varios audios, Kaelen, los modelos sin fuente y la pista de Blackhorn. Ver sección 12 |
| Ghidorah como fan-art | Propiedad con copyright. Revisar antes de cualquier publicación |
| Repositorio privado | Los packs de Ririsaurus y Atelier Magicae no pueden publicarse con sus archivos originales |
| Sonidos sin escuchar en todos los casos | Algunos efectos aportados y los de esbirros normales (ataque y muerte) aún no se han comprobado en todos los equipos. Revisar en el playtest |
| Mando real | Los controles están configurados para Xbox, pero no se ha probado el mando físico en todas las funciones. Revisar en el playtest |
| Aviso del rayo | El aviso cuenta con una zona clara que no hace daño y puede confundir. Revisar en el playtest |
| Animaciones de esbirros | Ataque y muerte de los esbirros normales pendientes de revisar en juego. El élite Knight usa un clip de caminar más lento |
| Shaders nuevos sin compilar en pruebas | `telegraph_ground.gdshader` y el aura de `psx_lit` no se compilan sin ventana (las pruebas usan el renderizador vacío). Revisados a mano; confirmar en el editor que no hay errores de shader |
| Sincronía de los ataques nuevos | Los tiempos de los ataques de esbirros (`resources/attacks/minions/`) son estimados: se comprobó que golpean, no que el golpe coincida con el clip. Velocidades de `strafe`/`walk_back` (2 m/s), `run` y `lurch` puestas a ojo. Revisar en juego y ajustar los `.tres` |
| Plague Arcanist a distancia | Desde 3 m su único ataque en rango es `cast`: a media distancia lo lanza casi siempre. Vigilar en el playtest si resulta repetitivo |
| Ataque fuerte con ajustes antiguos | Si alguien había reasignado "Atacar" al clic derecho, ese clic sigue atacando normal; se arregla reasignando en Opciones |
| Clips duplicados de Blackhorn | `idle` y `charge`, y `walk` y `run`, duran lo mismo. Solo se usa `run` |
| Cola de Ghidorah junto al muro norte | En la arena 3 la punta de la cola queda a 1,9 m del muro (1,35 m en `death`). Medir de nuevo si se regeneran las arenas |
| Decoración de arenas | Pendiente. Las arenas tienen geometría de kit pero poca decoración |
| Final: plano de `EndingCam2` | Kaelen puede tapar a Elysia. Ajustable en el generador |
| Cámara contra paredes | El brazo de la cámara puede dejar a Kaelen muy cerca de la lente con un muro detrás |
| Árboles del pack PS1 | Sin licencia clara. Confirmar antes de publicar |

---

## 15. Assets de personajes: estado

Estado verificado en `scale_reference` y en el juego. Los `.glb` están en `assets/`.

| Rol | Modelo | Altura | Clips | Estado |
|---|---|---|---|---|
| Kaelen | `characters/kaelen/kaelen.glb` | 1,70 m | `idle`, `walk`, `run`, `roll`, `attack_1..3`, `hurt`, `death` (+ extras) | Listo. El `roll` original dura 2,4 s y se reproduce más rápido |
| Elysia | `characters/elysia/elysia.glb` | 1,60 m | Sin clips (estática; `Tween` de respiración) | Listo |
| Skeleton | `minions/skeleton/skeleton.glb` | 1,75 m | `idle`, `walk`, `attack`, `hurt`, `death` | Listo |
| Knight (élite 1) | `minions/knight/knight.glb` | 2,10 m | `idle`, `walk`, `attack`, `attack_2`, `combo`, `hurt`, `death` | Listo. Espada en `knight_sword.glb` |
| Plague Arcanist | `minions/plague_arcanist/plague_arcanist.glb` | 1,80 m | `idle`, `walk`, `attack`, `attack_cast`, `attack_leap`, `taunt`, `knockdown`, `hurt`, `death` | Listo (`hurt` y `death` son recortes de `knockdown`) |
| TheWrapper | `minions/thewrapper/thewrapper.glb` | 2,00 m | `idle`, `walk`, `run`, `attack`, `hurt`, `scream` | Listo. Sin `death`: cae con un `Tween` |
| Straw Reaper (élite 3) | `minions/straw_reaper/straw_reaper.glb` | 1,90 m | `idle`, `walk`, `lurch`, `attack`, `attack_2`, `combo`, `hurt`, `death` | Listo |
| Bone Dragon | `bosses/bonedragon/bonedragon.glb` | ~7,7 m de largo | `idle`, `roar`, `bite`, `tail_sweep`, `stomp`, `death` | Listo (animado por script) |
| Blackhorn | `bosses/blackhorn/blackhorn.glb` | 3,20 m | `idle`, `taunt`, `roar`, `walk`, `run`, `charge`, `attack_pounce`, `attack_slam`, `hurt`, `death` | Listo |
| Ghidorah | `bosses/ghidorah/ghidorah.glb` | 4,15 m (escala ×1,95 en Godot) | `idle`, `roar`, `bite`, `tail_sweep`, `beam`, `death` | Listo (ver la nota de peso en 14.2) |

Armas: mandoble de Kaelen (`weapons/greatsword/greatsword.glb`, 1,00 m; escala ×1,4–1,5 en el `BoneAttachment3D` de `mixamorig:RightHand`) y espada del Knight (`knight_sword.glb`, 1,10 m).

Animaciones de Mixamo (Kaelen, Skeleton, Knight, Plague Arcanist, Straw Reaper y Blackhorn): el procedimiento está documentado en el propio script `_source/tools/build_characters.py` y en `export_multi_action.py`. Para personajes nuevos: auto-rig en Mixamo con *In Place* activado en los clips, descarga FBX sin piel, combinar con el script y revisar en `scale_reference`.

---

## 16. Equipo

| Integrante | Nombre completo | Usuario de git |
|---|---|---|
| Paula | Paula Sofia Gonzalez Zambrano | `SoFzzz` |
| David | David Alejandro Aza Jojoa | `Dazaj02` |
| Stehven | Stehven Alexander Obando Cordoba | `StehvenObandoUcc` |

Los roles A/B/C del plan original quedaron sin efecto desde el 2026-10-14: ya no hay dueños de archivos ni de escenas. Cualquiera puede tocar cualquier parte, con commits pequeños y pruebas antes de cada push.

---

## 17. Decisiones: dinamismo del combate y curva (2026-10-20)

Trabajo de pulido dentro de T18, antes de la congelación de T19. Rama `wt/combat-dynamism` (worktree aparte). Objetivo: que el combate sea menos monótono y que cada piso tenga su propio pico de ritmo, sin assets nuevos.

| Decisión | Elección | Por qué | Revisar si |
|---|---|---|---|
| Alcance | Pulido acotado de T18, sin sistemas nuevos de datos ni guardado | Congelación y playtest pendientes | El playtest pide cambios mayores |
| Vida por piso | Se mantiene 100 / 70 / 40 | Da la dificultad creciente y encaja con la historia | El playtest la ve injusta en el piso 3 |
| Esbirros con varios ataques | Usar los clips ya importados (`attack_2`, `combo`, `attack_cast`, `attack_leap`, `scream`, `run`…), empezando por los élites | Es lo que más dinamismo da por esfuerzo; solo código y `.tscn` | Algún clip no encaja en juego |
| Muerte de TheWrapper | Mejorar la caída por `Tween` (desplome, polvo, sonido) | **Nada de Blender ni de rehacer `.glb`** | Aparece un clip `death` ya hecho |
| Fase 2 de jefes | Al menos un combo encadenado por jefe en fase 2 | Un giro a mitad de pelea, el pico de ritmo de cada piso | Los combos vuelven injusta la fase 2 |
| Kaelen: `jump_attack` | Nuevo ataque fuerte con el clip existente | Variedad ofensiva | Rompe el balance de las simulaciones |
| Kaelen: strafe | Caminar lateral y hacia atrás con lock-on (`strafe_left/right`, `walk_back`), cuidando que el ataque siga sintiéndose bien al girar hacia el objetivo | Peleas más dinámicas con jefes | El ataque pierde precisión o peso |
| Curva entre pisos | Cada piso presenta una amenaza nueva (por ejemplo, a distancia en el piso 2, esbirros que corren en el piso 3) | Progresión por variedad, no solo por números | El playtest no la nota |
| Registro | Esta sección (una sola guía) | El equipo eligió `AGENTS.md` en lugar de `docs/` | — |

### Resuelto al implementar
- `jump_attack`: clic derecho / RT, 45 de daño, 35 de estamina, desde `MOVE` o como remate del combo (sección 6). Ventana de golpe medida fotograma a fotograma en `kaelen_moves_flow`.
- Combos de cada jefe: sección 7.1. Amenaza de cada piso: sección 7.2.

### Abierto
- Revisar en juego la sincronía de los ataques nuevos con sus clips y las velocidades de `strafe`, `run` y `lurch` (sección 14.2).
- Las simulaciones (`boss_pressure_sim`, `boss_tactics_sim`) usan una Kaelen simulada sin ataque fuerte ni strafe: no miden esos cambios. Sí miden los combos de fase 2.
- Efecto medido de los combos (`boss_tactics_sim`, tácticas activas, frente al código anterior): daño a Kaelen por minuto con perfil evasivo +27 % en Bone Dragon y +11 % en Blackhorn; Ghidorah casi igual. Si el playtest lo ve duro: subir `Boss.COMBO_RECOVER_FRACTION` (0,35) o `COMBO_TELEGRAPH` (0,85), o quitar un `combo_next`.
- Corregido en `boss_pressure_sim.gd`: la Kaelen simulada golpeaba desde 2,5 m del centro del jefe, pero Ghidorah (×1,95) se planta a 5 m (`engage_range`), así que nunca moría (0/12). Ahora el alcance es el mayor entre 2,5 m y el `engage_range`: Ghidorah muere en 12/12 (60 s y 88 s).

---

## 18. Plan de mejora, reglas de trabajo y política de rama (2026-10-20)

Plan aprobado por el equipo para seguir refinando el juego después de la sección 17. Quien continúe el trabajo (persona o agente) **debe leer y cumplir esta sección entera** antes de tocar nada.

### 18.1 Política de rama y directorios (obligatoria)

| Regla | Detalle |
|---|---|
| **`main` no se toca** | Este trabajo **nunca se fusiona con `main`** ni se hace push a `main` hasta que el equipo lo decida expresamente en otra ocasión. Nada de merge, rebase sobre `main` ni pull request hacia `main` por iniciativa propia. |
| Rama de integración | `wt/combat-dynamism`, en el worktree `../Descending-wt-combat`. Es la única rama que se sube: `git push origin wt/combat-dynamism`, **sin `--force`**. |
| Worktree principal | La carpeta `Descending-to-my-Heaven` (rama `main`) no se modifica. |
| Worktrees de agentes | Uno por agente y oleada: `../Descending-w<oleada>-<agente>`, rama `w<oleada>/<agente>`, creada desde `wt/combat-dynamism`. **Nunca se suben.** Al terminar se entrega su diff, se integra en `wt/combat-dynamism` y el worktree se elimina con `git worktree remove`. |
| Archivos por agente | Dos agentes no editan el mismo archivo en la misma oleada. Si hace falta, el plan de la oleada dice quién lo toca y en qué orden. |
| Commits | Solo con aprobación explícita del equipo. Autoría rotada entre Paula, David y Stehven con `--author` (esta PC no tiene identidad de git). Sin líneas `Co-Authored-By` ni atribuciones a IA. |
| **Cada commit debe cargar solo** | Un commit no puede depender de otro posterior (los siete commits de la sección 17 no lo cumplían: solo el último carga completo; por eso esa rama se fusiona entera). A partir de ahora, cada commit deja el proyecto cargando y con las pruebas en verde. |
| Higiene de `.import` | Antes de cada commit se restauran los `.import` que solo cambian finales de línea, UID o compresión por la reimportación (`git diff --ignore-cr-at-eol`). Solo se suben los `.import` con un cambio pedido (por ejemplo, los mipmaps de la sección 9.3). |
| `.godot/` | No se sube nunca. Para arrancar un worktree nuevo se puede copiar la caché `.godot/` de la rama de integración. |

### 18.2 Reglas innegociables de calidad

1. **Nada se afirma sin verificarlo.** Toda afirmación sobre código o assets sale de leer el archivo o de ejecutar algo, con `archivo:línea` o la salida del comando.
2. **Ninguna cifra inventada.** FPS, tiempos o daños salen de una ejecución real; lo que no se pudo medir se escribe "no medido".
3. **Lo visual se marca como pendiente de revisión.** Las pruebas sin ventana no compilan shaders ni dibujan. Todo cambio visual queda "pendiente de revisión en pantalla" hasta que una persona lo confirme.
4. **Una prueba que falla no se debilita para que pase.** Se busca la causa. Si cambia una regla de diseño, se dice, se documenta aquí y se renombra la prueba (ejemplo: la cola de Ghidorah, sección 7.1).
5. **Sin atajos que escondan problemas:** no se desactivan sistemas, no se ponen valores "a ojo" cuando se pueden medir y no se dejan `TODO`.
6. **Escenas generadas solo desde `level_builder.gd`** (sección 2.4).
7. **Sin assets nuevos sin licencia verificada.** Sin Blender (aplazado por el equipo, ver 18.4).
8. **Rendimiento ante todo:** 60 FPS o más en GTX 1050 a 1280×720 sin VSync.
   - Sin asignaciones por fotograma en código caliente.
   - Efectos con pools (ImpactFx) y partículas con tope.
   - Geometría estática en mallas fusionadas o `MultiMeshInstance3D`.
   - Todo cambio visual grande se mide antes y después.
9. **Godot solo sin ventana** (`--headless`) mientras alguien trabaja en la PC: con ventana, el juego captura el ratón. Las mediciones con ventana se pactan con el equipo.
10. **Código y comentarios en inglés;** textos visibles con `tr()` en es y en (`localization/translations.csv`).
11. **Alcance cerrado:** lo que no está en 18.3 se pregunta al equipo antes de hacerlo.
12. **Informe honesto:** cada entrega incluye la salida real de las pruebas, lo que no se pudo verificar y cualquier fallo encontrado, aunque sea propio.

### 18.3 Organización: tres agentes y doble revisión

Tres agentes trabajan en paralelo por oleada, cada uno en su worktree. **Cada oleada se revisa dos veces:**
- **Revisión 1 (cruzada):** cada agente revisa el diff de otro (1 → 2, 2 → 3, 3 → 1) buscando errores de lógica, regresiones, rendimiento y reglas incumplidas.
- **Revisión 2 (integración):** se aplican los tres diffs en `wt/combat-dynamism` y se pasa la batería completa: `run_tests.gd`, todos los flujos de `tests/flow/` y las simulaciones de la sección 2.5.

Al final de cada oleada se para para que el equipo lo pruebe en pantalla antes de la siguiente.

**Criterios de "terminado" de cada tarea:**
- Pruebas unitarias y flujos en verde, más pruebas nuevas que fijen el comportamiento añadido.
- Rendimiento dentro del presupuesto (medido o razonado con evidencia).
- Revisión 1 y revisión 2 superadas.
- Esta guía actualizada (sección correspondiente y riesgos).
- Sin archivos fuera de su alcance modificados.

| Oleada | Agente 1: combate y control | Agente 2: jefes e IA | Agente 3: mundo, progresión y auditoría |
|---|---|---|---|
| **1. Correcciones** | Combo con recuperación (el 3.er golpe cierra el combo; el siguiente golpe solo encadena tras el recorrido); rodada con recuperación (`roll_to_run`) sin cortes por spam; ataque tras rodada para dar dinamismo; aturdimiento solo a esbirros (0,6 s normales, 0,35 s élites); espantapájaros (modelo del Straw Reaper) como muñeco del tutorial | Rugido de fase 2 corto (≈ 1,5 s), invulnerable y con la onda de repulsión existente; Bone Dragon más difícil **sin ataques nuevos** (velocidad, tiempos, presión, avance del mordisco); corregir el hueco en que el jefe persigue sin atacar | Atajos de depuración (F3, F5, F6) solo en compilaciones de depuración (`OS.is_debug_build()`); UID de los `.import` coherentes; anillo de islotes y terreno alrededor de la isla para que parezca enorme; bosque lejano más alejado; torre del templo de tres cuerpos, uno por piso (≈ 45–55 m), con coronación; medición de rendimiento del exterior |
| **2. IA** | IA de esbirros: separación y cerco por huecos; atacar en la apertura de Kaelen y esperar si los encara; esquivar de lado el ataque fuerte; magos que mantienen 5–7 m y buscan línea de visión; élites con aguante en su ataque; grito de alerta | IA de jefes: memoria ampliada (curación, estamina, momento de las rodadas, ataques fallados); castigo de aperturas; ataques retrasados contra la rodada repetida; espaciado y rodeo; personalidad de fase 2; cabezas que siguen a Kaelen (`LookAtModifier3D`) | Simulaciones con la Kaelen real (combo, ataque fuerte, estamina, rodada); indicadores por jefe (tiempo para matar, daño recibido, esquivas) antes y después; guardado por piso ("Continuar" en el menú) |
| **3. Presentación** | Abrazo del final con IK en los brazos de Kaelen (`TwoBoneIK3D`); *ragdoll* (`PhysicalBone3D`) para la muerte de TheWrapper | Presentación de cada jefe (barrido de cámara y nombre) y rugido procedural del Bone Dragon sobre su clip | Pantalla de resultados (tiempo, muertes por piso, frascos); notas de historia en cada piso; accesibilidad (iconos además de color en los avisos, sacudida activable, tamaño de subtítulos) |
| **4. Cierre** | Revisión general cruzada | Revisión general cruzada | Sesión de rendimiento con ventana pactada (exterior, rayo de Ghidorah, final); esta guía al día |

Objetivo de dificultad: progresión coherente entre pisos. El Bone Dragon sigue siendo el primer jefe, pero su tiempo para matar en `boss_pressure_sim` debe acercarse al de Blackhorn sin superarlo. Ningún jefe puede caer en segundos solo con spam de ataque (hoy, sin las correcciones de la oleada 1, el Bone Dragon cae en 11,5 s; medido con Kaelen invulnerable).

### 18.4 Qué se aprueba y qué no

| Propuesta | Estado | Motivo |
|---|---|---|
| Correcciones de la oleada 1 | **Aprobado** | Fallos confirmados en código y en pruebas (combo infinito, rodada sin recuperación, rugido de fase 2 de 4,2 s sin defensa, atajos de depuración en el `.exe`) |
| Bone Dragon más difícil ajustando lo que ya tiene | **Aprobado** | Hoy es el más fácil por diseño: 3 ataques cuerpo a cuerpo, 3 m/s frente a los 5 m/s de Kaelen, sin cambios en fase 2 |
| Ataques nuevos para el Bone Dragon | **No aprobado** | Decisión del equipo |
| Más dinamismo en el combate | **Aprobado** | Ataque tras rodada, IA de las oleadas 2 y 3 |
| Isla rodeada de islotes y terreno | **Aprobado** | Que parezca enorme |
| Escalar la isla | **No aprobado** | Obliga a re-medir sendero, estanques y templo |
| Torre imponente | **Aprobado** | Por fuera los tres pisos no se notaban |
| IA de jefes y esbirros (oleada 2) | **Aprobado** | Prioridad del equipo |
| Abrazo con IK, *ragdoll* de TheWrapper, rugido procedural | **Aprobado** | Mejoran la animación sin assets nuevos |
| **Rig y animaciones de Elysia (Blender + Mixamo)** | **Aplazado** | Sin Blender de momento; se retoma al terminar este proceso. Sin rig, Elysia solo puede moverse como un bloque |
| Guardado por piso, presentación de jefes, pantalla de resultados, notas de historia | **Aprobado** | Progresión y cierre |
| Accesibilidad (iconos en avisos, sacudida activable, subtítulos) | **Aprobado** | Coste bajo |
| Modo de dificultad "Historia" | **Solo si sobra tiempo** | No es prioritario |
| Nueva partida+ | **No aprobado** | Mucho coste para tres jefes |
| Multijugador, mundo abierto, voces dobladas, personajes nuevos | **No aprobado** | Fuera de alcance o sin assets con licencia |
| Exportación Web | **Pendiente de evaluar al final** | Compatibilidad y peso (`ghidorah.glb` de 26 MB) |
| Fusionar con `main` | **No aprobado** | Ver 18.1 |

### 18.5 Pendientes conocidos de la auditoría (2026-10-20)

- ~~Atajos de depuración activos en el `.exe` exportado~~ → resuelto en la oleada 1 (sección 18.6).
- ~~Avisos de UID inválido al cargar~~ → causa encontrada en la oleada 1: caché importada obsoleta tras restaurar un `.import` con UID regenerado; en el repositorio no había UID incoherentes (prueba `test_uid_coherence.gd` y herramienta `uid_cache_check.gd`).
- ~~Superarmadura de Kaelen más combo infinito~~ → resuelto en la oleada 1 (sección 6).
- Simulaciones sin el ataque fuerte, la estamina real ni la rodada → oleada 2, agente 3.
- Shaders nuevos (`telegraph_ground.gdshader`, aura de `psx_lit`) sin verificar en pantalla → revisión del equipo en el editor.
- Equilibrio de los 10 frascos por piso a revisar tras las oleadas 1 y 2.
- Fuera de código: peso de `ghidorah.glb`, licencias por confirmar y Ghidorah como fan-art (sección 14.2).

### 18.6 Oleada 1: resultado (2026-10-21, pendiente de prueba del equipo y sin commit)

Tres agentes en worktrees `../Descending-w1-{combate,jefes,mundo}` (ramas locales `w1/*`, que no se suben ni se borran; worktrees eliminados al integrar), sin archivos compartidos. Revisión 1 cruzada (1→2, 2→3, 3→1): los tres "aprobado con cambios"; se corrigieron la rodada en el buffer que caducaba durante la recuperación, el feedback de impacto durante el rugido invulnerable y una prueba que dependía de la caché `.godot/`. Revisión 2 en `wt/combat-dynamism`: **444/444 pruebas**, **13/13 flujos `FLOW: OK`** sin avisos de UID, y `uid_cache_check` con 0 modelos obsoletos.

| `boss_pressure_sim` (12 runs, TTK steady / opportunist) | Antes | Después |
|---|---|---|
| Bone Dragon | 34,0 / 48,8 s | 42,1 / 46,8 s |
| Blackhorn | 45,9 / 81,6 s | 46,7 / 76,3 s |
| Ghidorah | 60,1 / 89,0 s | 62,8 / 87,5 s |

- **Objetivo de dificultad:** con el perfil steady (el más cercano al spam de ataque) el Bone Dragon se acerca a Blackhorn sin superarlo. Con el perfil opportunist (solo pega en la recuperación del jefe) no se acerca: un jefe más rápido da más ventanas de castigo; llegar a ≈ 73 s exigiría frenarlo o quitar castigos. **Decisión pendiente del equipo.**
- **La simulación no modela** el combo con recuperación ni la rodada de 0,86 s de Kaelen (`boss_pressure_sim.gd:133-138`), y su muñeco no tiene colisión (el avance del mordisco lo atraviesa): oleada 2, agente 3.
- `boss_tactics_sim` (daño a Kaelen por minuto, tácticas activas): Bone Dragon agresivo 287 → 378 y evasivo 241 → 314; Blackhorn y Ghidorah casi iguales. `orchestrator_sim`: sin cambios.
- **Cambio fuera de alcance, a aprobar por el equipo:** el `AnimationTree` de Kaelen se evalúa en los fotogramas de física (`callback_mode_process = PROCESS_PHYSICS`). Sin ventana había un fotograma de animación por cada 3–6 de física y la espada (sigue un hueso) podía atravesar al objetivo sin golpear. La pose avanza a 60 Hz.
- **Pendiente de revisión en pantalla:** `roll_to_run` como rodada (posible torsión de cadera al empezar y acabar), deslizamiento de pies al moverse durante la recuperación, el espantapájaros, el corte del rugido a 1,5 s, la franja del mordisco y su avance, la torre, los islotes (shader del bosque, sin la niebla del entorno; las copas más lejanas rozan el `far` de 300 m) y las normales de las mallas fusionadas.
- **Riesgos para el playtest:** la rodada ocupa 0,86 s y el remate ya no tiene superarmadura en su recorrido (combate más exigente); el rugido de fase 2 consume la recarga de la repulsión (unos 5,5 s sin protección contra ráfagas al empezar la fase 2); combo de fase 2 del Bone Dragon `tail_sweep` → `bite` en ≈ 0,78 s (calculado), menor que el ciclo de rodada; la persecución corregida castiga antes a Kaelen si se cura mientras el jefe acecha (`AMBUSH_SPEED`); Ghidorah usa el coletazo entre 5 y 8 m si Kaelen guarda distancia; la detección de élite por `sfx_spawn` es frágil (un `@export var elite` explícito sería más robusto); carga del exterior ≈ +75 ms y `exterior.tscn` de 1,09 MB.
