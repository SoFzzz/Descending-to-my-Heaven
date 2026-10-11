# Descending to my Heaven — Plan de trabajo (7 días)

> **Para agentes:** SUB-SKILL REQUERIDA: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea. Los pasos usan casillas (`- [ ]`) para seguimiento.

**Objetivo:** un boss rush 3D estilo PSX en Godot, jugable de principio a fin (menú → isla → 3 jefes → Elysia → créditos), construido por 3 personas en paralelo sin pisarse.

**Arquitectura:** componentes pequeños reutilizables (`Health`, `Stamina`, `Hitbox`, `Hurtbox`) usados por Kaelen, esbirros y jefes; autoloads (`Events`, `GameState`, `AttackTokens`, `Orchestrator`, `AudioManager`) como contrato entre personas; cada arena separada en una escena de **arte** (dueño C) y una escena de **gameplay** (dueño B) para que nadie edite el mismo archivo. La lógica de IA y combate vive en clases puras testeables sin escena.

**Stack:** Godot 4.7.2 (GDScript, renderizador Compatibility), Blender 5.2 + Mixamo, Git LFS. MCP de Godot y Blender para automatizar importación y modelado.

**Spec:** [2026-10-10-descending-to-my-heaven-design.md](2026-10-10-descending-to-my-heaven-design.md)

## Restricciones globales

- Godot **4.7.2**, GDScript con tipos estáticos (`var x: int`), renderizador `gl_compatibility`. 1 unidad = 1 metro.
- Valores de combate exactos de la spec §4: vida Kaelen 100/70/40 por nivel; estamina 100, regenera 30/s tras 0.6 s; costo rodar 25, atacar 20; invulnerabilidad 0.35 s de 0.6 s de rodada; daño Kaelen 10/10/18; vida esbirro 30; vida jefes 400/500/600; fase 2 al 50 %.
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
3. **Arena = dos escenas:** `scenes/levels/arena_N.tscn` (arte, dueño C) instancia a `scenes/levels/arena_N_gameplay.tscn` (gameplay, dueño B). C nunca coloca enemigos; B nunca mueve muros.
4. **Entrega de modelos:** C exporta a `assets/<categoría>/<nombre>/<nombre>.glb` y avisa en el chat del equipo con la lista de animaciones. Quien usa el modelo lo instancia; **no** lo edita.
5. **Git:** trabajar en `main` con commits pequeños; antes de cada `push` ejecutar `git pull --rebase`. Correr las pruebas antes de hacer push.
6. **Sincronización:** 10 min al inicio del día (qué hace cada uno) y 20 min al final (integración y prueba juntos).
7. Las firmas de la sección "Contrato" no se cambian sin avisar a los otros dos.

### Dueños de archivos

| Dueño | Archivos |
|---|---|
| **A — Jugador e interfaz** | `scripts/player/*`, `scenes/player/*`, `scenes/ui/{main_menu,pause_menu,hud,credits,death_screen,options_menu,transition}.tscn` + sus scripts en `scripts/ui/`, `scenes/levels/test_arena.tscn`, `scenes/bosses/boss_malenia.tscn`, `scenes/bosses/boss_ghidorah.tscn`, `resources/attacks/malenia_*.tres`, `resources/attacks/ghidorah_*.tres`, `scripts/game/game_state.gd` (desde el día 3), `scripts/game/ending_director.gd` |
| **B — IA y enemigos** | `project.godot`, `scripts/game/events.gd`, `scripts/combat/*`, `scripts/ai/*`, `scenes/enemies/*`, `scenes/bosses/boss_base.tscn`, `scenes/bosses/boss_bonedragon.tscn`, `resources/attacks/bonedragon_*.tres`, `scenes/levels/arena_*_gameplay.tscn`, `scenes/ui/debug_overlay.tscn`, `tests/*`, `docs/playtest.md` |
| **C — Arte, escenarios y sonido** | `assets/**`, `shaders/*`, `scenes/levels/{scale_reference,island_intro,arena_1,arena_2,arena_3,ending}.tscn`, `assets/environment/base_env.tres`, `scripts/audio/*`, `docs/asset-status.md`, sección §7.8 del documento de diseño |

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
func start_new_game() -> void             # level 0 → island_intro
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

- [ ] **Paso 1: Escribir el corredor `tests/run_tests.gd`**

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

