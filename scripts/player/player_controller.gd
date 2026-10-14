class_name Player
extends CharacterBody3D
## Kaelen (Tarea 3). Estados MOVE (caminar relativo a la cámara, gravedad, giro suave) y ROLL
## (rodada con i-frames y costo de estamina). ATTACK, HURT y DEAD quedan para la Tarea 6.

enum State { MOVE, ROLL, ATTACK, HURT, DEAD }

const WALK_SPEED := 5.0          # m/s (Tarea 3)
const ACCELERATION := 30.0       # m/s² al arrancar
const DECELERATION := 40.0       # m/s² al frenar
const TURN_SPEED := 12.0         # rapidez del giro hacia la dirección de avance
const MAX_STEP := 0.35           # escalón más alto que sube sola (los del mapa miden 0.25 m)
const STEP_PROBE := 0.2          # cuánto se adelanta para buscar la huella del escalón
const ROLL_DURATION := 0.6
const ROLL_IFRAME_START := 0.05
const ROLL_IFRAME_END := 0.40
const ROLL_COST := 25.0
const ROLL_SPEED := 7.0          # m/s constantes durante toda la rodada

# Velocidad del suelo a la que cada clip se ve sin patinar (medida a ojo con capturas; ver
# docs/asset-status.md). Por encima de RUN_ANIM_SPEED se acelera el clip `run`.
const WALK_ANIM_SPEED := 1.4
const RUN_ANIM_SPEED := 4.2

# Estados de acción del AnimationTree (además de "locomotion"). Solo roll se usa por ahora; los
# demás quedan listos para la Tarea 6.
const ACTION_STATES: Array[StringName] = [&"roll", &"attack_1", &"attack_2", &"attack_3", &"hurt", &"death"]

var state: State = State.MOVE
## Si nadie los asignó antes, se buscan en _ready (hijos "Health" y "Stamina"). Las pruebas los
## asignan a mano sin meter a Kaelen en el árbol.
var health: Health
var stamina: Stamina

@onready var _model: Node3D = $Model
@onready var _camera_rig: CameraRig = $CameraRig
var _anim_tree: AnimationTree
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _roll_time := 0.0
var _roll_dir := Vector3.ZERO
# Fuentes de invulnerabilidad: se combinan y ninguna apaga a las otras (Foco de revisión 4).
var _iframes := false   # ventana de la rodada
var _victory := false   # tras Events.boss_defeated
var _god := false       # depuración (acción "debug_god", F6)


func _ready() -> void:
	add_to_group("player")
	if health == null:
		health = get_node_or_null(^"Health") as Health
	if stamina == null:
		stamina = get_node_or_null(^"Stamina") as Stamina
	# Events puede no existir (pruebas con -s), por eso se busca por ruta.
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.boss_defeated.connect(_on_boss_defeated)
	_build_animation_tree()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("debug_god"):
		_god = not _god
		print("debug_god: ", _god)

	match state:
		State.MOVE:
			if Input.is_action_just_pressed("roll") and try_roll():
				_roll_step(delta)
			else:
				_move_step(delta)
		State.ROLL:
			_roll_step(delta)
		_:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
	_update_invulnerability()
	_update_animation(Vector3(velocity.x, 0.0, velocity.z).length())


## Dirección del input relativa a la cámara (largo ≤ 1; cero sin input).
func _input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	# Relativo a la cámara: solo importa su giro horizontal.
	var yaw := _camera_rig.yaw if _camera_rig else 0.0
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	return dir.normalized() * minf(input.length(), 1.0)


func _move_step(delta: float) -> void:
	var dir := _input_direction()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var goal := dir * WALK_SPEED
	var rate := ACCELERATION if goal.length() > horizontal.length() else DECELERATION
	horizontal = horizontal.move_toward(goal, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and is_on_wall() and dir != Vector3.ZERO:
		_try_step_up(dir * WALK_SPEED * delta)

	if dir != Vector3.ZERO:
		# El modelo de Mixamo mira a +Z: se gira para que su frente apunte hacia `dir`.
		var target_yaw := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))


# CharacterBody3D no sube escalones solo: si choca con algo de hasta MAX_STEP de alto, se prueba
# subirla, avanzar un poco y bajar hasta tocar el escalón; si hay apoyo, se eleva a esa altura y
# el siguiente move_and_slide la hace avanzar.
func _try_step_up(motion: Vector3) -> void:
	var probe := motion.normalized() * STEP_PROBE
	var from := global_transform
	if test_move(from, Vector3.UP * MAX_STEP):
		return   # techo encima
	var raised := from.translated(Vector3.UP * MAX_STEP)
	if test_move(raised, probe):
		return   # sigue siendo pared: no es un escalón
	var col := KinematicCollision3D.new()
	if not test_move(raised.translated(probe), Vector3.DOWN * MAX_STEP, col):
		return   # no hay suelo donde apoyarse
	var rise := MAX_STEP + col.get_travel().y
	if rise <= 0.01:
		return
	global_position.y += rise
	velocity.y = 0.0


# --- Rodada -----------------------------------------------------------------------------------

## Ventana de invulnerabilidad de la rodada: [ROLL_IFRAME_START, ROLL_IFRAME_END) segundos.
static func iframes_active_at(t: float) -> bool:
	return t >= ROLL_IFRAME_START and t < ROLL_IFRAME_END


