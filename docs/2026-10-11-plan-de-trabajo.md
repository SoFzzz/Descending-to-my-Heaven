# Descending to my Heaven — Plan de trabajo (7 días)

> Los pasos usan casillas (`- [ ]`) para seguimiento.

**Objetivo:** un boss rush 3D estilo PSX en Godot, jugable de principio a fin (menú → isla → 3 jefes → Elysia → créditos), construido por 3 personas en paralelo sin pisarse.

**Arquitectura:** componentes pequeños reutilizables (`Health`, `Stamina`, `Hitbox`, `Hurtbox`) usados por Kaelen, esbirros y jefes; autoloads (`Events`, `GameState`, `AttackTokens`, `Orchestrator`, `AudioManager`) como contrato entre personas; cada arena separada en una escena de **arte** (dueño C) y una escena de **gameplay** (dueño B) para que nadie edite el mismo archivo. La lógica de IA y combate vive en clases puras testeables sin escena.

**Stack:** Godot 4.7.2 (GDScript, renderizador Compatibility), Blender 5.2 + Mixamo, Git LFS.
**Spec:** [2026-10-10-descending-to-my-heaven-design.md](2026-10-10-descending-to-my-heaven-design.md)

## Estado actual (2026-10-15, día 5)

> Esta sección es el resumen vivo del avance. Las tareas de abajo conservan su texto original; las casillas y las notas "Resultado" reflejan lo hecho. **Ya no hay roles A/B/C ni dueños de archivos** (decisión del 2026-10-14): las tablas de dueños de más abajo son históricas. Lo único que sigue vigente es la regla de las escenas generadas.

### Qué tenemos

- **Pruebas:** 145/145 (`tests/run_tests.gd`), código 0 (2026-10-15). Incluye las nuevas de la T15 (`test_level_exit.gd`, `test_ending_director.gd`, `test_player_cutscene.gd`, `test_cutscene_blocks_pause`) y de la T16 (`test_minion_visuals.gd`).
- **Autoloads:** `Events`, `GameState`, `AttackTokens`, `Orchestrator` (completo), `AudioManager` (stub). `run/main_scene = scenes/ui/main_menu.tscn`.
- **Combate** (`scripts/combat`): `Health`, `Stamina`, `Hitbox`, `Hurtbox`.
- **Kaelen:** estados MOVE/ROLL/ATTACK/HURT/DEAD, rodada con i-frames, combo de 3 golpes (daño 20/20/36), defensa con 1 s de i-frames tras un golpe y ×0.5 de daño mientras ataca, lock-on, HUD, mandoble a dos manos, buffer de entrada de 0.2 s. F6 = modo dios.
- **Esbirros:** `MinionBrain` (pura) + `Minion` (FSM, fichas de ataque: máximo 2 atacando, espera de 2 s para volver a pedirla). `Minion.alert()` los pone en persecución. Variantes con modelo, animaciones y tinte de élite (T16): `minion_skeleton`/`minion_knight_elite` (arena 1), `minion_plague`/`minion_plague_elite` (arena 2), `minion_wrapper`/`minion_reaper_elite` (arena 3; el élite es The Straw Reaper).
- **Orquestador** (`orchestrator_model.gd` puro + `orchestrator.gd` autoload):
  - Intensidad 0–100 y fases BUILD_UP / PEAK / RELAX según spec §8.3.
  - **Ciclo por oleadas con ventana del jefe:** primera oleada a los 3 s; oleada de 3–4 esbirros; cuando muere el último, `clear_delay` (12 s ×0.9–1.3 según intensidad) sin apariciones para que el jugador ataque al jefe; después, otra oleada. Nunca aparecen esbirros con alguno vivo. Parámetros en `ArenaConfig` (`wave_size_min/max`, `clear_delay`, `first_wave_delay`, `base_budget`, `max_alive`).
  - **Puntos de aparición por niveles:** 1) fuera del cono de cámara y a > 8 m; 2) a > 14 m aunque se vean; 3) el más lejano a > 8 m tras un intento fallido; si no hay, reintenta.
  - `end_arena()` libera esbirros y fichas al morir Kaelen o al ganar.
  - Overlay F3 (intensidad, fase, presupuesto, ciclo, vivos, fichas); F5 salta de nivel.
- **Jefes:** `Boss`, `BossAttack` (Resource), `BossBrain` (puntaje por utilidad). El antiguo `attack_driver.gd` se integró en `boss.gd`/`boss_attack.gd` y se borró. Campos nuevos de `BossAttack`: `advance_distance`, `opener`, `extra_hitbox_paths`, `visual_path`, `exposes_hurtboxes`. Regla: dentro de `engage_range` compiten todos los ataques válidos; fuera solo los `opener`, nunca repitiendo el último; si ninguno vale, el jefe camina. El cuerpo del jefe ya no atraviesa a Kaelen (máscara 3).
  - **Bone Dragon** (400 PV), **Blackhorn** (500 PV; ataques `slam` 0–4 m, `pounce` 2–7 m, `charge` 8–16 m solo fase 2; `slam`, `pounce` y `charge` son `opener`; solo usa el clip `run` para desplazarse), **Ghidorah** (600 PV; `bite` 0–6 m, `tail_sweep` 0–8 m, `beam` 8–20 m; escala ×1.95 → 8.1 m de alto y 13.7 m de largo; las cabezas solo reciben golpes en la ventana de `bite`).
- **Niveles** (generados por `scripts/tools/level_builder.gd`, nunca a mano): `exterior`, `arena_1`, `arena_2` (octógono), `arena_3` (40×40 m con pasillo y sala de Elysia) con arte de kit (`GridMap` + `dungeon_kit.meshlib`, material `kit_std.tres`). Navegación horneada solo a la altura del suelo. Escenas de gameplay: `arena_1/2/3_gameplay.tscn` y `exterior_gameplay.tscn`.
- **Flujo:** menú principal, pausa (Esc), "HAS MUERTO" con recarga, transición con fundido, `GameState.advance_level()`; vida máxima 100/70/40 según nivel. Al ganar una arena la reja de salida se abre 3 s después y `ExitTrigger` avanza de nivel.
- **Salida del exterior (T15):** el `ExitTrigger` del exterior avanza a la arena 1. Antes no estaba conectado.
- **Final y créditos (T15, verificado en Godot con un recorrido automático el 2026-10-15; falta la partida completa a mano):** en `arena_3_gameplay`, `ending_director.gd` hace la respiración de Elysia, el corte entre dos cámaras con texto, el fundido del abrazo y el paso a los créditos (`scenes/ui/credits.tscn`, `assets/credits.txt`). El botón Créditos del menú principal aparece solo cuando existe la escena.

### Qué hicimos en esta etapa (días 3–5)

| Tarea | Resultado |
|---|---|
| T9 Jefes + Bone Dragon + arena 1 | Hecha. Hito del día 3 probado a mano: menú → arena 1 → ganar y perder. |
| T10 Menús, pausa, muerte, flujo | Hecha. |
| T11 Arte de arena 1 + animaciones de jefes | Hecha. `GridMap` en `arena_1`; se cambió el material del kit a `kit_std.tres` porque `psx_lit` hacía desaparecer baldosas grandes. Blackhorn y Ghidorah verificados en `scale_reference`. |
| T12 Orquestador + overlay | Hecha, con el ciclo de oleadas y ventana del jefe pedido tras probar a mano (los esbirros eran excesivos). |
| T13 Blackhorn y Ghidorah | Hecha, incluidas `arena_2_gameplay` y `arena_3_gameplay`. Se corrigió el arte de Ghidorah (colas y alas bajo el suelo, `death`) y se redujo su escala. |
| T14 Arenas 2 y 3 + exterior | Hecha y commiteada en `feat/aza`. Arte de kit en arenas 2 y 3 y en el exterior; el sendero del exterior rodea la nariz abierta de la isla; PlayerStart a 6 m de la pared (cámara a 4 m); `spawn_point` recolocados; navegación limitada en altura. |
| T15 Flujo completo, final y créditos | Hecha y commiteada en `feat/aza`. Verificada en Godot con un recorrido automático (salida del exterior, final completo hasta créditos); falta la partida completa a mano. Detalles en la Tarea 15. |
| T16 Esbirros por nivel y élites | Hecha y commiteada en `feat/aza`. Revisión a mano pendiente. Verificado en Godot: cada arena genera su esbirro y su élite (coste 3, vida 90). Detalles en la Tarea 16. |
| Deuda técnica | `attack_driver.gd` integrado en `Boss`; apariciones por niveles; Ghidorah ×1.95; Blackhorn solo corre; daño de Kaelen ×2; `slam` de Blackhorn como `opener`. (Commiteada en `feat/aza`.) |

### Qué nos falta

| Tarea | Pendiente |
|---|---|
| **T15** Verificación manual | Paso 3 de la Tarea 15: partida completa con F6/F5 (el commit ya está en `feat/aza`). Pendiente además: añadir `assets/credits.txt` al filtro de exportación de recursos no-recurso (T19). |
| **T16** Revisión a mano | Ver en juego animaciones, espada del Knight, hoz del Straw Reaper y caída de TheWrapper. El Aura Battler no se usa: el élite de la arena 3 es el Straw Reaper (2026-10-15). |
| **T17** Audio | Completa (2026-10-15). Incluye música por escena (menú, exterior, jefes, final y créditos), SFX de espada, pasos de Kaelen y esbirros, monstruos, élites (el élite de la Plague usa el set del Knight), ataques de jefes (sin sonido en los avisos), rugidos de fase y muerte, rayo de Ghidorah, antorchas, ambiente de arenas, puerta de piedra, pantalla de muerte, sonidos de Kaelen (golpe, muerte, rodar, cansancio), voces tipo blip en los diálogos del final (pack de dmochas), UI y volumen configurable en Opciones. Licencias "por confirmar": TomMusic y las pistas BGM salvo Blazing Honor. |
| **T18** Pulido y playtest | En curso (2026-10-15). Hecho: menú de opciones (controles reasignables, volumen por bus, sensibilidad, idioma español/inglés, mando de Xbox) y sonidos faltantes. En curso: pausa de impacto, parpadeo al recibir golpe, iluminación por arena y balance con F3. Pendiente: playtest con 2 personas externas, registrado en [playtest.md](playtest.md). |
| **T19** Congelación, exportar Windows | Pendiente (ver tarea 19). |
| **Integración** | `feat/aza` va 55 commits por delante de `main`. No hay merge ni PR a `main` todavía. |