- [ ] **Paso 2: Escribir `tests/test_case.gd` y una prueba de humo** `test_smoke.gd::test_runner_works` con `assert_eq(1 + 1, 2)`. Todo archivo de prueba empieza con `extends TestCase`; las pruebas que crean nodos los liberan con `free()` al final.

- [ ] **Paso 3: Ejecutar el comando de pruebas** — Esperado: `1/1 passed`, código 0. Cambiar temporalmente a `assert_eq(1 + 1, 3)` y confirmar `FAIL` y código 1; revertir.

- [ ] **Paso 4: Crear los stubs del Contrato y registrarlos como autoloads** en `project.godot` (`Events`, `GameState`, `AttackTokens`, `Orchestrator`, `AudioManager`), más el mapa de entradas.

- [ ] **Paso 5: Verificar** — abrir el proyecto en Godot sin errores en el panel *Output*; el comando de pruebas sigue en `1/1 passed`.

- [ ] **Paso 6: Commit y push inmediato** (los otros dos esperan esto)

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

- [ ] **Paso 1: Escribir las pruebas que fallan**

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

- [ ] **Paso 2: Ejecutar pruebas** — Esperado: FAIL (clases no definidas).
- [ ] **Paso 3: Implementar los cuatro componentes y `AttackTokens`.** `AttackTokens` guarda los dueños en un `Array` y descarta los `!is_instance_valid` antes de contar. `Hurtbox.receive_hit` usa `roundi(amount * damage_multiplier)`.
- [ ] **Paso 4: Ejecutar pruebas** — Esperado: todas pasan.
- [ ] **Paso 5: Commit** — `feat: add combat components and attack tokens`

### Tarea 3 (A): Kaelen-cápsula, cámara y rodada en `test_arena`

**Archivos:**
- Crear: `scenes/levels/test_arena.tscn` (piso CSG 32×32 m, 4 pilares 1.2 m × 8 m, paredes invisibles; capa `world`)
- Crear: `scenes/player/kaelen.tscn`, `scripts/player/player_controller.gd`, `scripts/player/camera_rig.gd`
- Prueba: `tests/test_player_roll.gd`

**Interfaces:**
- Consume: `Health`, `Stamina`, `Hurtbox` (Tarea 2; si aún no están, usar stubs locales y reemplazar al hacer pull).
- Produce: `class_name Player extends CharacterBody3D` en grupo `"player"`, con hijos `Health`, `Stamina`, `Hurtbox` (capa 7), `CameraRig`; `enum State { MOVE, ROLL, ATTACK, HURT, DEAD }`; `var state: State`; `func is_invulnerable() -> bool`; constantes `ROLL_DURATION := 0.6`, `ROLL_IFRAME_START := 0.05`, `ROLL_IFRAME_END := 0.40`, `ROLL_COST := 25.0`.
- Medidas: collider cápsula r 0.35 · alto 1.70 (capa 2, máscara 1|3|4); hurtbox r 0.30 · alto 1.50; cámara pivote 1.5 m, `spring_length` 4 m, FOV 70°, margen 0.2, máscara del `SpringArm3D` solo capa 1.

- [ ] **Paso 1: Prueba que falla** — `test_player_roll.gd`:
  - `test_iframes_window`: `Player.iframes_active_at(t)` es falso en 0.0, verdadero en 0.05 y 0.30, falso en 0.45 (ventana de 0.35 s).
  - `test_roll_needs_stamina`: con `stamina.current = 0`, `try_roll()` devuelve false y `state` sigue `MOVE`.
- [ ] **Paso 2: Ejecutar** — Esperado: FAIL.
- [ ] **Paso 3: Implementar** `static func iframes_active_at(t: float) -> bool`, `func try_roll() -> bool`, movimiento relativo a la cámara (velocidad 5 m/s caminar, 7 m/s rodada), gravedad, giro suave hacia la dirección de movimiento, y `camera_rig.gd` (órbita con ratón, captura del cursor).
- [ ] **Paso 4: Ejecutar pruebas** — Esperado: pasan.
- [ ] **Paso 5: Verificación manual** — F6 sobre `test_arena.tscn`: la cápsula camina, rueda, no atraviesa pilares; la cámara se acerca al chocar con un pilar y no atraviesa paredes.
- [ ] **Paso 6: Commit** — `feat: add player capsule with camera and roll`

### Tarea 4 (C): Escalas, importación y estado de assets