## Empieza una rodada si se está en MOVE y hay estamina. Dirección: la del input relativo a la
## cámara o, sin input, el frente del modelo.
func try_roll() -> bool:
	if state != State.MOVE or stamina == null or not stamina.try_spend(ROLL_COST):
		return false
	var dir := _input_direction()
	if dir == Vector3.ZERO:
		dir = get_facing()
	dir.y = 0.0
	_roll_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.BACK
	_roll_time = 0.0
	state = State.ROLL
	if _model:
		_model.rotation.y = atan2(_roll_dir.x, _roll_dir.z)
	if _anim_tree:
		var playback := _anim_tree.get(&"parameters/playback") as AnimationNodeStateMachinePlayback
		playback.start(&"roll")   # siempre desde el principio del clip
	return true


func _roll_step(delta: float) -> void:
	var motion := _roll_dir * ROLL_SPEED
	velocity.x = motion.x
	velocity.z = motion.z
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and is_on_wall():
		_try_step_up(motion * delta)
	_advance_roll(delta)


## Avanza el reloj de la rodada; al cumplir ROLL_DURATION vuelve a MOVE frenada en seco.
func _advance_roll(delta: float) -> void:
	_roll_time += delta
	_iframes = iframes_active_at(_roll_time)
	if _roll_time >= ROLL_DURATION - 0.0001:
		state = State.MOVE
		_iframes = false
		_roll_time = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
	_update_invulnerability()


func _on_boss_defeated(_boss: Node3D) -> void:
	_victory = true
	_update_invulnerability()


func is_invulnerable() -> bool:
	return _iframes or _victory or _god


func _update_invulnerability() -> void:
	if health:
		health.invulnerable = is_invulnerable()


func get_facing() -> Vector3:
	if _model == null:
		return basis.z   # fuera del árbol (pruebas)
	return _model.global_basis.z


## Coloca a Kaelen en un punto (Marker3D) del nivel y alinea la cámara detrás de ella.
func spawn_at(marker: Node3D) -> void:
	global_position = marker.global_position
	velocity = Vector3.ZERO
	var forward := -marker.global_basis.z   # los Marker3D miran a -Z
	_model.rotation.y = atan2(forward.x, forward.z)
	_camera_rig.yaw = atan2(-forward.x, -forward.z)
	_camera_rig.rotate_view(0.0, 0.0)
	_camera_rig.global_position = global_position + Vector3.UP * CameraRig.PIVOT_HEIGHT


# --- Animación --------------------------------------------------------------------------------
# Raíz: AnimationNodeStateMachine.
# - "locomotion": BlendTree con un BlendSpace1D idle/walk/run según la velocidad y un TimeScale
#   que acelera el clip cuando se va más rápido de lo que muestra (evita que los pies patinen).
# - "roll": BlendTree con el clip y un TimeScale que lo ajusta a ROLL_DURATION.
# - attack_1..3, hurt, death: un clip cada uno. Todos vuelven a locomotion al terminar salvo death.

func _build_animation_tree() -> void:
	var player := _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sm := AnimationNodeStateMachine.new()
	sm.add_node(&"locomotion", _build_locomotion(), Vector2(0, 0))
	for i in ACTION_STATES.size():
		var state_name := ACTION_STATES[i]
		var node: AnimationRootNode
		if state_name == &"roll":
			node = _build_time_scaled_clip(state_name)
		else:
			var clip := AnimationNodeAnimation.new()
			clip.animation = state_name
			node = clip
		sm.add_node(state_name, node, Vector2(300, (i - 2) * 80))
		var go := AnimationNodeStateMachineTransition.new()
		go.xfade_time = 0.08
		sm.add_transition(&"locomotion", state_name, go)
		if state_name != &"death":
			var back := AnimationNodeStateMachineTransition.new()
			back.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			back.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
			back.xfade_time = 0.15
			sm.add_transition(state_name, &"locomotion", back)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"locomotion", start)

	_anim_tree = AnimationTree.new()
	_anim_tree.name = "AnimationTree"
	_anim_tree.tree_root = sm
	add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(player)
	# El clip roll entero (~2.4 s) debe caber en ROLL_DURATION: factor con su duración real.
	var roll_length := ROLL_DURATION
	if player.has_animation(&"roll"):
		roll_length = player.get_animation(&"roll").length
	else:
		push_warning("Kaelen: falta el clip 'roll'")
	_anim_tree.set(&"parameters/roll/speed/scale", roll_length / ROLL_DURATION)
	_anim_tree.active = true


func _build_locomotion() -> AnimationNodeBlendTree:
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = WALK_SPEED
	for p in [["idle", 0.0], ["walk", WALK_ANIM_SPEED], ["run", RUN_ANIM_SPEED]]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = p[0]
		space.add_blend_point(clip, p[1], -1, p[0])
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"locomotion", space)
	tree.add_node(&"speed", AnimationNodeTimeScale.new())
	tree.connect_node(&"speed", 0, &"locomotion")
	tree.connect_node(&"output", 0, &"speed")
	return tree


## BlendTree clip → TimeScale ("speed") → salida; el factor se fija en parameters/<estado>/speed/scale.
func _build_time_scaled_clip(clip_name: StringName) -> AnimationNodeBlendTree:
	var clip := AnimationNodeAnimation.new()
	clip.animation = clip_name
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"clip", clip)
	tree.add_node(&"speed", AnimationNodeTimeScale.new())
	tree.connect_node(&"speed", 0, &"clip")
	tree.connect_node(&"output", 0, &"speed")
	return tree


func _update_animation(speed: float) -> void:
	_anim_tree.set(&"parameters/locomotion/locomotion/blend_position", speed)
	var anim_scale := 1.0
	if speed > RUN_ANIM_SPEED:
		anim_scale = speed / RUN_ANIM_SPEED
	elif speed > 0.05 and speed < WALK_ANIM_SPEED:
		anim_scale = maxf(0.6, speed / WALK_ANIM_SPEED)
	_anim_tree.set(&"parameters/locomotion/speed/scale", anim_scale)