### Riesgos y mejoras anotadas

- **Probar a mano** (no medido por los arneses): la sensación de las tres peleas con el daño duplicado y las oleadas, `arena_2` y `arena_3` completas, jefe y oleadas juntos, y el exterior de principio a fin.
- **Cámaras del final (resuelto en T15; verificado con un recorrido automático el 2026-10-15):** `ending_director.gd` activa `EndingCam1/2` con `make_current()` explícito, y la cámara de Kaelen conserva el override `current = true` en `arena_3_gameplay.tscn`, así que el final no le roba la vista. Mejora opcional: que `EndingCam1/2` sean `Marker3D` en el generador y que el final cree la cámara por código.
- **Recorrido del exterior:** dura ~14 s (la spec pide 1–2 min). Alargar el sendero es opcional.
- **Combate:** el rayo de Ghidorah usa el VFX "Beam VFX" de Binbun (2026-10-15), y baja en diagonal de la boca central al suelo bajo Kaelen, con la hitbox y el aviso siguiéndolo (ver `asset-status.md`). Aviso del jefe: disco rojo opaco (hacerlo semitransparente, con borde y pulso). `hit_landed` se emite una vez por hurtbox tocada (se oiría doble con el audio). El dragón y Ghidorah se deslizan con `idle`. Parry opcional. Los avisos del suelo de `pounce`, `charge` y `slam` no se revisaron con capturas.
- **Arte:** el suelo de la sala de Elysia sigue con textura triplanar; línea fina en una unión de pared de `arena_2`; revisar capturas de las escenas finales regeneradas. Si se regeneran las arenas, repetir la medición de la cola de Ghidorah contra el muro norte de `arena_3` (margen actual 1.9 m, 1.35 m en `death`).
- **Esbirros:** el tercer nivel de aparición solo tiene pruebas unitarias. Los esbirros tienen sonido de daño (y aparecer/daño/muerte en los élites Knight y Straw Reaper); ataque y muerte de esbirros normales siguen sin sonido. Los cadáveres desaparecen a los 2 s (`corpse_time`).
- **Final:** en el plano de `EndingCam2` Kaelen tapa a Elysia (la cámara está detrás de Kaelen); se ajusta en el generador si se quiere.
- **Otros:** `player_died` solo se emite en la primera muerte de cada instancia de Kaelen (funciona porque la recarga crea otra). Blackhorn: `idle`/`charge` y `walk`/`run` duran lo mismo (posibles clips duplicados; solo se usa `run`). El error `Parameter "material" is null` al cerrar corridas headless con Kaelen es del renderizador dummy y es inofensivo.
- **Peso de Ghidorah:** `assets/bosses/ghidorah/ghidorah.glb` pesa ~26 MB con 9.1k triángulos; probablemente tiene texturas incrustadas sin reducir (la regla del proyecto es 256 px). Revisarlo antes de exportar (T19).
- **Licencias por carpeta:** solo 4 carpetas de `assets/` tienen `license.txt` (`bosses/blackhorn`, `characters/elysia`, `characters/kaelen`, `minions/knight`). Faltan en `bosses/bonedragon`, `bosses/ghidorah`, `environment/island`, `environment/kit`, `environment/textures`, `minions/plague_arcanist`, `minions/skeleton`, `minions/straw_reaper`, `minions/thewrapper` y `weapons/greatsword`. El diseño (§13.1) pide uno por carpeta.
- **Playtest:** `docs/playtest.md` existe como plantilla (2026-10-15); falta rellenarla con las dos sesiones de la T18.
- **Documentación:** la regla de escenas ("`<nivel>_gameplay.tscn` instancia el nivel como hijo `Level`") ya está corregida en §6.4 del documento de diseño. El texto original de las tareas 8 y 15 conserva la redacción antigua; lo vigente es lo que dice esta sección.

## Restricciones globales

- Godot **4.7.2**, GDScript con tipos estáticos (`var x: int`), renderizador `gl_compatibility`. 1 unidad = 1 metro.
- Valores de combate exactos de la spec §4: vida Kaelen 100/70/40 por nivel; estamina 100, regenera 30/s tras 0.6 s; costo rodar 25, atacar 20; invulnerabilidad 0.35 s de 0.6 s de rodada; daño Kaelen 20/20/36 (duplicado el 2026-10-14 para acortar los combates; el valor original de la spec era 10/10/18); vida esbirro 30; vida jefes 400/500/600; fase 2 al 50 %.
- Medidas exactas de la spec §7.4–7.6 (alturas, cápsulas, hurtbox, cámara, navegación). Capas de colisión de §7.7 (ya nombradas en `project.godot`).
- Capas de navegación: 1 = `small` (radio 0.5, alto 2.0), 2 = `large` (radio 2.5, alto 4.0); celda 0.25 m.
- Todos los modelos pasan por `scale_reference` (§7.8) antes de usarse.
- Texturas: filtro *nearest*, sin mipmaps, `Size Limit` 256.
- Comando de pruebas (PowerShell, raíz del repo):
  `& "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s res://tests/run_tests.gd`
  Pasa si termina con `N/N passed` y código de salida 0.
- La documentación del proyecto no menciona herramientas de IA usadas en el desarrollo.

## Reglas para no pisarse

1. **Cada archivo tiene un solo dueño** (tabla abajo). Si necesitas un cambio en un archivo ajeno, se lo pides al dueño.
2. **`project.godot` solo lo edita B.** Autoloads, mapa de entradas y ajustes nuevos se piden a B.
3. **Nivel = dos escenas:** `scenes/levels/<nivel>.tscn` (arte, dueño C) y `scenes/levels/<nivel>_gameplay.tscn` (gameplay, dueño B; `exterior_gameplay` de A), que **instancia** al nivel como hijo `Level` y agrega a Kaelen, enemigos y lógica. C nunca coloca enemigos; B nunca mueve muros.
   - **Las escenas generadas (`exterior.tscn`, `arena_N.tscn`) se SOBRESCRIBEN cada vez que se ejecuta `scripts/tools/level_builder.gd`: nunca se editan a mano ni se les agregan nodos.** Los puntos del mapa (`PlayerStart`, `BossStart`, `spawn_point`, `GateEntry`, `GateExit`, `ExitTrigger`, `EndingTrigger`…) se buscan por nombre o grupo desde la escena de gameplay. Los cambios del mapa se piden a C, que los hace en las tablas del generador (problemas conocidos en [`problemas-mapa.md`](problemas-mapa.md)). El generador nunca escribe `*_gameplay.tscn` (tiene un `assert`).
4. **Entrega de modelos:** C exporta a `assets/<categoría>/<nombre>/<nombre>.glb` y avisa en el chat del equipo con la lista de animaciones. Quien usa el modelo lo instancia; **no** lo edita.
5. **Git:** trabajar en `main` con commits pequeños; antes de cada `push` ejecutar `git pull --rebase`. Correr las pruebas antes de hacer push.
6. **Sincronización:** 10 min al inicio del día (qué hace cada uno) y 20 min al final (integración y prueba juntos).
7. Las firmas de la sección "Contrato" no se cambian sin avisar a los otros dos.

### Dueños de archivos

| Dueño | Archivos |
|---|---|
| **A — Jugador e interfaz** | `scripts/player/*`, `scenes/player/*`, `scenes/ui/{main_menu,pause_menu,hud,credits,death_screen,options_menu,transition}.tscn` + sus scripts en `scripts/ui/`, `scenes/levels/test_arena.tscn`, `scenes/bosses/boss_blackhorn.tscn`, `scenes/bosses/boss_ghidorah.tscn`, `resources/attacks/blackhorn_*.tres`, `resources/attacks/ghidorah_*.tres`, `scripts/game/game_state.gd` (desde el día 3), `scripts/game/ending_director.gd` |
| **B — IA y enemigos** | `project.godot`, `scripts/game/events.gd`, `scripts/combat/*`, `scripts/ai/*`, `scenes/enemies/*`, `scenes/bosses/boss_base.tscn`, `scenes/bosses/boss_bonedragon.tscn`, `resources/attacks/bonedragon_*.tres`, `scenes/levels/arena_*_gameplay.tscn`, `scenes/ui/debug_overlay.tscn`, `tests/*`, `docs/playtest.md` |
| **C — Arte, escenarios y sonido** | `assets/**`, `shaders/*`, `scenes/levels/{scale_reference,exterior,arena_1,arena_2,arena_3}.tscn`, `scripts/tools/level_builder.gd`, `assets/environment/base_env.tres`, `scripts/audio/*`, `docs/asset-status.md`, sección §7.8 del documento de diseño |

## Contrato (lo que todos usan)

Estas firmas se crean el día 1 en la Tarea 1 (como stubs) y no cambian sin aviso.

