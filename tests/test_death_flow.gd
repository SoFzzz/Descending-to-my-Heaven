extends TestCase
# Pantalla de muerte: estructura (3 botones, theme compartido) y textos de respaldo. El flujo
# completo (foco, pausa, música única, vida llena al reintentar) está en tests/flow/death_flow.tscn,
# que necesita árbol y autoloads reales.

const DeathScreen := preload("res://scripts/ui/death_screen.gd")


func test_fallback_text_uses_spanish_when_key_is_untranslated() -> void:
	assert_eq(DeathScreen.fallback_text("DEATH_TITLE", "DEATH_TITLE"), "HAS MUERTO")
	assert_eq(DeathScreen.fallback_text("DEATH_RETRY", "DEATH_RETRY"), "Reintentar")
	assert_eq(DeathScreen.fallback_text("DEATH_MENU", "DEATH_MENU"), "Volver al menú")
	assert_eq(DeathScreen.fallback_text("DEATH_QUIT", "DEATH_QUIT"), "Salir del juego")
	assert_eq(DeathScreen.fallback_text("DEATH_RETRY", "Retry"), "Retry", "con traducción se respeta")


func test_death_screen_scene_has_three_buttons_with_shared_theme() -> void:
	var screen: Node = (load("res://scenes/ui/death_screen.tscn") as PackedScene).instantiate()
	var box := screen.get_node(^"Root/Column/Center/Panel/Box")
	assert_eq(box.get_child_count(), 3, "3 botones")
	for child in box.get_children():
		assert_true(child is Button, child.name)
	assert_eq(String(box.get_child(0).name), "Retry", "Reintentar es el primero")
	assert_true((screen.get_node(^"Root") as Control).theme.resource_path.ends_with("menu_theme.tres"))
	assert_eq(screen.process_mode, Node.PROCESS_MODE_ALWAYS)
	screen.free()


func test_stamina_refill_restores_and_notifies() -> void:
	var stamina := Stamina.new()
	stamina.current = 10.0
	var seen := [0.0]
	stamina.changed.connect(func(current: float, _max: float) -> void: seen[0] = current)
	stamina.refill()
	assert_almost(stamina.current, stamina.max_value)
	assert_almost(seen[0], stamina.max_value)
	stamina.free()
