# AGENTS.md: Descending to my Heaven

Guía única del proyecto para quien se incorpora al equipo: qué es el juego, en qué estado está, cómo ejecutarlo y probarlo, cómo está organizado el código y qué falta. Sustituye a la antigua carpeta `docs/`.

- **Fecha de esta versión:** 2026-10-16
- **Juego:** boss rush 3D en tercera persona, estilo soulslike y PSX. Kaelen sube un templo de tres pisos sobre una isla flotante y derrota a tres jefes para llegar a Elysia.
- **Motor:** Godot 4.7.2 estable, GDScript con tipos estáticos, renderizador `gl_compatibility` (Compatibility). Resolución interna 640×360, ventana 1280×720.
- **Rama de trabajo:** `feat/aza`. `main` (ec0e4fa) ya incluye un merge de esta rama; la exportación a Windows se prepara en `wt/export`.
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
| T18: pulido y playtest | Casi hecha | **Playtest con 2 personas externas** (plantilla en la sección 14); decoración de arenas (pendiente); commit por persona |
| T19: congelación, exportación Windows, tag `v1.0` | En curso | Exportación Windows lista (sección 2.6). Falta: congelación, probar el `.exe` en otra PC, revisar créditos, `v1.0` (Web, si funciona) |

### 1.2 Lo último que se hizo (2026-10-14 a 2026-10-16)

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

Pasa si termina con `N/N passed` y código de salida 0. **Número actual de pruebas: 365.** Cada prueba crea sus propios nodos y los libera al terminar.

### 2.3 Pruebas de flujo (escenas)

```
godot --headless --path . res://tests/flow/<nombre>.tscn
```

Pasa si imprime `FLOW: OK`. Los siete flujos:

| Flujo | Comprueba |
|---|---|
| `death_flow` | Muerte real con los autoloads: pantalla de muerte, reintento |
| `dialogue_flow` | Final con diálogo en la arena 3: avance solo por pulsación (con `-- shots <carpeta>` en ventana, mide el bus UI y guarda capturas) |
| `ending_cut_flow` | El final mueve a Kaelen solo con la pantalla en negro |
| `ending_finish_flow` | El final siempre avanza aunque haya un fundido en curso |
| `hit_feedback_flow` | Pausa de impacto y parpadeo |
| `transition_flow` | Cartel entre pisos: no se dispara dos veces, Kaelen bloqueada, se puede saltar |
| `ui_flow` | HUD y menú de opciones (captura de tecla cancelada al ocultarse) |

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
| Rodar | Espacio | B |
| Curarse | R | Y |
| Fijar objetivo (lock-on) | Clic central (rueda) o Q | R3 |
| Pausa | Esc | Start |
| Menús: moverse / aceptar / volver | Flechas / Enter / Esc | D-pad o stick / A / B |
| Diálogos del final: avanzar | Enter, Espacio, clic izquierdo | A, RB, X |
| Opciones: cambiar pestaña | Ratón | LB / RB |
| Pantalla completa | Alt + Enter | — |
| Depuración | F3 (overlay IA), F5 (salta de nivel), F6 (invulnerable) | — |

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
| Costes | Rodar 25; atacar 20 |
| Rodada | 0,6 s a 7 m/s; i-frames de 0,05 a 0,40 s |
| Combo | 20 / 20 / 36 (ventana de encadenado 0,4 s; buffer de entrada 0,2 s) |
| Mandoble | Caja de 2,15 m a lo largo de la hoja; alcance efectivo ≈ 2,6 m. Un golpe por activación |
| Tras recibir un golpe | 0,4 s de `HURT` y 1 s de i-frames. Mientras ataca recibe la mitad de daño |
| Sacudida de cámara | Si un golpe quita el 15 % o más de la vida máxima |
| Escalones | Sube escalones de hasta 0,35 m (`MAX_STEP`) |

Feedback de combate:

- **Pausa de impacto** (`hit_stop.gd`): 60 ms al acertar, 40 ms al recibir daño, con `Engine.time_scale` a 0,05. No se apila y siempre se restaura.
- **Parpadeo** (`hit_flash.gd`): 0,1 s, blanco en enemigos y rojo en Kaelen. Es un uniform del shader `psx_lit`.
- **Chispas y polvo** (`impact_fx.gd`): según la superficie (carne, hueso, metal) con reservas fijas de partículas.

Lock-on (`lock_on.gd`): cada enemigo fijable tiene un `Marker3D` llamado `LockOnPoint`. Se suelta si el objetivo muere o se aleja más de 15 m (25 m para jefes). Con un jefe a más de 8 m el brazo de la cámara se alarga hasta 3 m.

---

## 7. Enemigos

### 7.1 Jefes

Los tres jefes comparten `boss_base.tscn` y se diferencian por modelo, recursos de ataque y valores. Fase 2 al 50 % de vida: +25 % de velocidad de ataque y más presupuesto para el Orquestador. La embestida de Blackhorn (`charge`) existe solo en fase 2.

| Jefe | Arena | Vida | Ataques (id: distancia) | Notas |
|---|---|---|---|---|
| Bone Dragon | 1 | 500 | `bite` (mordida), `tail_sweep` (coletazo), `stomp` (pisotón) | 8 m de largo. Se desliza con `idle`. Sin collider en la cola. Cabeza con daño ×1,25 |
| Blackhorn | 2 | 625 | `slam` (golpe al suelo, 0–4 m), `pounce` (zarpazo con salto, 2–7 m), `charge` (embestida, 8–16 m, solo fase 2) | 3,20 m. Se desplaza con `run`. Burla (`taunt`) durante la espera. Rugido de transición a fase 2 |
| Mecha King Ghidorah | 3 | 750 | `bite` (0–6 m), `tail_sweep` (0–8 m), `beam` (rayo, 8–20 m) | Escala ×1,95 (8,1 m de alto). Cabezas golpeables solo durante `bite`. El rayo se fija al 70 % del aviso y el impacto se esquiva apartándose |