```gdscript
# scripts/game/events.gd  — autoload "Events"
signal player_damaged(amount: int, current: int, max_value: int)
signal player_died
signal enemy_died(enemy: Node3D, cost: int)
signal boss_phase_changed(boss: Node3D, phase: int)
signal boss_defeated(boss: Node3D)
signal arena_entered(arena_id: int)
signal arena_cleared(arena_id: int)
signal hit_landed(position: Vector3, surface: StringName)   # &"flesh", &"bone", &"metal"

# scripts/game/game_state.gd — autoload "GameState"
const MAX_HP_BY_LEVEL: Array[int] = [100, 70, 40]
var current_level: int                    # 0, 1, 2
func get_player_max_hp() -> int
func start_new_game() -> void             # level 0 → exterior
func advance_level() -> void              # tras boss_defeated: siguiente arena o ending
func reload_current_arena() -> void       # reaparición tras muerte
func go_to_main_menu() -> void

# scripts/ai/attack_tokens.gd — autoload "AttackTokens"
const MAX_TOKENS := 2
func request(enemy: Node) -> bool
func release(enemy: Node) -> void
func reset() -> void
func holders_count() -> int

# scripts/ai/orchestrator.gd — autoload "Orchestrator"
func begin_arena(config: ArenaConfig) -> void
func end_arena() -> void
func get_debug_info() -> Dictionary       # {intensity, phase, budget, alive, tokens}

# scripts/audio/audio_manager.gd — autoload "AudioManager"
func play_music(stream: AudioStream, fade_time: float = 1.0) -> void
func play_sfx_3d(stream: AudioStream, position: Vector3, pitch_variation: float = 0.1) -> void
func play_ui(stream: AudioStream) -> void

# Grupos de nodos
# "player"   → la Kaelen activa (una sola)
# "lockable" → enemigos fijables; tienen hijo Marker3D llamado "LockOnPoint"
# "enemy"    → todo esbirro vivo (el Orquestador los cuenta)
```

## Foco de revisión

Fallos que la spec implica pero que ninguna prueba "normal" toca; cada uno tiene su prueba en la tarea dueña:

1. **Esbirro que muere con ficha de ataque** → la ficha se libera; si no, nadie vuelve a atacar (Tarea 2: `test_tokens_released_when_holder_freed`).
2. **Reaparición deja estado sucio** (fichas tomadas, Orquestador en Pico, jefe con vida parcial) → todo vuelve al inicio (Tarea 2 `test_reset_clears_all`, Tarea 12 `test_reset_returns_to_build_up`, Tarea 9 verificación manual).
3. **Un solo tajo golpea varias veces al mismo objetivo** (el `Area3D` re-detecta) → un golpe por activación (Tarea 2: `test_hitbox_hits_each_target_once_per_activation`).
4. **Kaelen y el jefe mueren en el mismo frame** → gana el jugador si la vida del jefe llegó a 0; tras `boss_defeated` Kaelen es invulnerable (Tarea 9 verificación manual, Tarea 10 `invulnerable` al recibir `boss_defeated`).
5. **El objetivo fijado muere o sale de rango** → el lock-on se suelta sin errores de instancia liberada (Tarea 5: `test_lock_on_drops_invalid_target`).

---

# DÍA 1 — Base y validación

Meta del día: el contrato existe, Kaelen-cápsula se mueve en `test_arena`, los modelos están medidos.

### Tarea 1 (B, primera hora): Contrato, mapa de entradas y corredor de pruebas

**Archivos:**
- Crear: `scripts/game/events.gd`, `scripts/game/game_state.gd`, `scripts/ai/attack_tokens.gd`, `scripts/ai/orchestrator.gd`, `scripts/audio/audio_manager.gd` (stubs con las firmas del Contrato; cuerpos `pass` o retorno por defecto)
- Crear: `tests/run_tests.gd`, `tests/test_case.gd`, `tests/test_smoke.gd`
- Modificar: `project.godot` (autoloads + entradas)

**Interfaces:**
- Produce: todo el bloque "Contrato"; acciones de entrada `move_forward`, `move_back`, `move_left`, `move_right` (WASD + stick izq.), `attack` (clic izq. / X), `roll` (Espacio / B), `lock_on` (clic central o Q / R3), `pause` (Esc / Start), `debug_overlay` (F3), `debug_skip` (F5), `debug_god` (F6); cámara con ratón y stick der. (A lee el ratón en `_unhandled_input`).
- Produce: `class_name TestCase extends RefCounted` con `assert_eq(actual, expected, msg := "")`, `assert_true(cond, msg := "")`, `assert_almost(actual: float, expected: float, eps := 0.001, msg := "")`, propiedades `failed: bool`, `message: String`.

- [x] **Paso 1: Escribir el corredor `tests/run_tests.gd`**

```gdscript
extends SceneTree
# Ejecuta todos los métodos test_* de res://tests/test_*.gd. Sale con código 1 si algo falla.
func _init() -> void:
	var total := 0
	var failures := 0
	for file in DirAccess.get_files_at("res://tests"):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
		for method in script.get_script_method_list():
			if not String(method.name).begins_with("test_"):
				continue
			total += 1
			var case: TestCase = script.new()
			case.call(method.name)
			if case.failed:
				failures += 1
				print("FAIL %s::%s — %s" % [file, method.name, case.message])
	print("%d/%d passed" % [total - failures, total])
	quit(1 if failures > 0 else 0)
```

- [x] **Paso 2: Escribir `tests/test_case.gd` y una prueba de humo** `test_smoke.gd::test_runner_works` con `assert_eq(1 + 1, 2)`. Todo archivo de prueba empieza con `extends TestCase`; las pruebas que crean nodos los liberan con `free()` al final.

- [x] **Paso 3: Ejecutar el comando de pruebas** — Esperado: `1/1 passed`, código 0. Cambiar temporalmente a `assert_eq(1 + 1, 3)` y confirmar `FAIL` y código 1; revertir.

- [x] **Paso 4: Crear los stubs del Contrato y registrarlos como autoloads** en `project.godot` (`Events`, `GameState`, `AttackTokens`, `Orchestrator`, `AudioManager`), más el mapa de entradas.

- [x] **Paso 5: Verificar** — abrir el proyecto en Godot sin errores en el panel *Output*; el comando de pruebas sigue en `1/1 passed`.

- [x] **Paso 6: Commit y push inmediato** (los otros dos esperan esto)

```bash
git add project.godot scripts tests
git commit -m "feat: add project contract, input map and test runner"
git push
```

### Tarea 2 (B): Componentes de combate

**Archivos:**
- Crear: `scripts/combat/health.gd`, `scripts/combat/stamina.gd`, `scripts/combat/hitbox.gd`, `scripts/combat/hurtbox.gd`
- Completar: `scripts/ai/attack_tokens.gd`
- Pruebas: `tests/test_health.gd`, `tests/test_stamina.gd`, `tests/test_hitbox.gd`, `tests/test_attack_tokens.gd`

**Interfaces:**
- Consume: `Events.hit_landed`.
- Produce:
  - `class_name Health extends Node` — `signal changed(current: int, max_value: int)`, `signal died`; `@export var max_value: int = 100`; `var current: int`; `var invulnerable: bool`; `func take_damage(amount: int) -> void`; `func reset(new_max: int = -1) -> void`; `func is_dead() -> bool`.
  - `class_name Stamina extends Node` — `signal changed(current: float, max_value: float)`; `@export var max_value := 100.0`, `regen_per_sec := 30.0`, `regen_delay := 0.6`; `func try_spend(amount: float) -> bool`; `func tick(delta: float) -> void` (llamado desde `_process`).
  - `class_name Hurtbox extends Area3D` — `@export var health: Health`; `@export var damage_multiplier := 1.0`; `@export var surface: StringName = &"flesh"`; `signal hurt(amount: int, source: Node)`; `func receive_hit(amount: int, source: Node) -> void`.
  - `class_name Hitbox extends Area3D` — `@export var damage: int`; `func activate() -> void`; `func deactivate() -> void`; `func register_hit(hurtbox: Hurtbox) -> bool` (true solo la primera vez por activación); al detectar un `Hurtbox` llama `receive_hit` y emite `Events.hit_landed`.

- [x] **Paso 1: Escribir las pruebas que fallan**

```gdscript
# tests/test_health.gd
func test_damage_reduces_and_clamps_at_zero():
	var h := Health.new(); h.max_value = 100; h.reset()
	h.take_damage(30); assert_eq(h.current, 70)
	h.take_damage(500); assert_eq(h.current, 0); assert_true(h.is_dead())
	h.free()
func test_died_emits_once():          # dos golpes letales → died se emite 1 vez
func test_invulnerable_ignores_damage():
func test_reset_with_new_max():       # reset(70) → current 70, max_value 70

# tests/test_stamina.gd
func test_spend_requires_positive_stamina():
	var s := Stamina.new(); s.current = 10.0
	assert_true(s.try_spend(25.0)); assert_eq(s.current, 0.0)   # se permite con > 0 y queda en 0
	assert_true(not s.try_spend(20.0))                          # con 0 no se permite
	s.free()
func test_no_regen_before_delay():    # tras gastar, tick(0.5) → no sube
func test_regen_rate_after_delay():   # tras gastar a 0: tick(0.6) y luego tick(1.0) → current == 30.0
func test_regen_clamps_at_max():

# tests/test_hitbox.gd
func test_hitbox_hits_each_target_once_per_activation():
	var hb := Hitbox.new(); var target := Hurtbox.new()
	hb.activate()
	assert_true(hb.register_hit(target)); assert_true(not hb.register_hit(target))
	hb.deactivate(); hb.activate()
	assert_true(hb.register_hit(target))
	hb.free(); target.free()
func test_hurtbox_applies_multiplier():   # multiplier 1.25, receive_hit(20) → health.current == 75 (100 - 25)

# tests/test_attack_tokens.gd
func test_max_two_holders():              # 3 pedidos → true, true, false
func test_same_enemy_requesting_twice_keeps_one_token():
func test_release_frees_a_slot():
func test_tokens_released_when_holder_freed():   # holder.free() → request de otro enemigo devuelve true
func test_reset_clears_all():
```