**Archivos:**
- Crear: `scenes/levels/scale_reference.tscn`, `docs/asset-status.md`
- Crear: `assets/<categoría>/<nombre>/` con los GLB/FBX importados y su `license.txt`
- Modificar: tabla de §7.8 del documento de diseño

**Interfaces:**
- Produce: `docs/asset-status.md` con una fila por modelo: ruta en `assets/`, factor de escala, altura medida, lista exacta de animaciones, estado (`listo` / `falta rig` / `falta animación` / `reemplazado`).

- [ ] **Paso 1: Importar** los 11 modelos del reparto (§3 de la spec) a `assets/`. Los FBX con escalas internas raras (knight, Malenia, skeleton, bonedragon, TheWrapper, woman knight) se abren en Blender vía MCP, se aplica escala y se exportan a GLB.
- [ ] **Paso 2: Armar `scale_reference.tscn`** — grilla de 1 m, cápsula de 1.70 m, cada modelo a su altura de la tabla §7.4 (Kaelen 1.70, Elysia 1.60, Skeleton 1.75, Knight 2.10, Plague Arcanist 1.80, TheWrapper 2.00, Aura Battler 3.00, Malenia 2.60, Bone Dragon 8 m de largo, Ghidorah 10 m de alto), módulo de muro de `PSX_Dungeon` a 4 × 4 m.
- [ ] **Paso 3: Verificar** con un script de herramienta (o el MCP de Godot) que imprima la `AABB` de cada modelo instanciado; cada altura dentro de ±5 % de la tabla.
- [ ] **Paso 4: Completar `docs/asset-status.md`** y la tabla de §7.8.
- [ ] **Paso 5: Decidir reservas** — todo modelo que no importe en 2 h se marca `reemplazado` con su sustituto (§3).
- [ ] **Paso 6: Commit** — `feat: import and normalize character and boss assets`

### Tarea 5 (C, tarde): Shader PSX y entorno base

**Archivos:**
- Crear: `shaders/psx.gdshader`, `assets/materials/psx_base.tres`, `assets/environment/base_env.tres`

**Interfaces:**
- Produce: `ShaderMaterial` con uniformes `albedo_texture: sampler2D` (filtro nearest), `tint: vec4 = vec4(1.0)`, `uv_scale: vec2 = vec2(1.0)`, `snap_resolution: float = 160.0` (temblor de vértices); `render_mode vertex_lighting`. `base_env.tres`: niebla de distancia gris-azulada, cielo con gradiente, luz ambiental tenue.

- [ ] **Paso 1: Escribir el shader** con el snapping de vértices en espacio de recorte.
- [ ] **Paso 2: Aplicarlo** a todos los modelos de `scale_reference` con `base_env.tres`.
- [ ] **Paso 3: Verificar** — captura de `scale_reference` donde todos los modelos se ven con la misma paleta y textura pixelada; compartirla con el equipo.
- [ ] **Paso 4: Commit** — `feat: add PSX shader and base environment`

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

- [ ] **Paso 1: Pruebas que fallan**
  - `test_combo_damage_sequence`: `Player.combo_damage(i)` devuelve 10, 10, 18 para i = 0, 1, 2 y 10 para i = 3 (vuelve a empezar).
  - `test_lock_on_drops_invalid_target`: con un `Node3D` asignado como `target` y luego liberado, `validate()` deja `target == null` sin error.
  - `test_lock_on_range`: objetivo a 16 m sin grupo `"boss"` → se suelta; en grupo `"boss"` a 16 m → se mantiene.
- [ ] **Paso 2: Ejecutar** — FAIL.
- [ ] **Paso 3: Implementar** combo (ventana para encadenar 0.4 s tras cada golpe), hitbox del mandoble (caja 0.2 × 0.2 × 1.4 m, capa 5, máscara 8) activada solo en la ventana de daño, estado `HURT` (0.4 s, interrumpe ataque), `DEAD` (emite `Events.player_died`), y el HUD conectado a `Health.changed` y `Stamina.changed`.
- [ ] **Paso 4: Ejecutar pruebas** — pasan.
- [ ] **Paso 5: Verificación manual** en `test_arena` con un muñeco (`StaticBody3D` + `Hurtbox` + `Health` 30): 3 golpes de combo lo matan (10 + 10 + 18 ≥ 30); la estamina baja 20 por golpe; el lock-on gira la cámara hacia el muñeco.
- [ ] **Paso 6: Commit** — `feat: add player combo, lock-on, death and HUD`

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

