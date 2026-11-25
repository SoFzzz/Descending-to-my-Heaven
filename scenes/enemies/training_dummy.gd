extends StaticBody3D
## Test dummy: takes hits from the greatsword (Hurtbox layer 8 → Health 30) and disappears on death.
## It is in the "lockable" group with its LockOnPoint at 1.3 m. It is not in "enemy" (the
## Orchestrator does not count it). It looks like the Straw Reaper (its model, a scarecrow of the
## third floor) frozen in a fixed pose: POSE_CLIP at POSE_TIME, the AnimationPlayer paused (it does
## not move nor cost anything per frame). It flashes on each hit like the enemies.

const PSX := preload("res://scenes/levels/psx_test.gd")
const POSE_CLIP := &"idle"
const POSE_TIME := 0.0

@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var model: Node3D = $Model


func _ready() -> void:
	health.died.connect(_on_died)
	hurtbox.hurt.connect(_on_hurt)
	PSX.apply_psx(model)
	_freeze_pose()


## Poses the model with POSE_CLIP at POSE_TIME and pauses its AnimationPlayer.
func _freeze_pose() -> void:
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim == null or not anim.has_animation(POSE_CLIP):
		push_warning("TrainingDummy: the model has no '%s' clip." % POSE_CLIP)
		return
	anim.play(POSE_CLIP)
	anim.seek(POSE_TIME, true)
	anim.pause()


## True if the model's AnimationPlayer holds the fixed pose (paused on POSE_CLIP).
func is_pose_frozen() -> bool:
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	return anim != null and anim.assigned_animation == POSE_CLIP and not anim.is_playing()


# The Hurtbox only flashes boss / minion / player models (HitFlash.model_for): the dummy does it here.
func _on_hurt(amount: int, _source: Node) -> void:
	if amount > 0:
		HitFlash.flash(model)


func _on_died() -> void:
	# died is emitted from a physics signal (area_entered): it is freed at the end of the frame.
	remove_from_group(&"lockable")
	queue_free()