En las pruebas de `AttackTokens` instanciar el script directamente (`load("res://scripts/ai/attack_tokens.gd").new()`), no el autoload.

- [x] **Paso 2: Ejecutar pruebas** — Esperado: FAIL (clases no definidas).
- [x] **Paso 3: Implementar los cuatro componentes y `AttackTokens`.** `AttackTokens` guarda los dueños en un `Array` y descarta los `!is_instance_valid` antes de contar. `Hurtbox.receive_hit` usa `roundi(amount * damage_multiplier)`.
- [x] **Paso 4: Ejecutar pruebas** — Esperado: todas pasan.
- [x] **Paso 5: Commit** — `feat: add combat components and attack tokens`

### Tarea 3 (A): Kaelen-cápsula, cámara y rodada en `test_arena`

**Archivos:**
- Crear: `scenes/levels/test_arena.tscn` (piso CSG 32×32 m, 4 pilares 1.2 m × 8 m, paredes invisibles; capa `world`)
- Crear: `scenes/player/kaelen.tscn`, `scripts/player/player_controller.gd`, `scripts/player/camera_rig.gd`
- Prueba: `tests/test_player_roll.gd`

**Interfaces:**
- Consume: `Health`, `Stamina`, `Hurtbox` (Tarea 2; si aún no están, usar stubs locales y reemplazar al hacer pull).
- Produce: `class_name Player extends CharacterBody3D` en grupo `"player"`, con hijos `Health`, `Stamina`, `Hurtbox` (capa 7), `CameraRig`; `enum State { MOVE, ROLL, ATTACK, HURT, DEAD }`; `var state: State`; `func is_invulnerable() -> bool`; constantes `ROLL_DURATION := 0.6`, `ROLL_IFRAME_START := 0.05`, `ROLL_IFRAME_END := 0.40`, `ROLL_COST := 25.0`.
- Medidas: collider cápsula r 0.35 · alto 1.70 (capa 2, máscara 1|3|4); hurtbox r 0.30 · alto 1.50; cámara pivote 1.5 m, `spring_length` 4 m, FOV 70°, margen 0.2, máscara del `SpringArm3D` solo capa 1.

- [x] **Paso 1: Prueba que falla** — `test_player_roll.gd`:
  - `test_iframes_window`: `Player.iframes_active_at(t)` es falso en 0.0, verdadero en 0.05 y 0.30, falso en 0.45 (ventana de 0.35 s).
  - `test_roll_needs_stamina`: con `stamina.current = 0`, `try_roll()` devuelve false y `state` sigue `MOVE`.
- [x] **Paso 2: Ejecutar** — Esperado: FAIL.
- [x] **Paso 3: Implementar** `static func iframes_active_at(t: float) -> bool`, `func try_roll() -> bool`, movimiento relativo a la cámara (velocidad 5 m/s caminar, 7 m/s rodada), gravedad, giro suave hacia la dirección de movimiento, y `camera_rig.gd` (órbita con ratón, captura del cursor).
- [x] **Paso 4: Ejecutar pruebas** — Esperado: pasan.
- [x] **Paso 5: Verificación manual** — F6 sobre `test_arena.tscn`: la cápsula camina, rueda, no atraviesa pilares; la cámara se acerca al chocar con un pilar y no atraviesa paredes.
- [x] **Paso 6: Commit** — `feat: add player capsule with camera and roll`

### Tarea 4 (C): Escalas, importación y estado de assets

**Archivos:**
- Crear: `scenes/levels/scale_reference.tscn`, `docs/asset-status.md`
- Crear: `assets/<categoría>/<nombre>/` con los GLB/FBX importados y su `license.txt`
- Modificar: tabla de §7.8 del documento de diseño

**Interfaces:**
- Produce: `docs/asset-status.md` con una fila por modelo: ruta en `assets/`, factor de escala, altura medida, lista exacta de animaciones, estado (`listo` / `falta rig` / `falta animación` / `reemplazado`).

- [x] **Paso 1: Importar** los 11 modelos del reparto (§3 de la spec) a `assets/`. Los FBX con escalas internas raras (knight, skeleton, bonedragon, TheWrapper, woman knight) se abren en Blender, se aplica escala y se exportan a GLB.
- [x] **Paso 2: Armar `scale_reference.tscn`** — grilla de 1 m, cápsula de 1.70 m, cada modelo a su altura de la tabla §7.4 (Kaelen 1.70, Elysia 1.60, Skeleton 1.75, Knight 2.10, Plague Arcanist 1.80, TheWrapper 2.00, Aura Battler 3.00, Blackhorn 3.20, Bone Dragon 8 m de largo, Ghidorah 10 m de alto), módulo de muro de `PSX_Dungeon` a 4 × 4 m.
- [x] **Paso 3: Verificar** con un script de herramienta que imprima la `AABB` de cada modelo instanciado; cada altura dentro de ±5 % de la tabla.
- [x] **Paso 4: Completar `docs/asset-status.md`** y la tabla de §7.8.
- [x] **Paso 5: Decidir reservas** — todo modelo que no importe en 2 h se marca `reemplazado` con su sustituto (§3).
- [x] **Paso 6: Commit** — `feat: import and normalize character and boss assets`

### Tarea 5 (C, tarde): Shader PSX y entorno base

**Archivos:**
- Ya existe: `shaders/psx/*.gdshader` y `shaders/psx/postprocess/*.gdshader` (Godot-PSX-Starter-kit portado a Godot 4; los 23 compilan en 4.7)
- Crear: `assets/materials/psx_base.tres`, `assets/environment/base_env.tres`, escena de postproceso con `pp_band_dither`

**Interfaces:**
- Produce: `psx_base.tres` = `ShaderMaterial` con `psx_lit.gdshader` (uniformes `albedoTex` con filtro nearest, `modulate_color` = tinte, `uv_scale`, `precision_multiplier` = cuánto tiemblan los vértices). `base_env.tres`: niebla de distancia gris-azulada, cielo con gradiente, luz ambiental tenue. Postproceso: `SubViewport` a baja resolución (p. ej. 320 × 240) mostrado en un `TextureRect` con `pp_band_dither.gdshader` (`dither_tex` = `psxdither.png`, `col_depth` 15).

- [x] **Paso 1: Shader**: portado del kit (no hace falta escribirlo).
- [x] **Paso 2: Aplicarlo** a todos los modelos de `scale_reference` con `base_env.tres`. *(Hecho en `scenes/levels/psx_test.tscn` con Kaelen y el esqueleto; `scale_reference` no se tocó. Para el resto basta `PsxTest.apply_psx(nodo)`.)*
- [x] **Paso 3: Verificar** *(captura de `psx_test` en ejecución: pixelado 320×240, bandas/dither y texturas correctas; falta compartirla)* — captura de `scale_reference` donde todos los modelos se ven con la misma paleta y textura pixelada; compartirla con el equipo.
- [x] **Paso 4: Commit** — `feat: add PSX shader and base environment`

**Fin del día 1 (integración):** pull de todos; B corre pruebas (todas pasan); A muestra la cápsula en `test_arena`; C muestra `scale_reference`.

---

# DÍA 2 — Combate y primer esbirro

Meta: se puede matar a un esbirro y morir ante él.

### Tarea 6 (A): Ataque, lock-on, daño y muerte de Kaelen + HUD

**Archivos:**
- Modificar: `scripts/player/player_controller.gd`, `scenes/player/kaelen.tscn`
- Crear: `scripts/player/lock_on.gd`, `scenes/ui/hud.tscn`, `scripts/ui/hud.gd`
- Prueba: `tests/test_player_combo.gd`, `tests/test_lock_on.gd`

**Interfaces:**
- Consume: `Hitbox`, `Hurtbox`, `Health`, `Stamina`, grupo `"lockable"` + `LockOnPoint`, `Events.player_damaged`, `Events.player_died`.
- Produce: `const COMBO_DAMAGE: Array[int] = [10, 10, 18]`, `const ATTACK_COST := 20.0`; `class_name LockOn extends Node` con `var target: Node3D`, `func toggle() -> void`, `func validate() -> void` (suelta objetivos liberados o a más de 15 m; 25 m si el objetivo está en grupo `"boss"`); el `CameraRig` usa pivote 2.5 m y distancia 6.5 m cuando `target` está en grupo `"boss"`. HUD: barras de vida y estamina arriba a la izquierda; nodo `BossBar` oculto con `func show_boss(name: String, health: Health) -> void`.

- [x] **Paso 1: Pruebas que fallan**
  - `test_combo_damage_sequence`: `Player.combo_damage(i)` devuelve 10, 10, 18 para i = 0, 1, 2 y 10 para i = 3 (vuelve a empezar).
  - `test_lock_on_drops_invalid_target`: con un `Node3D` asignado como `target` y luego liberado, `validate()` deja `target == null` sin error.
  - `test_lock_on_range`: objetivo a 16 m sin grupo `"boss"` → se suelta; en grupo `"boss"` a 16 m → se mantiene.