- [ ] **Paso 1: Pruebas que fallan**
  - `test_idle_to_chase_when_seen`; `test_chase_to_circle_without_token` (distancia ≤ 4 m y `has_token = false` → `CIRCLE`); `test_chase_to_attack_with_token` (distancia ≤ 1.5 y token → `ATTACK`); `test_attack_to_recover`; `test_hit_interrupts_to_stunned`; `test_dead_is_terminal` (desde cualquier estado con `is_dead` → `DEAD`, y de `DEAD` no sale).
  - `test_can_see_cone`: objetivo a 5 m al frente → true; a 5 m detrás → false; a 13 m al frente → false.
- [ ] **Paso 2: Ejecutar** — FAIL.
- [ ] **Paso 3: Implementar** `MinionBrain` y `minion.gd` (pide ficha al entrar en rango de 4 m; en `CIRCLE` orbita a 3.5 m; en `ATTACK` activa la hitbox 0.3 s tras 0.5 s de aviso; `RECOVER` 0.8 s; `STUNNED` 0.4 s; libera la ficha al salir de `ATTACK` y al morir).
- [ ] **Paso 4: Ejecutar pruebas** — pasan.
- [ ] **Paso 5: Verificación manual** — 4 esbirros en `test_arena`: solo 2 atacan a la vez, los demás rodean; se mueren con los combos de Kaelen; Kaelen muere tras 5 golpes de 20.
- [ ] **Paso 6: Commit** — `feat: add minion FSM with navigation and attack tokens`

### Tarea 8 (C): Kaelen y Elysia procesadas + animaciones del Bone Dragon + bloqueo de la arena 1

**Archivos:**
- Crear: `assets/characters/kaelen/kaelen.glb` (rig Mixamo, ~5k triángulos, capa separada), `assets/characters/kaelen/anims/*.glb` (Mixamo, *without skin*), `assets/characters/elysia/elysia.glb`
- Crear: `assets/bosses/bonedragon/bonedragon.glb` con animaciones `idle`, `roar`, `bite`, `tail_sweep`, `stomp`, `death`
- Crear: `assets/minions/skeleton/skeleton.glb`, `assets/minions/knight/knight.glb` (rig Mixamo)
- Crear: `scenes/levels/arena_1.tscn` (bloqueo CSG según §6.3: 32 × 32 m, techo 8 m, 4 pilares, rejas, margen de cámara 3 m)

**Interfaces:**
- Produce: nombres de animación exactos para Kaelen: `idle`, `walk`, `run`, `roll`, `attack_1`, `attack_2`, `attack_3`, `hurt`, `death`; para esbirros humanoides: `idle`, `walk`, `attack`, `hurt`, `death`. Lista real registrada en `docs/asset-status.md`.
- Produce: `arena_1.tscn` con un nodo vacío `Gameplay` donde se instancia `arena_1_gameplay.tscn` (de B).

- [ ] **Paso 1:** Kaelen y Elysia: reducir (Blender *Decimate* hasta ~5k triángulos), pintar por zonas con la paleta de los concept art, separar la capa de Kaelen, exportar FBX para Mixamo.
- [ ] **Paso 2:** Mixamo (manual, cuenta del equipo): auto-rig de Kaelen, Elysia, Skeleton y Knight; descargar las animaciones de la lista *in place*.
- [ ] **Paso 3:** Bone Dragon: crear las 6 animaciones con keyframes sobre su rig (vía MCP de Blender); verificar que se reproducen en Godot.
- [ ] **Paso 4:** Bloqueo de `arena_1.tscn` + capturas.
- [ ] **Paso 5: Verificación** — cada GLB abre en Godot con las animaciones de la lista; Kaelen mide 1.70 m en `scale_reference`.
- [ ] **Paso 6: Commit** — `feat: add processed Kaelen, Elysia, skeleton, knight and bone dragon animations`

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

- [ ] **Paso 1: Pruebas que fallan**
  - `test_out_of_range_scores_zero`; `test_repeat_penalty` (mismo ataque como último → puntaje × 0.3); `test_phase2_multiplier` (× 1.25); `test_choose_never_returns_out_of_range`; `test_choose_only_from_top_two` (con 3 ataques válidos y semilla fija, en 200 sorteos el de menor puntaje nunca sale); `test_phase_min_filter`; `test_dodge_bias_average` (registrar +1, +1, −1 → 0.333).
