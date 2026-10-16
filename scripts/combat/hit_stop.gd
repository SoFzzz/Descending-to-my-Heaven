class_name HitStop
extends Node
## Hit-stop: lowers Engine.time_scale for a few milliseconds when a hit lands. The time is
## measured on the real clock (not affected by time_scale itself) and ALWAYS restored: when it
## ends, if the game is paused, if the scene changes or if the node leaves the tree. A request
## while another is active is ignored (they do not stack, time never stays slow).
## UI Tweens that use set_ignore_time_scale(true) and the death screen timers are not
## affected; everything else runs slower during those ~60 ms.

const HIT_DURATION := 0.06      # Kaelen's hit that lands
const HURT_DURATION := 0.04     # Kaelen takes damage
const SCALE := 0.05             # time_scale during the stop

static var _driver: HitStop = null

var active := false
var _saved_scale := 1.0
var _end_ms := 0
var _duration := 0.0


## Requests a stop of `duration` s. Returns true if applied (false if one was already active, there is
## no tree, the game is paused or the duration is 0).
static func request(tree: SceneTree, duration: float = HIT_DURATION) -> bool:
	if tree == null or duration <= 0.0 or tree.paused:
		return false
	if _driver == null or not is_instance_valid(_driver) or not _driver.is_inside_tree():
		_driver = HitStop.new()
		_driver.name = "HitStop"
		_driver.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(_driver)
	return _driver._begin(duration)


## true while a hit-stop is in progress.
static func is_active() -> bool:
	return _driver != null and is_instance_valid(_driver) and _driver.active


## Restores the time immediately (scene change, tests).
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


## Ends the stop: time_scale returns to its previous value only if nobody else has changed it.
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