- [x] **Paso 2: Ejecutar** — FAIL.
- [x] **Paso 3: Implementar** combo (ventana para encadenar 0.4 s tras cada golpe), hitbox del mandoble (caja 0.2 × 0.2 × 1.4 m, capa 5, máscara 8) activada solo en la ventana de daño, estado `HURT` (0.4 s, interrumpe ataque), `DEAD` (emite `Events.player_died`), y el HUD conectado a `Health.changed` y `Stamina.changed`.
- [x] **Paso 4: Ejecutar pruebas** — pasan.
- [x] **Paso 5: Verificación manual** en `test_arena` con un muñeco (`StaticBody3D` + `Hurtbox` + `Health` 30): 3 golpes de combo lo matan (con el daño original 10 + 10 + 18 ≥ 30; hoy 20 + 20 ya mata al esbirro de 30); la estamina baja 20 por golpe; el lock-on gira la cámara hacia el muñeco.
- [x] **Paso 6: Commit** — `feat: add player combo, lock-on, death and HUD`

### Tarea 7 (B): Esbirro con máquina de estados y navegación

**Archivos:**
- Crear: `scripts/ai/minion.gd`, `scripts/ai/minion_brain.gd`, `scenes/enemies/minion_base.tscn`
- Prueba: `tests/test_minion_brain.gd`
- Modificar (pedido a A): agregar `NavigationRegion3D` capa 1 a `test_arena.tscn` — **A lo hace** en 10 min a pedido de B.

**Interfaces:**
- Consume: `AttackTokens`, `Health`, `Hitbox`, `Hurtbox`, grupo `"player"`.
- Produce:
  - `class_name MinionBrain extends RefCounted` (lógica pura): `enum State { IDLE, CHASE, CIRCLE, ATTACK, RECOVER, STUNNED, DEAD }`; `func next_state(state: State, ctx: Dictionary) -> State` con `ctx = {distance: float, sees_player: bool, has_token: bool, attack_finished: bool, recover_finished: bool, was_hit: bool, is_dead: bool}`; `static func can_see(from: Vector3, forward: Vector3, to: Vector3, radius := 12.0, fov_deg := 110.0) -> bool` (sin raycast; el raycast lo hace `minion.gd`).
  - `class_name Minion extends CharacterBody3D` en grupos `"enemy"` y `"lockable"`; `@export var cost := 1`; `@export var attack_range := 1.5`; `@export var move_speed := 3.5`; `@export var damage := 20`; al morir emite `Events.enemy_died(self, cost)` y libera su ficha.
  - `minion_base.tscn`: cápsula r 0.35 · alto 1.75 (capa 3), hurtbox r 0.40 · alto 1.80 (capa 8), hitbox esfera r 0.5 a 1.2 m al frente (capa 6, máscara 7), `NavigationAgent3D` capa 1 con evitación r 0.35, `LockOnPoint` a 1.3 m. Malla placeholder: cápsula roja.

- [x] **Paso 1: Pruebas que fallan**
  - `test_idle_to_chase_when_seen`; `test_chase_to_circle_without_token` (distancia ≤ 4 m y `has_token = false` → `CIRCLE`); `test_chase_to_attack_with_token` (distancia ≤ 1.5 y token → `ATTACK`); `test_attack_to_recover`; `test_hit_interrupts_to_stunned`; `test_dead_is_terminal` (desde cualquier estado con `is_dead` → `DEAD`, y de `DEAD` no sale).
  - `test_can_see_cone`: objetivo a 5 m al frente → true; a 5 m detrás → false; a 13 m al frente → false.
- [x] **Paso 2: Ejecutar** — FAIL.
- [x] **Paso 3: Implementar** `MinionBrain` y `minion.gd` (pide ficha al entrar en rango de 4 m; en `CIRCLE` orbita a 3.5 m; en `ATTACK` activa la hitbox 0.3 s tras 0.5 s de aviso; `RECOVER` 0.8 s; `STUNNED` 0.4 s; libera la ficha al salir de `ATTACK` y al morir).
- [x] **Paso 4: Ejecutar pruebas** — pasan.
- [x] **Paso 5: Verificación manual** — 4 esbirros en `test_arena`: solo 2 atacan a la vez, los demás rodean; se mueren con los combos de Kaelen; Kaelen muere tras 5 golpes de 20.
- [x] **Paso 6: Commit** — `feat: add minion FSM with navigation and attack tokens`

### Tarea 8 (C): Kaelen y Elysia procesadas + animaciones del Bone Dragon + bloqueo de la arena 1

**Archivos:**
- Crear: `assets/characters/kaelen/kaelen.glb` (`low-poly-woman-knight`, rig Mixamo), `assets/characters/kaelen/anims/*.glb` (Mixamo, *without skin*), `assets/characters/elysia/elysia.glb` (`ancient-elf-lady-psx`, estático sin rig)
- Crear: `assets/bosses/bonedragon/bonedragon.glb` con animaciones `idle`, `roar`, `bite`, `tail_sweep`, `stomp`, `death`
- Crear: `assets/minions/skeleton/skeleton.glb`, `assets/minions/knight/knight.glb` (rig Mixamo)
- Crear: `scenes/levels/arena_1.tscn` (bloqueo CSG según §6.3: 32 × 32 m, techo 8 m, 4 pilares, rejas, margen de cámara 3 m), **generado** por `scripts/tools/level_builder.gd`

**Interfaces:**
- Produce: nombres de animación exactos para Kaelen: `idle`, `walk`, `run`, `roll`, `attack_1`, `attack_2`, `attack_3`, `hurt`, `death`; para esbirros humanoides: `idle`, `walk`, `attack`, `hurt`, `death`. Lista real registrada en `docs/asset-status.md`.
- Produce: `arena_1.tscn` con un nodo vacío `Gameplay` donde se instancia `arena_1_gameplay.tscn` (de B).

- [x] **Paso 1:** Kaelen (`low-poly-woman-knight`): ya es low poly; solo aplicar escala y exportar FBX para Mixamo. Elysia (`ancient-elf-lady-psx`): **sin rig**; solo escalar a 1.60 m y exportar `elysia.glb` estático.
- [x] **Paso 2:** Mixamo: Kaelen, Skeleton y Knight riggeados y combinados (`_source/tools/build_characters.py`); Plague Arcanist y TheWrapper exportados (`export_multi_action.py`). Ver `docs/asset-status.md`.
- [x] **Paso 3:** Bone Dragon: 6 animaciones hechas por script (`_source/tools/animate_bonedragon.py`). Falta verificar que se reproducen en Godot.
- [x] **Paso 4:** Bloqueo de `arena_1.tscn` + capturas. Se genera con `level_builder.gd` junto con `exterior`, `arena_2` y `arena_3` (ver Tarea 14).
- [x] **Paso 5: Verificación** — cada GLB abre en Godot con las animaciones de la lista; Kaelen mide 1.70 m en `scale_reference`.
- [x] **Paso 6: Commit** — `feat: add processed Kaelen, Elysia, skeleton, knight and bone dragon animations`

**Fin del día 2:** se combate contra esbirros en `test_arena`. A cambia la cápsula por `kaelen.glb` si ya está.

---

# DÍA 3 — HITO: jefe 1 ganable y perdible desde el menú

### Tarea 9 (B): Sistema de jefes + Bone Dragon + gameplay de la arena 1

**Archivos:**
- Crear: `scripts/ai/boss_attack.gd`, `scripts/ai/boss_brain.gd`, `scripts/ai/boss.gd`, `scenes/bosses/boss_base.tscn`, `scenes/bosses/boss_bonedragon.tscn`, `resources/attacks/bonedragon_{bite,tail_sweep,stomp}.tres`, `scenes/levels/arena_1_gameplay.tscn`, `scripts/game/arena_config.gd`
- Prueba: `tests/test_boss_brain.gd`

**Interfaces:**
- Consume: componentes de combate, `Events`, `GameState`.
- Produce:
  - `class_name BossAttack extends Resource` — `@export var id: StringName`, `min_range: float`, `max_range: float`, `telegraph_time: float`, `active_time: float`, `recovery_time: float`, `base_weight: float`, `damage: int`, `animation: StringName`, `hitbox_path: NodePath`, `phase_min := 1`.
  - `class_name BossBrain extends RefCounted` — `static func score(attack: BossAttack, distance: float, last_attack_id: StringName, dodge_bias: float, phase: int) -> float`; `func choose(attacks: Array[BossAttack], distance: float, phase: int, rng: RandomNumberGenerator) -> BossAttack`; `func record_dodge(side: int) -> void` (−1 izquierda, +1 derecha; guarda las últimas 6); `var dodge_bias: float` (promedio, −1..1).
  - `class_name Boss extends CharacterBody3D` en grupos `"boss"` y `"lockable"`; `@export var display_name: String`; `@export var attacks: Array[BossAttack]`; `@export var max_health: int`; `var phase: int` (1 o 2); emite `Events.boss_phase_changed` al cruzar 50 % y `Events.boss_defeated` al morir.
  - `class_name ArenaConfig extends Resource` — `arena_id: int`, `base_budget: float`, `minion_scene: PackedScene`, `elite_scene: PackedScene`, `max_alive := 6`.
- Fórmula (spec §8.2): `score = base_weight × ajuste_distancia × (0.3 si id == last_attack_id, si no 1) × (1 + 0.5 × |dodge_bias| si el ataque es lateral) × (1.25 si phase == 2)`; `ajuste_distancia` = 1 dentro de `[min_range, max_range]`, 0 fuera. `choose` sortea ponderado entre los 2 de mayor puntaje; ataques con `phase_min > phase` quedan fuera.

- [x] **Paso 1: Pruebas que fallan**
  - `test_out_of_range_scores_zero`; `test_repeat_penalty` (mismo ataque como último → puntaje × 0.3); `test_phase2_multiplier` (× 1.25); `test_choose_never_returns_out_of_range`; `test_choose_only_from_top_two` (con 3 ataques válidos y semilla fija, en 200 sorteos el de menor puntaje nunca sale); `test_phase_min_filter`; `test_dodge_bias_average` (registrar +1, +1, −1 → 0.333).
