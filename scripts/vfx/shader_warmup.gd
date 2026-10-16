class_name ShaderWarmup
extends SubViewport
## Precalentamiento de los efectos de un jefe. En gl_compatibility cada shader se compila la PRIMERA
## vez que se dibuja: el rayo de Ghidorah (5 shaders y 2 sistemas de particulas) congelaba el juego
## ~120 ms en su primer disparo y los avisos rojos del suelo unos 20-50 ms en el primer ataque.
## Aqui se dibujan una vez, durante la carga y fuera de pantalla (un SubViewport de 64x64 con su
## propio mundo 3D), copias de cada efecto visual y de cada aviso de los ataques; despues se libera.
## Tambien se reproduce una vez cada animacion de ataque para que el AnimationPlayer resuelva sus
## pistas (el modelo de Ghidorah tiene cientos). Se omite sin ventana (pruebas, --headless).

const FRAMES := 3
const DISTANCE := 3.0

var _frames_left := FRAMES


## Prepara el precalentamiento de `boss` (llamar desde su _ready, ya dentro del arbol).
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
			# Un efecto instanciado de una escena (el rayo) se vuelve a instanciar: duplicate() llama a los
			# setters de su script antes de que existan sus nodos hijos.
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
	if count == 0:
		warm.free()
		return null
	boss.add_child.call_deferred(warm)
	return warm


func _ready() -> void:
	# Los efectos con apertura animada (el rayo) se muestran abiertos del todo; sus nodos hijos
	# solo existen aqui, ya dentro del arbol.
	for child in get_children():
		if "open_amount" in child:
			child.set(&"open_amount", 1.0)
			child.set_process(false)


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left <= 0:
		queue_free()
