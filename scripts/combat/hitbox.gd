class_name Hitbox
extends Area3D
## Zona que hace daño mientras está activa; golpea cada Hurtbox una sola vez por activación.

@export var damage: int = 0

var _hit_ids: Dictionary = {}
var _active := false


func _init() -> void:
	monitoring = false  # empieza inactiva, también fuera del árbol


func _ready() -> void:
	area_entered.connect(_on_area_entered)


# Diferido: cambiar monitoring dentro de callbacks de física está bloqueado por Godot.
func activate() -> void:
	_hit_ids.clear()
	_active = true
	set_deferred(&"monitoring", true)


func deactivate() -> void:
	_active = false
	set_deferred(&"monitoring", false)


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
	# Events puede no existir (pruebas con -s), por eso se busca por ruta.
	var events := get_node_or_null(^"/root/Events")
	if events:
		events.hit_landed.emit(hurtbox.global_position, hurtbox.surface)