- [ ] **Paso 2: Ejecutar** — FAIL.
- [ ] **Paso 3: Implementar** `BossBrain`, `Boss` (ciclo: elegir → aviso con decal en el piso del tamaño de la hitbox → activa → recuperación; fase 2 = +25 % velocidad de animación y de ataque), `boss_base.tscn` y `boss_bonedragon.tscn` con medidas de §7.4 (collider cápsula horizontal r 1.2 × 4 m; hurtboxes en torso, cabeza ×1.25 y 4 patas con `BoneAttachment3D`; navegación capa 2).
- [ ] **Paso 4: Ejecutar pruebas** — pasan.
- [ ] **Paso 5: `arena_1_gameplay.tscn`**: `PlayerStart`, `BossStart`, 6 `Marker3D` en grupo `"spawn_point"` sobre la capa 1, `NavigationRegion3D` capa 1 y 2 horneadas sobre la geometría de `arena_1`, rejas que se cierran al entrar (`Events.arena_entered`) y se abren con `Events.boss_defeated`; 4 esqueletos colocados a mano (el Orquestador llega el día 4).
- [ ] **Paso 6: Verificación manual (hito)** — se puede matar al Bone Dragon (400 de vida) y morir ante él; a 200 cambia a fase 2; si Kaelen y el dragón mueren casi a la vez gana quien llegó primero a 0, y tras `boss_defeated` Kaelen no recibe daño.
- [ ] **Paso 7: Commit** — `feat: add boss system and bone dragon fight`

### Tarea 10 (A): Menú principal, pausa, muerte/reaparición y flujo de `GameState`

**Archivos:**
- Completar: `scripts/game/game_state.gd` (B lo entrega a A al empezar el día 3)
- Crear: `scenes/ui/main_menu.tscn`, `scenes/ui/pause_menu.tscn`, `scenes/ui/death_screen.tscn`, `scenes/ui/transition.tscn`, scripts en `scripts/ui/`
- Prueba: `tests/test_game_state.gd`
- Pedido a B: `run/main_scene = res://scenes/ui/main_menu.tscn` en `project.godot`

**Interfaces:**
- Consume: `Events.player_died`, `Events.boss_defeated`.
- Produce: `GameState.LEVEL_SCENES: Array[String] = ["res://scenes/levels/island_intro.tscn", "res://scenes/levels/arena_1.tscn", "res://scenes/levels/arena_2.tscn", "res://scenes/levels/arena_3.tscn", "res://scenes/levels/ending.tscn"]`; `func scene_for_level(level: int) -> String`; `transition.tscn` con `func fade_to(path: String) -> void` (fundido a negro 0.5 s). Kaelen se vuelve invulnerable al recibir `Events.boss_defeated`.

- [ ] **Paso 1: Pruebas que fallan** — `test_max_hp_by_level` (0 → 100, 1 → 70, 2 → 40); `test_level_clamped` (`current_level` no pasa de 2 al calcular vida); `test_new_game_resets_level` (`start_new_game()` con nivel 2 → nivel 0).
- [ ] **Paso 2: Ejecutar** — FAIL.
- [ ] **Paso 3: Implementar** `GameState` (sin cargar escenas en las pruebas: separar `_change_scene(path)` para que las pruebas no lo llamen), menú principal (Iniciar, Créditos, Salir; foco inicial en Iniciar; navegable con teclado y mando), pausa (`get_tree().paused`, `process_mode = ALWAYS`, Continuar / Volver al menú / Salir; libera y recaptura el ratón), pantalla "HAS MUERTO" + fundido + `reload_current_arena()`.
- [ ] **Paso 4: Ejecutar pruebas** — pasan.
- [ ] **Paso 5: Verificación manual** — desde el menú se entra a `arena_1`, se pausa y continúa, se muere y reaparece con el jefe a vida completa y sin esbirros sobrantes; "Volver al menú" desde la pausa no deja el juego pausado.
- [ ] **Paso 6: Commit** — `feat: add main menu, pause, death and game flow`

### Tarea 11 (C): Arte de la arena 1 + animaciones de Malenia y Ghidorah