- [x] **Paso 2: Ejecutar** — FAIL.
- [x] **Paso 3: Implementar** `BossBrain`, `Boss` (ciclo: elegir → aviso con decal en el piso del tamaño de la hitbox → activa → recuperación; fase 2 = +25 % velocidad de animación y de ataque), `boss_base.tscn` y `boss_bonedragon.tscn` con medidas de §7.4 (collider cápsula horizontal r 1.2 × 4 m; hurtboxes en torso, cabeza ×1.25 y 4 patas con `BoneAttachment3D`; navegación capa 2).
- [x] **Paso 4: Ejecutar pruebas** — pasan.
- [x] **Paso 5: `arena_1_gameplay.tscn`**: `PlayerStart`, `BossStart`, 6 `Marker3D` en grupo `"spawn_point"` sobre la capa 1, `NavigationRegion3D` capa 1 y 2 horneadas sobre la geometría de `arena_1`, rejas que se cierran al entrar (`Events.arena_entered`) y se abren con `Events.boss_defeated`; 4 esqueletos colocados a mano (el Orquestador llega el día 4).
- [x] **Paso 6: Verificación manual (hito)** — se puede matar al Bone Dragon (400 de vida) y morir ante él; a 200 cambia a fase 2; si Kaelen y el dragón mueren casi a la vez gana quien llegó primero a 0, y tras `boss_defeated` Kaelen no recibe daño.
- [x] **Paso 7: Commit** — `feat: add boss system and bone dragon fight`

### Tarea 10 (A): Menú principal, pausa, muerte/reaparición y flujo de `GameState`

**Archivos:**
- Completar: `scripts/game/game_state.gd` (B lo entrega a A al empezar el día 3)
- Crear: `scenes/ui/main_menu.tscn`, `scenes/ui/pause_menu.tscn`, `scenes/ui/death_screen.tscn`, `scenes/ui/transition.tscn`, scripts en `scripts/ui/`
- Prueba: `tests/test_game_state.gd`
- Pedido a B: `run/main_scene = res://scenes/ui/main_menu.tscn` en `project.godot`

