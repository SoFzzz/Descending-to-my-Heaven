class_name DialogueBox
extends Control
## Caja de diálogo del final (estilo de la banda de la pantalla de muerte): banda negra semitransparente
## abajo, nombre del hablante arriba (DungeonFont, un color por personaje) y su texto debajo, revelado
## con Typewriter. Una sola línea de un solo hablante a la vez; el narrador no lleva nombre y va
## centrado en gris. El prefijo "Kaelen:" / "Elysia:" del texto traducido solo sirve para detectar
## el hablante: no se muestra. Con la línea completa aparece un triángulo ▼ parpadeante; la caja
## emite `advanced` cuando el jugador pulsa avanzar (ver Typewriter para las teclas y el bloqueo).

signal advanced
signal line_finished

const MENU_THEME := preload("res://scenes/ui/menu_theme.tres")
const DUNGEON_FONT := preload("res://assets/fonts/DungeonFont.ttf")

const BAND_HEIGHT := 112.0
const BAND_ALPHA := 0.88
const SIDE_MARGIN := 64.0
const NAME_FONT_SIZE := 26
const TEXT_FONT_SIZE := 14
const TEXT_LINES := 2
const MARKER_BLINK := 0.45

## Nombre que se muestra y color del nombre por hablante (Skin04: gris/negro/blanco con un toque cálido o frío).
const SPEAKER_NAMES := {&"kaelen": "Kaelen", &"elysia": "Elysia"}
const SPEAKER_COLORS := {
	&"kaelen": Color(0.78, 0.22, 0.2),
	&"elysia": Color(0.74, 0.82, 0.95),
}
const NARRATOR_COLOR := Color(0.72, 0.72, 0.76)
const TEXT_COLOR := Color(0.94, 0.94, 0.97)

var typewriter: Typewriter
var name_label: Label
var text_label: Label
var marker: Polygon2D
var band: TextureRect
var current_speaker: StringName = &""
var current_body := ""
var _marker_tween: Tween


# --- Lógica pura ---------------------------------------------------------------------------

## {speaker: StringName (&"" = narrador), name: String, body: String} de una línea de diálogo.
static func parse_line(line: String) -> Dictionary:
	var speaker := Typewriter.speaker_of(line)
	var body := line.substr(Typewriter.prefix_length(line)).strip_edges()
	return {"speaker": speaker, "name": SPEAKER_NAMES.get(speaker, ""), "body": body}


static func color_for(speaker: StringName) -> Color:
	return SPEAKER_COLORS.get(speaker, NARRATOR_COLOR)


## Banda con el degradado vertical de la pantalla de muerte: transparente, negro, negro, transparente.
static func make_band_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.78, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0), Color(0, 0, 0, BAND_ALPHA), Color(0, 0, 0, BAND_ALPHA), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	return tex


# --- Construcción --------------------------------------------------------------------------

func _ready() -> void:
	theme = MENU_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modulate.a = 0.0

	band = TextureRect.new()
	band.texture = make_band_texture()
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -BAND_HEIGHT
	add_child(band)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	column.offset_top = -BAND_HEIGHT + 16.0
	column.offset_bottom = -22.0
	column.offset_left = SIDE_MARGIN
	column.offset_right = -SIDE_MARGIN
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 2)
	add_child(column)

	name_label = Label.new()
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)
	name_label.add_theme_constant_override(&"outline_size", 4)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	text_label = Label.new()
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override(&"font_size", TEXT_FONT_SIZE)
	text_label.add_theme_color_override(&"font_color", TEXT_COLOR)
	text_label.add_theme_constant_override(&"line_spacing", 1)
	text_label.custom_minimum_size = Vector2(0, TEXT_LINES * 19.0)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(text_label)

	marker = Polygon2D.new()
	marker.polygon = PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(5, 7)])
	marker.color = Color(0.94, 0.94, 0.97)
	marker.visible = false
	add_child(marker)
	# Esquina inferior derecha de la caja (Control anclado: se coloca en _notification/resized).
	resized.connect(_place_marker)
	_place_marker()

	typewriter = Typewriter.new()
	add_child(typewriter)
	typewriter.finished.connect(_on_line_finished)
	typewriter.advanced.connect(_on_advanced)


func _place_marker() -> void:
	if marker:
		marker.position = Vector2(size.x - SIDE_MARGIN - 4.0, size.y - 32.0)


# --- Uso -----------------------------------------------------------------------------------

## Muestra una línea ("Kaelen: texto", "Elysia: texto" o narración sin prefijo) y empieza a revelarla.
func show_line(line: String) -> void:
	var parsed := parse_line(line)
	current_speaker = parsed["speaker"]
	current_body = parsed["body"]
	_set_marker(false)
	var narrator := current_speaker == &""
	name_label.visible = not narrator
	name_label.text = parsed["name"]
	name_label.add_theme_color_override(&"font_color", color_for(current_speaker))
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if narrator else HORIZONTAL_ALIGNMENT_LEFT
	text_label.add_theme_color_override(&"font_color", NARRATOR_COLOR if narrator else TEXT_COLOR)
	typewriter.start(text_label, current_body, current_speaker)


func fade(alpha: float, time: float) -> void:
	create_tween().tween_property(self, "modulate:a", alpha, time)


func _on_line_finished() -> void:
	_set_marker(true)
	line_finished.emit()


func _on_advanced() -> void:
	_set_marker(false)
	advanced.emit()


func _set_marker(on: bool) -> void:
	if _marker_tween and _marker_tween.is_valid():
		_marker_tween.kill()
	marker.visible = on
	marker.modulate.a = 1.0
	if on and is_inside_tree():
		_marker_tween = create_tween().set_loops()
		_marker_tween.tween_property(marker, "modulate:a", 0.15, MARKER_BLINK)
		_marker_tween.tween_property(marker, "modulate:a", 1.0, MARKER_BLINK)