**Archivos:**
- Crear: `assets/environment/kit/*.tscn` (piezas de `PSX_Dungeon` a 4 m con colisión), `assets/environment/kit/dungeon_kit.meshlib`
- Modificar: `scenes/levels/arena_1.tscn` (reemplazar CSG por `GridMap` + piezas; decoración mínima)
- Crear: `assets/bosses/malenia/malenia.glb` (+ animaciones Mixamo reasignadas: `idle`, `walk`, `slash`, `thrust`, `spin`, `hurt`, `death`), `assets/bosses/ghidorah/ghidorah.glb` (~8k triángulos; `idle`, `roar`, `bite`, `tail_sweep`, `beam`, `death`)

- [ ] **Paso 1:** importar piezas del kit con escala de 4 m y colisión (caja para muros/pilares, trimesh para pisos/escaleras); exportar `MeshLibrary` (puede usarse `export_mesh_library` del MCP de Godot).
- [ ] **Paso 2:** reconstruir `arena_1` con `GridMap` sin mover la posición de pilares, rejas ni límites (B ya horneó la navegación sobre ellos; si cambian, avisar a B para rehornear).
- [ ] **Paso 3:** Malenia (retarget de Mixamo en Godot con `BoneMap`) y Ghidorah (reducir + keyframes vía MCP de Blender).
- [ ] **Paso 4: Verificación** — `arena_1` con arte se juega igual que el bloqueo; Malenia y Ghidorah reproducen todas sus animaciones en `scale_reference`.
- [ ] **Paso 5: Commit** — `feat: arena 1 art pass, malenia and ghidorah animations`

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

- [ ] **Paso 1: Pruebas que fallan** — `test_damage_raises_intensity` (20 de daño → +30); `test_natural_decay` (intensidad 50, `update(1.0)` sin enemigos cerca → 35); `test_build_up_to_peak_at_80`; `test_peak_lasts_5s`; `test_relax_waits_for_low_intensity`; `test_low_hp_forces_relax`; `test_no_spawn_during_boss_special`; `test_budget_phase2_multiplier`; `test_budget_respects_max_alive` (5 vivos → presupuesto ≤ 1); `test_reset_returns_to_build_up`.
- [ ] **Paso 2: Ejecutar** — FAIL.
- [ ] **Paso 3: Implementar** el modelo y el autoload (genera esbirros/élites en los `spawn_point` válidos; `begin_arena` lo llama `arena_N_gameplay` con `Events.arena_entered`; `end_arena` con `boss_defeated` o `player_died` → `reset()` + liberar esbirros + `AttackTokens.reset()`).
- [ ] **Paso 4: Ejecutar pruebas** — pasan.
- [ ] **Paso 5: Overlay F3** — muestra intensidad, fase, presupuesto, vivos y fichas (`get_debug_info()` + `AttackTokens.holders_count()`); F5 salta al siguiente nivel; F6 alterna invulnerabilidad de Kaelen.
- [ ] **Paso 6: Verificación manual** — en `arena_1` la intensidad oscila (no se queda en 0 ni en 100), aparecen oleadas fuera de cámara, y al bajar de 25 % de vida dejan de aparecer.
- [ ] **Paso 7: Commit** — `feat: add orchestrator and debug overlay`

### Tarea 13 (A): Jefes 2 (Malenia) y 3 (Ghidorah)

**Archivos:**
- Crear: `scenes/bosses/boss_malenia.tscn`, `scenes/bosses/boss_ghidorah.tscn` (heredan de `boss_base.tscn`), `resources/attacks/malenia_{slash,thrust,spin}.tres`, `resources/attacks/ghidorah_{bite,tail_sweep,beam}.tres`

**Interfaces:**
- Consume: `Boss`, `BossAttack` (Tarea 9) — **sin modificar sus scripts**; si falta algo, pedirlo a B.
- Medidas (§7.4): Malenia cápsula r 0.50 · alto 2.60, hurtbox r 0.55 · alto 2.50, espada 0.2 × 0.2 × 1.6 m, estocada 1 × 1 × 4 m, navegación capa 1, vida 500. Ghidorah cápsula torso r 2.5 · alto 6 + patas, cabezas solo con hurtbox (esferas r 1.0) y bajan al suelo durante `bite`, mordida esfera r 1.5, cola caja 6 m, rayo 1.5 × 1.5 × 20 m con aviso en línea, navegación capa 2, vida 600, `LockOnPoint` en el torso a media altura.