Cada ataque es un recurso `BossAttack` (`resources/attacks/*.tres`) con rango, aviso (`telegraph_time`), activo, recuperación, peso, daño y hitboxes por hueso o zona. Los avisos del suelo tienen el mismo tamaño que la zona de daño.

**Repulsión (anti-ráfagas).** Un jefe reacciona si se cumple cualquiera de estas condiciones (y el enfriamiento de 7 s ha terminado):

1. Recibe el 10 % de su vida máxima en 4 s.
2. Recibe 3 golpes en 3 s.
3. Kaelen permanece a 3,2 m o menos durante 7 s.

La reacción interrumpe lo que esté haciendo, ruge (invulnerable, hasta 1,6 s) y 0,35 s después lanza una onda de 7 m de radio. Si Kaelen está dentro, sale empujada a 18 m/s (unos 4,5 m). La rodada solo la esquiva si sus i-frames cubren el instante de la onda.

**Selección de ataque (`boss_brain.gd`).** Puntaje = peso × ajuste por distancia (0 fuera del rango) × 0,3 si repite el último ataque × bonus si Kaelen esquiva siempre hacia un lado × 1,25 en fase 2. Elige por sorteo ponderado entre los dos mejores.

### 7.2 Esbirros

- **Tipos:** normal (coste 1, 30 PV, daño 20) y élite (coste 3, 90 PV, daño 30; cada grupo lleva exactamente un élite).
- **Por arena:** Skeleton y Knight (arena 1); Plague Arcanist y su élite con tinte verdoso (arena 2); TheWrapper y Straw Reaper (arena 3).
- **Máquina de estados** (`minion_brain.gd`): `IDLE`, `CHASE`, `CIRCLE`, `ATTACK`, `RECOVER`, `STUNNED`, `DEAD`. Detecta a 12 m con cono de 110° y línea de visión.
- **Fichas de ataque:** máximo 2 atacando a la vez. Pide ficha a 4 m y la suelta a 6 m. Tras atacar o recibir un golpe espera 2 s.
- **Ataque:** aviso de 0,5 s, hitbox activa 0,3 s, recuperación de 0,8 s.
- **Retirada:** un esbirro normal con menos del 30 % de vida se aleja unos 3,5 s hasta unos 9 m de Kaelen y vuelve. Solo una vez por vida.
- **Cadáveres:** desaparecen a los 2 s.
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
- Templo escalonado (`level_builder._temple`): puerta con arco, columnas, torre de cuatro pisos, alas con tejado, árbol, piedras y columnas caídas. Solo diseño, con las mismas texturas.
- Tres huecos en la isla (ojos y nariz) con estanques de agua (`water_psx`). Sin colisión: las paredes invisibles impiden llegar.
- Vacío cubierto: niebla en tres capas y tres anillos de árboles lejanos (`forest_ring.gd` con `MultiMeshInstance3D`). Se funden con la bruma. Rendimiento: unos 205 a 223 FPS en GTX 1050 sin VSync.
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

**Sala de Elysia (final, dentro de `arena_3`):** pasillo de 6 m de ancho y unos 20 m hasta la sala de 12 × 12 m con el altar. El muro norte tiene un hueco irregular hacia el cielo (cortes `BreakWall*` y `BreakCeil*`), cerrado por una barrera invisible. `ending_room.tscn` añade cielo, escombros y nubes. La caída (`start_fall()`) acelera el movimiento de nubes e islotes y el viento (`StormFX`) durante 2,5 s.

### 9.3 Look PSX

- Shader `psx_lit` (Godot-PSX-Starter-kit, MIT, portado a Godot 4): vértices que tiemblan, iluminación por vértice, texturas con filtro nearest. Variantes `alpha_scissor`, `transparent` y `metal`. Todos los modelos usan el mismo estilo.
- Postproceso `pp_band_dither` (reducción de color con dithering).
- Texturas nearest, sin mipmaps y de 256 px como máximo.
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
- **Worktrees:** cada trabajo en paralelo va en su rama y su worktree (`git worktree add`), sin tocar el worktree principal. Antes de un push, `git pull --rebase` y pruebas.
- **Git y LFS:** modelos, texturas, audio y `.blend` van con Git LFS (ver `.gitattributes`). No se sube `.godot/`. Los `.import` sí se suben.
- **Restaurar archivos `.import`:** Godot a veces reescribe los `.import` cambiando solo los finales de línea. Antes de commitear, comprobarlo con `git diff --ignore-cr-at-eol --stat`. Si solo cambian los finales de línea, restaurar **solo esos archivos** con `git restore -- <ruta>`. Nunca restaurar todo el árbol.
- **Shaders y materiales:** un único shader PSX para todo. Los cambios de paleta van por `modulate_color` o `tint`.
- **Medidas:** 1 unidad = 1 metro. Los modelos se normalizan a sus alturas (sección 9.5); nunca se confía en la escala del archivo original.
- **Tests antes de push:** ejecutar `run_tests.gd` (365 pasan) y, si se toca un flujo, su `.tscn`.

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
