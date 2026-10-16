class_name ShaderWarmup
extends SubViewport
## Warm-up of a boss's effects. In gl_compatibility each shader is compiled the FIRST time it is
## drawn: Ghidorah's beam (5 shaders and 2 particle systems) froze the game ~120 ms on its first
## shot and the red floor telegraphs about 20-50 ms on the first attack.
## Here copies of each visual effect and of each attack telegraph are drawn once, during loading and
## off screen (a 64x64 SubViewport with its own 3D world); afterwards it frees itself.
## It is skipped without a window (tests, --headless).

const FRAMES := 3
const DISTANCE := 3.0

var _frames_left := FRAMES


## Prepares the warm-up of `boss` (call from its _ready, already inside the tree).
static func start(boss: Boss) -> ShaderWarmup:
	if DisplayServer.get_name() == "headless" or not boss.is_inside_tree():
		return null
	var warm := ShaderWarmup.new()
	warm.size = Vector2i(64, 64)
	warm.own_world_3d = true
	warm.transparent_bg = true
	warm.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	warm.audio_listener_enable_3d = false
	var camera := Camera3D.new()
	camera.far = 40.0
	warm.add_child(camera)
	var count := 0
	for attack in boss.attacks:
		for path in [attack.visual_path, NodePath("Telegraphs/%s" % attack.id)]:
			var source := boss.get_node_or_null(path) as Node3D
			if source == null:
				continue
			# An effect instanced from a scene (the beam) is instanced again: duplicate() calls its
			# script's setters before its child nodes exist.
			var copy: Node3D
			if source.scene_file_path != "":
				copy = (load(source.scene_file_path) as PackedScene).instantiate() as Node3D
			else:
				copy = source.duplicate() as Node3D
			warm.add_child(copy)
			copy.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -DISTANCE))
			copy.visible = true
			for child in copy.find_children("*", "Node3D", true, false):
				(child as Node3D).visible = true
			count += 1
	# Impact effects, seals and wind (ImpactFx, MagicArea, StormFX): their shaders are compiled here.
	for sample in ImpactFx.warmup_samples():
		warm.add_child(sample)
		sample.position = Vector3(0.0, -0.4, -DISTANCE)
		count += 1
	if count == 0:
		warm.free()
		return null
	_attach.call_deferred(boss, warm)
	return warm


## Adds `warm` to `boss` once the frame ends; frees it if the boss is gone by then (no orphan).
static func _attach(boss: Variant, warm: ShaderWarmup) -> void:
	if is_instance_valid(boss) and (boss as Node).is_inside_tree():
		boss.add_child(warm)
	else:
		warm.free()


func _ready() -> void:
	# Effects with an animated opening (the beam) are shown fully open; their child nodes
	# only exist here, once inside the tree.
	for child in get_children():
		if child is CPUParticles3D:
			(child as CPUParticles3D).emitting = true   # ImpactFx sparks and dust
		if "open_amount" in child:
			child.set(&"open_amount", 1.0)
			child.set_process(false)


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left <= 0:
		queue_free()