**Interfaces:**
- Consume: `Events.player_died`, `Events.boss_defeated`.
- Produce: `GameState.LEVEL_SCENES: Array[String] = ["res://scenes/levels/exterior.tscn", "res://scenes/levels/arena_1.tscn", "res://scenes/levels/arena_2.tscn", "res://scenes/levels/arena_3.tscn"]` (el final ocurre dentro de `arena_3`)`; `func scene_for_level(level: int) -> String`; `transition.tscn` con `func fade_to(path: String) -> void` (fundido a negro 0.5 s). Kaelen se vuelve invulnerable al recibir `Events.boss_defeated`.

- [x] **Paso 1: Pruebas que fallan** — `test_max_hp_by_level` (0 → 100, 1 → 70, 2 → 40); `test_level_clamped` (`current_level` no pasa de 2 al calcular vida); `test_new_game_resets_level` (`start_new_game()` con nivel 2 → nivel 0).
- [x] **Paso 2: Ejecutar** — FAIL.
- [x] **Paso 3: Implementar** `GameState` (sin cargar escenas en las pruebas: separar `_change_scene(path)` para que las pruebas no lo llamen), menú principal (Iniciar, Créditos, Salir; foco inicial en Iniciar; navegable con teclado y mando), pausa (`get_tree().paused`, `process_mode = ALWAYS`, Continuar / Volver al menú / Salir; libera y recaptura el ratón), pantalla "HAS MUERTO" + fundido + `reload_current_arena()`.
- [x] **Paso 4: Ejecutar pruebas** — pasan.
- [x] **Paso 5: Verificación manual** — desde el menú se entra a `arena_1`, se pausa y continúa, se muere y reaparece con el jefe a vida completa y sin esbirros sobrantes; "Volver al menú" desde la pausa no deja el juego pausado.
- [x] **Paso 6: Commit** — `feat: add main menu, pause, death and game flow`

### Tarea 11 (C): Arte de la arena 1 + animaciones de Ghidorah

**Archivos:**
- Crear: `assets/environment/kit/*.tscn` (piezas de `PSX_Dungeon` a 4 m con colisión), `assets/environment/kit/dungeon_kit.meshlib`
- Modificar: `scenes/levels/arena_1.tscn` (reemplazar CSG por `GridMap` + piezas; decoración mínima)
- Ya existe: `assets/bosses/blackhorn/blackhorn.glb` (jefe 2, 10 animaciones; ver `docs/asset-status.md`)
- Ya existe: `assets/bosses/ghidorah/ghidorah.glb` (9.1k triángulos; `idle`, `roar`, `bite`, `tail_sweep`, `beam`, `death`)

- [x] **Paso 1:** importar piezas del kit con escala de 4 m y colisión (caja para muros/pilares, trimesh para pisos/escaleras); exportar `MeshLibrary` (puede usarse `export_mesh_library`).
- [x] **Paso 2:** el mismo `level_builder.gd` pinta un `GridMap` en lugar de las cajas (mismo plano, otra salida), sin mover la posición de pilares, rejas ni límites (B ya horneó la navegación sobre ellos; si cambian, avisar a B para rehornear).
- [x] **Paso 3:** Ghidorah: reducido a 9.1k triángulos y 6 animaciones por script (`_source/tools/animate_ghidorah.py`).
- [x] **Paso 4: Verificación** — `arena_1` con arte se juega igual que el bloqueo; Blackhorn y Ghidorah reproducen todas sus animaciones en `scale_reference`.
- [x] **Paso 5: Commit** — `feat: arena 1 art pass and ghidorah animations`

**Resultado T11:** arena 1 con `GridMap` verificada (colisiones, navegación, FPS ≈ 60 con vsync); material del kit `kit_std.tres`; Blackhorn y Ghidorah reproducen todos sus clips. Ghidorah medía 4.15 m (no 3.5 m) y sus colas colgaban bajo el suelo: corregido en `animate_ghidorah.py`.

**Fin del día 3 — HITO:** menú → arena 1 → ganar y perder contra el Bone Dragon. **Si no se cumple**, aplicar los recortes de la spec §15 antes de seguir.

---

# DÍA 4 — Orquestador, jefes 2 y 3, arenas 2 y 3

### Tarea 12 (B): Orquestador + overlay de depuración

**Archivos:**
- Crear: `scripts/ai/orchestrator_model.gd`, completar `scripts/ai/orchestrator.gd`, `scenes/ui/debug_overlay.tscn`, `scripts/ai/debug_overlay.gd`
- Modificar: `scenes/levels/arena_1_gameplay.tscn` (quitar esqueletos a mano, usar `ArenaConfig`)
- Prueba: `tests/test_orchestrator_model.gd`

**Interfaces:**
- Consume: `Events.player_damaged`, `Events.enemy_died`, `Events.boss_phase_changed`, grupo `"spawn_point"`, `ArenaConfig`.
- Produce: `class_name OrchestratorModel extends RefCounted` — `enum Phase { BUILD_UP, PEAK, RELAX }`; `var intensity: float` (0–100); `var phase: Phase`; `func on_player_damaged(amount: int) -> void` (+ amount × 1.5); `func update(delta: float, ctx: Dictionary) -> int` (devuelve presupuesto a gastar ahora, 0 si no se genera) con `ctx = {hp_ratio: float, enemies_near: int, enemies_alive: int, time_since_hit: float, boss_phase: int, boss_special: bool}`; `func reset() -> void`; `func budget_for(ctx: Dictionary, base_budget: float) -> int`.
- Reglas exactas (spec §8.3): sube +5/s si `hp_ratio < 0.3`, +2/s por enemigo a < 5 m; baja −8/s, −15/s si `enemies_near == 0`; `BUILD_UP → PEAK` con intensidad ≥ 80; `PEAK → RELAX` tras 5 s; `RELAX` dura entre 10 y 20 s y vuelve a `BUILD_UP` solo si intensidad < 30; `hp_ratio < 0.25` fuerza `RELAX`; `boss_special` → no genera; presupuesto = `base_budget × factor_desempeño (0.6–1.4) × (1.5 si boss_phase == 2)`; esbirro 1, élite 3; máximo 6 vivos. Puntos de aparición: fuera del cono de cámara y a > 8 m de Kaelen.

- [x] **Paso 1: Pruebas que fallan** — `test_damage_raises_intensity` (20 de daño → +30); `test_natural_decay` (intensidad 50, `update(1.0)` sin enemigos cerca → 35); `test_build_up_to_peak_at_80`; `test_peak_lasts_5s`; `test_relax_waits_for_low_intensity`; `test_low_hp_forces_relax`; `test_no_spawn_during_boss_special`; `test_budget_phase2_multiplier`; `test_budget_respects_max_alive` (5 vivos → presupuesto ≤ 1); `test_reset_returns_to_build_up`.
- [x] **Paso 2: Ejecutar** — FAIL.
- [x] **Paso 3: Implementar** el modelo y el autoload (genera esbirros/élites en los `spawn_point` válidos; `begin_arena` lo llama `arena_N_gameplay` con `Events.arena_entered`; `end_arena` con `boss_defeated` o `player_died` → `reset()` + liberar esbirros + `AttackTokens.reset()`).
- [x] **Paso 4: Ejecutar pruebas** — pasan.
- [x] **Paso 5: Overlay F3** — muestra intensidad, fase, presupuesto, vivos y fichas (`get_debug_info()` + `AttackTokens.holders_count()`); F5 salta al siguiente nivel; F6 alterna invulnerabilidad de Kaelen.
- [x] **Paso 6: Verificación manual** — en `arena_1` la intensidad oscila (no se queda en 0 ni en 100), aparecen oleadas fuera de cámara, y al bajar de 25 % de vida dejan de aparecer.
- [x] **Paso 7: Commit** — `feat: add orchestrator and debug overlay`

**Resultado T12:** hecha. Overlay F3/F5; F6 ya existía en `player_controller.gd`. Ciclo de oleadas con ventana del jefe, `Minion.alert()` y puntos de aparición por niveles (ver "Estado actual"). Reemplaza los esbirros colocados a mano de `arena_1_gameplay`.

### Tarea 13 (A): Jefes 2 (Blackhorn) y 3 (Ghidorah)

**Archivos:**
- Crear: `scenes/bosses/boss_blackhorn.tscn`, `scenes/bosses/boss_ghidorah.tscn` (heredan de `boss_base.tscn`), `resources/attacks/blackhorn_{pounce,slam,charge}.tres`, `resources/attacks/ghidorah_{bite,tail_sweep,beam}.tres`

**Interfaces:**
- Consume: `Boss`, `BossAttack` (Tarea 9) — **sin modificar sus scripts**; si falta algo, pedirlo a B.
- Medidas (§7.4): Blackhorn cápsula r 0.70 · alto 3.20, hurtbox r 0.80 · alto 3.0, garras esferas r 0.6 en las manos, zarpazo caja 2 × 2 × 4 m, golpe al suelo esfera r 3, embestida caja 1.5 × 2.5 × 3 m, navegación capa 2, vida 500; `roar` como transición a fase 2. Ghidorah cápsula torso r 2.5 · alto 6 + patas, cabezas solo con hurtbox (esferas r 1.0) y bajan al suelo durante `bite`, mordida esfera r 1.5, cola caja 6 m, rayo 1.5 × 1.5 × 20 m con aviso en línea, navegación capa 2, vida 600, `LockOnPoint` en el torso a media altura.

- [x] **Paso 1:** crear las escenas y los 6 recursos de ataque con rangos coherentes (Blackhorn: `attack_slam` 0–4 m, `attack_pounce` 2–7 m, `charge` 8–16 m solo fase 2; Ghidorah: `bite` 0–6 m, `tail_sweep` 0–8 m, `beam` 8–20 m).
- [x] **Paso 2: Verificación manual** en `test_arena` (cambiando el jefe instanciado): ambos jefes se pueden matar y matan a Kaelen; las cabezas de Ghidorah solo reciben golpes al bajar en `bite`; la cámara con lock-on encuadra a Ghidorah sin meterse en su cuerpo.
- [x] **Paso 3: Commit** — `feat: add blackhorn and ghidorah bosses`

**Resultado T13:** hecha. Blackhorn (500 PV) y Ghidorah (600 PV) con 6 ataques, `arena_2_gameplay` y `arena_3_gameplay`. Los ataques que `Boss` no soportaba (avance en ACTIVE, ataques a distancia, clip de desplazamiento, choque con Kaelen) se integraron en `boss.gd`/`boss_attack.gd`/`boss_brain.gd`. Ghidorah a ×1.95. Las cabezas solo reciben golpes en `bite`.

### Tarea 14 (C): Bloqueo y arte de arenas 2 y 3 + exterior

**Archivos:**
- Crear: `scripts/tools/level_builder.gd` (generador paramétrico; se ejecuta con `godot --headless --path . -s res://scripts/tools/level_builder.gd`)
- Genera: `scenes/levels/exterior.tscn`, `arena_1.tscn`, `arena_2.tscn` (octogonal, 24 m, techo 8 m, 6 columnas), `arena_3.tscn` (40 × 40 m, sin techo, pilares rotos, puerta bloqueada `GateExit` → pasillo ~20 m → sala de Elysia con altar, Elysia y `EndingTrigger`)
- ~~`island_intro.tscn` y `floating_island`~~: reemplazados por `exterior.tscn` con `float-islands` (§6.2).

- [x] **Paso 1:** generar el bloqueo CSG de las 4 escenas con nodo `Gameplay` vacío; las escenas `arena_N_gameplay.tscn` se crean aparte (hecho en T9 y T13).
- [x] **Paso 2:** exterior según §6.2: `float-islands`, sendero con colisión invisible, fachada del templo con `PSX_Dungeon`, cielo y niebla.
- [x] **Paso 3: Verificación** — `exterior` se recorre de inicio a puerta en 1–2 min sin caer al vacío; el pasillo y la sala de Elysia de `arena_3` son transitables; ≥ 60 FPS en la PC más lenta.
- [x] **Paso 4: Commit** — `feat: add level builder, arenas blockout and exterior`

**(B, final del día 4):** `arena_2_gameplay.tscn` y `arena_3_gameplay.tscn` con navegación, spawns y `ArenaConfig` (arena 2: Plague Arcanist; arena 3: TheWrapper + élite Aura Battler si existe).

---

**Resultado T14:** hecha y commiteada en `feat/aza`. Arenas 2 y 3 y exterior con arte de kit; `EndingCam1/2` ya no son `current`, pero el override de cámara de `arena_3_gameplay.tscn` se mantiene (ver "Riesgos"); navegación solo a la altura del suelo; `spawn_point` recolocados; sendero del exterior rodea la nariz de la isla. Pruebas nuevas en `tests/test_level_generator.gd`.

# DÍA 5 — Partida completa

### Tarea 15 (A): Flujo completo, final y créditos

**Archivos:**
- Modificar: `scripts/game/game_state.gd`
- Crear: `scenes/ui/credits.tscn`, `scripts/ui/credits.gd`, `scripts/game/ending_director.gd`
- Ya en `arena_3.tscn` (generada): nodo `Ending` con `EndingTrigger` (`Area3D`), cámaras fijas `EndingCam1`/`EndingCam2` y Elysia estática (la T15 le agrega el `Tween` de respiración y el fundido del abrazo desde el gameplay). **No hay escena `ending` aparte.**

**Interfaces:**
- Produce: `ending_director.gd` (se adjunta desde `arena_3_gameplay.tscn`, no en `arena_3.tscn`, que es generada; se dispara con `EndingTrigger.body_entered`) con `func play() -> void`: corta entre `EndingCam1`–`EndingCam2` con texto en pantalla y termina en `credits.tscn`. `credits.tscn` muestra el texto de `res://assets/credits.txt` (C lo escribe con autores y licencias).

- [x] **Paso 1:** `ExitTrigger` de `exterior` → `advance_level()`; `boss_defeated` → espera 3 s → `GateExit` abierta → `ExitTrigger` → `advance_level()` (en la arena 3 Kaelen recorre el pasillo hasta `EndingTrigger`); vida máxima de Kaelen = `GameState.get_player_max_hp()` al entrar a cada arena.
- [x] **Paso 2:** final y créditos (botón "Volver al menú").
- [ ] **Paso 3: Verificación manual** — partida completa menú → exterior → 3 jefes → pasillo → Elysia → créditos → menú usando F6 (invulnerable) y F5; luego otra muriendo una vez por jefe: la vida máxima es 100, 70 y 40.
- [x] **Paso 4: Commit** — `feat: complete game flow, ending and credits`

**Resultado T15:** hecho y commiteado en la rama `feat/aza` (varios commits `feat:` y `test:`). Verificado en Godot (2026-10-15) con un recorrido automático: el `ExitTrigger` del exterior lleva a la arena 1; vida máxima 100/70/40; en la arena 3 el final activa `EndingCam1` y luego `EndingCam2`, bloquea la pausa, coloca a Kaelen en `KaelenEndPoint` y a los ~15 s carga `credits.tscn`. Falta la partida completa a mano (Paso 3). Decisiones:
- El `ExitTrigger` se movió a `scripts/game/level_gameplay.gd` (señal `exit_reached`, `@export exit_advances_level` y virtual `_can_exit()`). El exterior avanza a la arena 1 al cruzarlo. `arena_gameplay.gd` solo sobrescribe `_can_exit()` (arena despejada).
- `arena_3_gameplay.tscn` tiene `exit_advances_level = false`, para que el pasillo no salte el final, y el nodo `EndingDirector`.
- `GameState.cutscene_active` bloquea la pausa durante el final y se limpia al cambiar de escena. `player_controller.gd` añade `set_cutscene()`, `is_cutscene()` y `face_point()` (invulnerable y sin control).
- Créditos: `credits.tscn` con auto-scroll, rueda y flechas, botón "Volver al menú" y Esc.
- Pruebas nuevas (incluidas en las 145/145): `tests/test_level_exit.gd`, `tests/test_ending_director.gd`, `tests/test_player_cutscene.gd` y `test_cutscene_blocks_pause` en `tests/test_game_state.gd`.

### Tarea 16 (B): Esbirros por nivel, élites y ajuste de jefes

**Archivos:**
- Crear: `scenes/enemies/minion_skeleton.tscn`, `minion_knight_elite.tscn`, `minion_plague.tscn`, `minion_wrapper.tscn`, `minion_aura_elite.tscn` (opcional), heredando de `minion_base.tscn`

- [x] **Paso 1:** variantes con modelos y medidas de §7.4 (élite: `cost = 3`, vida 90, daño 30, tinte distinto). Aura Battler: flota a 0.5 m, se mueve con tweens, navegación capa 2.
- [x] **Paso 2:** conectar animaciones (`idle`/`walk`/`attack`/`hurt`/`death`) y sonidos vía `AudioManager.play_sfx_3d`.
- [x] **Paso 3: Verificación manual** — cada arena genera su tipo de esbirro; el overlay muestra costos correctos (élite = 3).
- [x] **Paso 4: Commit** — `feat: add per-level minions and elites`

**Resultado T16:** hecho y commiteado en la rama `feat/aza`. `minion.gd` admite `model_scene`, `tint`, clips `anim_*`, `weapon_scene` (en `BoneAttachment3D`, acepta `mixamorig:` o `mixamorig_` y compensa la escala del hueso) y `sfx_*`. Variantes por arena: Skeleton + Knight élite (espada), Plague + Plague élite (tinte verdoso), Wrapper (sin clip de muerte, cae con un tween) + Straw Reaper élite (2026-10-15; sustituye al Wrapper élite con tinte: modelo propio con hoz, exportado con `export_multi_action.py -- straw_reaper`, 8 clips nombrados). Verificado en Godot: cada arena genera su esbirro y su élite (coste 3, vida 90, daño 30), alturas por huesos 1.60/2.07/1.85/1.98 m, espada a escala 1. El Aura Battler no se usa (está en `_source/models/` pero nunca se exportó a `assets/`). Pendiente: revisar en juego las animaciones de ataque/muerte.

### Tarea 17 (C): Audio completo

**Archivos:**
- Completar: `scripts/audio/audio_manager.gd`
- Crear: `assets/audio/bgm/*.ogg`, `assets/audio/sfx/**` (solo los usados, convertidos de `_source`), `assets/credits.txt`

**Interfaces:**
- Produce: `AudioManager` con buses `Music`/`SFX`/`UI`; fundido de música; variación de tono ±10 %; impacto de espada desde `Hitbox.sfx_impact` (una vez por golpe, no por hurtbox; `sfx_impact_metal` para `metal`), sin escuchar `Events.hit_landed` para no sonar doble; baja 10 dB la música en pausa.
- Asignación de música (cambiada el 2026-10-15; sustituye a la de spec §11.3): menú `sadness piano4`, exterior ambiente `Forest Night` (TomMusic), jefe 1 `ancient creature battle`, jefe 2 `hellhound battle`, jefe 3 `LVS04_10_Battlefield_bpm180_loop`, final con Elysia y créditos `celtic melancholy`. La música del jefe arranca cuando el jefe detecta a Kaelen y se apaga con fundido al derrotarlo.

- [x] **Paso 1:** copiados a `assets/audio/` (bgm, `sfx/{player,bosses,elites,ui,ambient}`; mp3/ogg nativos, wav para UI; 43 archivos en LFS). Bucle activado en las 6 BGM y la antorcha (solo `boss3_battlefield_loop.ogg` es un bucle limpio de origen).
- [x] **Paso 2:** `AudioManager` (fundido, pool de reproductores 3D, ±10 % de tono, música −10 dB en pausa, sonidos de UI enganchados a todos los botones) y música por escena. Variantes con `AudioStreamRandomizer` en `resources/audio/`. Pasos cada 2 m (`FOOTSTEP_STRIDE`), piedra en arenas y tierra en el exterior. Antorchas: `AudioStreamPlayer3D` creado en tiempo de ejecución en cada luz de `Level/Torches` (máx. 8, 9 m). Exports nuevos: `Boss.sfx_hurt/phase2/death`, `BossAttack.sfx_active/sfx_hit`, `Minion.sfx_spawn`, `Player.sfx_swing/footstep_stream`, `LevelGameplay.level_music/footstep_stream/torch_loop`, `ArenaGameplay.boss_music`, `EndingDirector.music`. Pruebas: `tests/test_audio.gd`.
- [x] **Paso 3:** `assets/credits.txt` con los packs de audio usados. Por confirmar: licencia de TomMusic y autor/licencia de las pistas BGM salvo Blazing Honor (que ya no se usa).
- [x] **Paso 4: Verificación manual** — cada escena suena con su pista; pasos, swings, impactos, rugidos y menús suenan; la pausa baja la música. *Hecho por el equipo jugando con altavoces el 2026-10-15.*
- [x] **Paso 5: Commit** — commits `977ade5`…`0b5d9da` en `feat/aza`.

**Cierre T17 (2026-10-15):** tarea completa. Los 5 pasos están hechos; la escucha con altavoces la hizo el equipo jugando. La lista de sonidos faltantes de abajo queda como referencia para la T18.

**Asignación de SFX (2026-10-15):** rayo de Ghidorah `Dragon_FireBreath4` (sale de la boca) e impacto `Spell Impact 1`; rugido de fase 2 `Monster_Roar22/14/12` y muerte `Monster_LongGrowl3/1/4` (Bone Dragon / Blackhorn / Ghidorah); daño de jefes y esbirros `Monster_Grunt1/3/4/6/7/8` al azar; Knight élite `Dinosaur_Shriek1` / `Monster_Groan1` / `Leviathan_Growl1` (aparecer / daño / muerte); Straw Reaper `Monster_Growl19` / `Dinosaur_Shriek2` / `Monster_Rumble1`; espada `Sword Attack 1–3` (swing), `Sword Impact Hit 1–3` (impacto), `Sword Blocked 1–3` (metal); pasos `Stone Run 2` y `Dirt Run 3`; antorcha `Torch Loop`; UI del pack Be Not Afraid UI (`--Unholy`).

**Sonidos faltantes (para la T18):** ataque y muerte de esbirros normales y sus pasos; Kaelen recibe golpe, muere, rueda y recupera aliento; avisos y ataques de los jefes (mordida, cola, pisotón, embestida, salto, golpe) y sus pasos; aparecer/muerte/ataque propios del Plague élite (hoy usa los de esbirro normal); ambiente de las arenas, pantalla de muerte y apertura de rejas. El reparto de los sets de élite (Knight = set 1, Straw Reaper = set 2) y el `Dinosaur_Shriek2` del Straw Reaper están pendientes de confirmar.

---

# DÍA 6 — Pulido y prueba externa

### Tarea 18 (los 3): Pulido por área
- **A:**
  - [x] Pausa de impacto 60 ms al acertar (40 ms al recibir daño), `Engine.time_scale` restaurado siempre (fin, pausa, muerte, cambio de escena, salida del árbol), sin apilarse: `scripts/combat/hit_stop.gd`; prueba `tests/flow/hit_feedback_flow.tscn`.
  - [x] Parpadeo de material 0,1 s al recibir golpe (blanco en enemigos, rojo en Kaelen) con un uniform del shader `psx_lit`: `scripts/combat/hit_flash.gd`.
  - [x] Ajuste de cámara: sacudida con golpes de >= 15 % de vida y brazo más largo con jefes enormes lejanos.
  - [x] Menú de opciones (volumen por bus, sensibilidad, pantalla completa, `user://settings.cfg`).
  - [x] Frasco de curación (justicia del juego): 10 usos por nivel, 38 % de la vida máxima en 0,9 s, acción `heal` (R / Y, reasignable), contador en el HUD; ver diseño §4 y `tests/test_heal.gd`.
- **B:**
  - [x] Balance con el overlay F3: `scripts/tools/orchestrator_sim.gd` muestra que la intensidad oscila en las 3 arenas; daño escalado por vida máxima para que la arena 3 llegue al pico (ver diseño §8.3).
  - [ ] Prueba con 2 personas externas y registro de dónde mueren (manual).
- **C:**
  - [x] Iluminación por arena (§6.3): nodo `Mood` en cada `arena_N_gameplay.tscn`.
  - [x] Filtro de color por jefe derrotado (tinte con fundido).
  - [x] Sonidos faltantes (§11.4).
  - [ ] Decoración de arenas (pendiente; la generación de niveles la lleva otro cambio).
- [ ] **Verificación:** 2 personas externas juegan la partida completa; se anotan los problemas en `docs/playtest.md`.
- [ ] **Commit** por persona.

# DÍA 7 — Congelación y entrega

### Tarea 19 (los 3): Cierre
- [ ] **Congelación:** no se agregan funciones; solo arreglos de la lista de `docs/playtest.md`, priorizados por B.
- [ ] **Exportar** Windows (A) y Web (opcional, A); probar el ejecutable en una PC que no sea de desarrollo.
- [ ] **Checklist final** (spec §16): menú → exterior → 3 jefes → pasillo → Elysia → créditos → menú, muriendo al menos una vez por jefe y usando la pausa; todas las pruebas pasan.
- [ ] **Créditos** revisados contra las licencias (C).
- [ ] **Commit y tag** `v1.0`.

---

## Resumen por persona y día

| Día | A — Jugador e interfaz | B — IA y enemigos | C — Arte, escenarios y sonido |
|---|---|---|---|
| 1 | T3 Kaelen-cápsula, cámara, rodada, `test_arena` | T1 Contrato (primera hora) · T2 Componentes + fichas | T4 Escalas e importación · T5 Shader PSX |
| 2 | T6 Combo, lock-on, muerte, HUD | T7 Esbirro FSM + navegación | T8 Kaelen/Elysia/esbirros Mixamo, animaciones Bone Dragon, bloqueo arena 1 |
| 3 | T10 Menús, pausa, muerte, `GameState` | T9 Sistema de jefes + Bone Dragon + gameplay arena 1 | T11 Arte arena 1, animaciones Ghidorah |
| 4 | T13 Jefes Blackhorn y Ghidorah | T12 Orquestador + overlay · gameplay arenas 2 y 3 | T14 Arenas 2 y 3, isla |
| 5 | T15 Flujo completo, final, créditos | T16 Esbirros por nivel y élites | T17 Audio completo |
| 6 | Pulido combate y opciones | Balance y prueba externa | Decoración e iluminación |
| 7 | Exportar | Arreglos priorizados | Créditos y licencias |
