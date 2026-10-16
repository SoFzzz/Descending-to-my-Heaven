class_name HitStop
extends Node
## Pausa de impacto: baja Engine.time_scale unos milisegundos al acertar un golpe. El tiempo se
## mide en reloj real (no se ve afectado por el propio time_scale) y se restaura SIEMPRE: al
## terminar, si el juego se pausa, si se cambia de escena o si el nodo sale del árbol. Una petición
## mientras hay otra activa se ignora (no se apilan, el tiempo nunca se queda lento).
## Los Tween de la UI que usan set_ignore_time_scale(true) y los temporizadores de la pantalla de
## muerte no se ven afectados; el resto va más lento durante esos ~60 ms.

const HIT_DURATION := 0.06      # golpe de Kaelen que acierta
const HURT_DURATION := 0.04     # Kaelen recibe daño
const SCALE := 0.05             # time_scale durante la pausa

static var _driver: HitStop = null

var active := false
var _saved_scale := 1.0
var _end_ms := 0
var _duration := 0.0


## Pide una pausa de `duration` s. Devuelve true si se aplicó (false si ya había una, no hay árbol,
## el juego está en pausa o la duración es 0).
static func request(tree: SceneTree, duration: float = HIT_DURATION) -> bool:
	if tree == null or duration <= 0.0 or tree.paused:
		return false
	if _driver == null or not is_instance_valid(_driver) or not _driver.is_inside_tree():
		_driver = HitStop.new()
		_driver.name = "HitStop"
		_driver.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(_driver)
	return _driver._begin(duration)


## true mientras hay una pausa de impacto en curso.
static func is_active() -> bool:
	return _driver != null and is_instance_valid(_driver) and _driver.active


## Restaura el tiempo ya (cambio de escena, pruebas).
static func cancel() -> void:
	if _driver != null and is_instance_valid(_driver):
		_driver.end()


func _begin(duration: float) -> bool:
	if active:
		return false
	active = true
	_duration = duration
	_saved_scale = Engine.time_scale
	_end_ms = Time.get_ticks_msec() + int(duration * 1000.0)
	Engine.time_scale = minf(_saved_scale, SCALE)
	return true


## Termina la pausa: el time_scale vuelve al valor previo solo si nadie más lo ha cambiado.
func end() -> void:
	if not active:
		return
	active = false
	if is_equal_approx(Engine.time_scale, minf(_saved_scale, SCALE)):
		Engine.time_scale = _saved_scale


func _process(_delta: float) -> void:
	if not active:
		return
	if get_tree().paused or Time.get_ticks_msec() >= _end_ms:
		end()


func _exit_tree() -> void:
	end()
	if _driver == self:
		_driver = null