- [ ] **Paso 1:** crear las escenas y los 6 recursos de ataque con rangos coherentes (Malenia: `slash` 0–3 m, `thrust` 2–6 m, `spin` 0–3.5 m solo fase 2; Ghidorah: `bite` 0–6 m, `tail_sweep` 0–8 m, `beam` 8–20 m).
- [ ] **Paso 2: Verificación manual** en `test_arena` (cambiando el jefe instanciado): ambos jefes se pueden matar y matan a Kaelen; las cabezas de Ghidorah solo reciben golpes al bajar en `bite`; la cámara con lock-on encuadra a Ghidorah sin meterse en su cuerpo.
- [ ] **Paso 3: Commit** — `feat: add malenia and ghidorah bosses`

### Tarea 14 (C): Bloqueo y arte de arenas 2 y 3 + isla

**Archivos:**
- Crear: `scenes/levels/arena_2.tscn` (octogonal, 24 m, techo 8 m, 6 columnas), `scenes/levels/arena_3.tscn` (40 × 40 m, sin techo, pilares rotos, altar al fondo tras reja), `scenes/levels/island_intro.tscn`
- Crear: `assets/environment/island/floating_island.tscn` (escena heredada, limpia)

- [ ] **Paso 1:** bloqueo CSG de arenas 2 y 3 con nodo `Gameplay` vacío; entregar a B para que cree `arena_2_gameplay.tscn` y `arena_3_gameplay.tscn` y hornee la navegación.
- [ ] **Paso 2:** `floating_island` según §6.2: escalar a ≈ 150 m, ocultar dirigible/animales/torii/banderas, texturas a 256 px, tinte desaturado, sin colisión salvo suelo invisible del sendero; fachada del templo con `PSX_Dungeon`; islotes de `float-islands`; cielo y niebla.
- [ ] **Paso 3: Verificación** — `island_intro` se recorre de inicio a puerta en 1–2 min sin caer al vacío; corre a ≥ 60 FPS en la PC más lenta del equipo.
- [ ] **Paso 4: Commit** — `feat: add arenas 2-3 blockout and island intro`

**(B, final del día 4):** `arena_2_gameplay.tscn` y `arena_3_gameplay.tscn` con navegación, spawns y `ArenaConfig` (arena 2: Plague Arcanist; arena 3: TheWrapper + élite Aura Battler si existe).

---

# DÍA 5 — Partida completa

### Tarea 15 (A): Flujo completo, final y créditos

**Archivos:**
- Modificar: `scripts/game/game_state.gd`
- Crear: `scenes/ui/credits.tscn`, `scripts/ui/credits.gd`, `scripts/game/ending_director.gd`
- Pedido a C: `scenes/levels/ending.tscn` con cámaras fijas `Cam1`..`Cam3` y Elysia

**Interfaces:**
- Produce: `ending_director.gd` (adjunto a un nodo de `ending.tscn` por C) con `func play() -> void`: corta entre `Cam1`–`Cam3` con texto en pantalla y termina en `credits.tscn`. `credits.tscn` muestra el texto de `res://assets/credits.txt` (C lo escribe con autores y licencias).

- [ ] **Paso 1:** puerta del templo en `island_intro` → `advance_level()`; `boss_defeated` → espera 3 s → reja abierta → al cruzarla `advance_level()`; vida máxima de Kaelen = `GameState.get_player_max_hp()` al entrar a cada arena.
- [ ] **Paso 2:** final y créditos (botón "Volver al menú").
- [ ] **Paso 3: Verificación manual** — partida completa menú → isla → 3 jefes → final → créditos → menú usando F6 (invulnerable) y F5; luego otra muriendo una vez por jefe: la vida máxima es 100, 70 y 40.
- [ ] **Paso 4: Commit** — `feat: complete game flow, ending and credits`

### Tarea 16 (B): Esbirros por nivel, élites y ajuste de jefes

**Archivos:**
- Crear: `scenes/enemies/minion_skeleton.tscn`, `minion_knight_elite.tscn`, `minion_plague.tscn`, `minion_wrapper.tscn`, `minion_aura_elite.tscn` (opcional), heredando de `minion_base.tscn`

- [ ] **Paso 1:** variantes con modelos y medidas de §7.4 (élite: `cost = 3`, vida 90, daño 30, tinte distinto). Aura Battler: flota a 0.5 m, se mueve con tweens, navegación capa 2.
- [ ] **Paso 2:** conectar animaciones (`idle`/`walk`/`attack`/`hurt`/`death`) y sonidos vía `AudioManager.play_sfx_3d`.
- [ ] **Paso 3: Verificación manual** — cada arena genera su tipo de esbirro; el overlay muestra costos correctos (élite = 3).
- [ ] **Paso 4: Commit** — `feat: add per-level minions and elites`

