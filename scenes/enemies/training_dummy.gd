extends StaticBody3D
## Test dummy: takes hits from the greatsword (Hurtbox layer 8 → Health 30) and disappears on death.
## It is in the "lockable" group with its LockOnPoint at 1.3 m. It is not in "enemy" (the
## Orchestrator does not count it).

@onready var health: Health = $Health


func _ready() -> void:
	health.died.connect(_on_died)


func _on_died() -> void:
	# died is emitted from a physics signal (area_entered): it is freed at the end of the frame.
	remove_from_group(&"lockable")
	queue_free()
