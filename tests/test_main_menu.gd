extends TestCase
# Main menu: buttons, island silhouette and float/spin animation. (Tests run before
# the scene tree exists, so only loose instances and static functions are used.)


func test_menu_scene_has_the_three_buttons_in_the_left_half() -> void:
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	var start := menu.get_node(^"%Start") as Button
	var credits := menu.get_node(^"%Credits") as Button
	var quit := menu.get_node(^"%Quit") as Button
	assert_eq(start.text, "MENU_START", "the buttons carry translation keys")
	assert_eq(credits.text, "MENU_CREDITS")
	assert_eq(quit.text, "MENU_QUIT")
	assert_true(menu.get_node(^"%Options") is Button, "Options button")
	TranslationServer.set_locale("es")
	assert_eq(TranslationServer.translate(&"MENU_START"), "Iniciar")
	assert_eq(TranslationServer.translate(&"MENU_QUIT"), "Salir")
	assert_eq(start.focus_mode, Control.FOCUS_ALL)
	var panel := menu.get_node(^"UI/Root/Panel") as Control
	assert_true(panel.offset_right <= 320.0, "panel stays in the left half")
	var island := menu.get_node(^"UI/Root/Island") as Control
	assert_almost(island.anchor_left, 0.5)
	assert_almost(island.anchor_right, 1.0)
	menu.free()


func test_island_material_is_pure_black_and_unshaded() -> void:
	var material := IslandSilhouette.silhouette_material()
	assert_eq(material.albedo_color, Color.BLACK)
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)


func test_island_models_exist() -> void:
	assert_true(ResourceLoader.exists(IslandSilhouette.ISLAND_DIR + IslandSilhouette.MAIN_ISLAND + ".glb"))
	for islet: Dictionary in IslandSilhouette.ISLETS:
		assert_true(ResourceLoader.exists(IslandSilhouette.ISLAND_DIR + String(islet[&"model"]) + ".glb"), islet[&"model"])


func test_island_floats_and_spins_over_time() -> void:
	assert_almost(IslandSilhouette.bob_offset(0.0), 0.0)
	assert_almost(IslandSilhouette.bob_offset(IslandSilhouette.BOB_PERIOD * 0.25), IslandSilhouette.BOB_AMPLITUDE)
	assert_almost(IslandSilhouette.bob_offset(IslandSilhouette.BOB_PERIOD * 0.75), -IslandSilhouette.BOB_AMPLITUDE)
	assert_true(IslandSilhouette.spin_angle(1.0) > IslandSilhouette.spin_angle(0.0), "it turns")
	assert_true(IslandSilhouette.spin_angle(1000.0) < TAU, "the angle wraps")
