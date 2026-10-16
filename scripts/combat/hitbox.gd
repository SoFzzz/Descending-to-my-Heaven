class_name Hitbox
extends Area3D
## Zona que hace daño mientras está activa; golpea cada Hurtbox una sola vez por activación.

@export var damage: int = 0
## Sonido de impacto de este golpe: suena UNA vez por activación (aunque toque varias hurtboxes),
## en la posición de la primera. `sfx_impact_metal` lo sustituye si esa hurtbox es de superficie `metal`.
@export var sfx_impact: AudioStream
@export var sfx_impact_metal: AudioStream

var _hit_ids: Dictionary = {}
var _active := false
var _impact_played := false


func _init() -> void:
	monitoring = false  # empieza inactiva, también fuera del árbol


func _ready() -> void:
	area_entered.connect(_on_area_entered)


# Diferido: cambiar monitoring dentro de callbacks de física está bloqueado por Godot.
func activate() -> void:
	_hit_ids.clear()
	_impact_played = false
	_active = true
	set_deferred(&"monitoring", true)


func deactivate() -> void:
	_active = false
	set_deferred(&"monitoring", false)


## true solo la primera vez por activación: el sonido de impacto se reproduce una vez por golpe.
func claim_impact_sound() -> bool:
	if _impact_played:
		return false
	_impact_played = true
	return true


## Sonido de impacto para una hurtbox de superficie `surface` (null si no hay).
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
		HitStop.request(get_tree())   # pausa de impacto solo en los golpes de Kaelen
	# Events puede no existir (pruebas con -s), por eso se busca por ruta.
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
