class_name Hitbox
extends Area3D
## Zone that deals damage while active; hits each Hurtbox only once per activation.

@export var damage: int = 0
## Impact sound of this hit: plays ONCE per activation (even if it touches several hurtboxes),
## at the position of the first. `sfx_impact_metal` replaces it if that hurtbox has a `metal` surface.
@export var sfx_impact: AudioStream
@export var sfx_impact_metal: AudioStream

var _hit_ids: Dictionary = {}
var _active := false
var _impact_played := false


func _init() -> void:
	monitoring = false  # starts inactive, also outside the tree


func _ready() -> void:
	area_entered.connect(_on_area_entered)


# Deferred: Godot blocks changing monitoring inside physics callbacks.
func activate() -> void:
	_hit_ids.clear()
	_impact_played = false
	_active = true
	set_deferred(&"monitoring", true)


func deactivate() -> void:
	_active = false
	set_deferred(&"monitoring", false)


## true only the first time per activation: the impact sound plays once per hit.
func claim_impact_sound() -> bool:
	if _impact_played:
		return false
	_impact_played = true
	return true


## Impact sound for a hurtbox of surface `surface` (null if there is none).
func impact_stream_for(surface: StringName) -> AudioStream:
	if surface == &"metal" and sfx_impact_metal != null:
		return sfx_impact_metal
	return sfx_impact


func register_hit(hurtbox: Hurtbox) -> bool:
	if not _active:
		return false
	var id := hurtbox.get_instance_id()
	if _hit_ids.has(id):
		return false
	_hit_ids[id] = true
	return true


func _on_area_entered(area: Area3D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox == null or not hurtbox.can_be_hit() or not register_hit(hurtbox):
		return
	var source: Node = get_owner()
	if source == null:
		source = get_parent()
	hurtbox.receive_hit(damage, source)
	_play_impact(hurtbox)
	if source != null and source.is_in_group(&"player") and is_inside_tree():
		# Hit-stop only on Kaelen's hits; she says how strong (light slash vs finisher / slam).
		var stop: float = source.call(&"hit_stop_time") if source.has_method(&"hit_stop_time") else HitStop.HIT_DURATION
		HitStop.request(get_tree(), stop)
	# Events may not exist (tests run with -s), so it is looked up by path.
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.hit_landed.emit(hurtbox.global_position, hurtbox.surface)


func _play_impact(hurtbox: Hurtbox) -> void:
	var stream := impact_stream_for(hurtbox.surface)
	if stream == null or not claim_impact_sound():
		return
	# By path: tests run with -s, without autoloads.
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio:
		audio.play_sfx_3d(stream, hurtbox.global_position)