### Tarea 17 (C): Audio completo

**Archivos:**
- Completar: `scripts/audio/audio_manager.gd`
- Crear: `assets/audio/bgm/*.ogg`, `assets/audio/sfx/**` (solo los usados, convertidos de `_source`), `assets/credits.txt`

**Interfaces:**
- Produce: `AudioManager` con buses `Music`/`SFX`/`UI`; fundido de música; variación de tono ±10 %; escucha `Events.hit_landed` y reproduce impacto según `surface` (`flesh`, `bone`, `metal`); baja 10 dB la música en pausa.
- Asignación de música (spec §11.3): menú `celtic melancholy`, isla `LVS04_10_Battlefield`, jefe 1 `skull dragon battle`, jefe 2 `Blazing Honor`, jefe 3 `black dragon battle`, final/créditos `sadness piano4`.

- [ ] **Paso 1:** convertir y copiar solo los archivos usados a `assets/audio/`.
- [ ] **Paso 2:** implementar `AudioManager` y conectar música por escena.
- [ ] **Paso 3:** escribir `assets/credits.txt` con autor y licencia de cada asset y pista usados (Atelier Magicae y CC-BY obligatorios).
- [ ] **Paso 4: Verificación manual** — cada escena suena con su pista; pasos, swings, impactos, rugidos y menús suenan; la pausa baja la música.
- [ ] **Paso 5: Commit** — `feat: add audio manager, music and sfx`

---

# DÍA 6 — Pulido y prueba externa

### Tarea 18 (los 3): Pulido por área
- **A:** pausa de impacto 60 ms (`Engine.time_scale` restaurado siempre, incluso si se pausa durante el impacto), parpadeo de material al recibir golpe, ajuste de cámara; menú de opciones (volumen por bus, sensibilidad, pantalla completa, `user://settings.cfg`) **solo si todo lo anterior funciona**.
- **B:** balance con el overlay F3 (la intensidad debe oscilar en las 3 arenas); prueba con 2 personas externas y registro de dónde mueren.
- **C:** decoración de arenas, iluminación por arena (§6.3), filtro de color por jefe derrotado (opcional), sonidos faltantes (§11.4).
- [ ] **Verificación:** 2 personas externas juegan la partida completa; se anotan los problemas en `docs/playtest.md`.
- [ ] **Commit** por persona.

# DÍA 7 — Congelación y entrega

### Tarea 19 (los 3): Cierre
- [ ] **Congelación:** no se agregan funciones; solo arreglos de la lista de `docs/playtest.md`, priorizados por B.
- [ ] **Exportar** Windows (A) y Web (opcional, A); probar el ejecutable en una PC que no sea de desarrollo.
- [ ] **Checklist final** (spec §16): menú → isla → 3 jefes → final → créditos → menú, muriendo al menos una vez por jefe y usando la pausa; todas las pruebas pasan.
- [ ] **Créditos** revisados contra las licencias (C).
- [ ] **Commit y tag** `v1.0`.

---

## Resumen por persona y día

| Día | A — Jugador e interfaz | B — IA y enemigos | C — Arte, escenarios y sonido |
|---|---|---|---|
| 1 | T3 Kaelen-cápsula, cámara, rodada, `test_arena` | T1 Contrato (primera hora) · T2 Componentes + fichas | T4 Escalas e importación · T5 Shader PSX |
| 2 | T6 Combo, lock-on, muerte, HUD | T7 Esbirro FSM + navegación | T8 Kaelen/Elysia/esbirros Mixamo, animaciones Bone Dragon, bloqueo arena 1 |
| 3 | T10 Menús, pausa, muerte, `GameState` | T9 Sistema de jefes + Bone Dragon + gameplay arena 1 | T11 Arte arena 1, animaciones Malenia y Ghidorah |
| 4 | T13 Jefes Malenia y Ghidorah | T12 Orquestador + overlay · gameplay arenas 2 y 3 | T14 Arenas 2 y 3, isla |
| 5 | T15 Flujo completo, final, créditos | T16 Esbirros por nivel y élites | T17 Audio completo |
| 6 | Pulido combate y opciones | Balance y prueba externa | Decoración e iluminación |
| 7 | Exportar | Arreglos priorizados | Créditos y licencias |
