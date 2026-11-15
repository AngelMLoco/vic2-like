extends Node
## Capturas automáticas del Modo B para revisión visual (requiere ventana, no headless):
##   godot --path . res://tests/VictoriaScreenshots.tscn -- <carpeta_salida>

var out_dir := "user://screenshots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(3)
	var menu: Node = load("res://src/app/MainMenu.tscn").instantiate()
	add_child(menu)
	await _frames(6)
	await _shot("01_main_menu")
	menu._show_page("mode")
	await _frames(3)
	await _shot("02_mode_select")
	menu.queue_free()

	var game: Node = load("res://src/victoria_mode/VictoriaGame.tscn").instantiate()
	add_child(game)
	await _frames(10)
	var gs: VGameState = game.gs
	game.camera.center_on(Vector2(gs.map_width * 0.5, gs.map_height * 0.4), game.camera.min_zoom)
	await _frames(40)
	await _shot("03_country_select_world")
	var cap := int(gs.countries["FRK"]["capital"])
	game._on_map_clicked(gs.provinces[cap]["center"])
	game._focus_country("FRK")
	await _frames(50)
	await _shot("04_country_select_frankia")
	game._start_playing("FRK")
	game.camera.center_on(gs.provinces[cap]["center"] + Vector2(120, -60), 0.95)
	await _frames(50)
	game._select_province(cap)
	await _frames(5)
	await _shot("05_playing_states_zoom")
	game.camera.center_on(gs.provinces[cap]["center"], 2.6)
	await _frames(50)
	await _shot("06_provinces_zoom")
	game._select_province(0)
	game.camera.center_on(Vector2(gs.map_width * 0.55, gs.map_height * 0.33), 0.5)
	await _frames(50)
	game.set_mapmode("culture")
	await _frames(5)
	await _shot("07_mapmode_culture")
	game.set_mapmode("resources")
	await _frames(5)
	await _shot("08_mapmode_resources")
	game.set_mapmode("diplomatic")
	await _frames(5)
	await _shot("09_mapmode_diplomatic")
	game.set_mapmode("political")
	game.nation_window.open("population")
	await _frames(5)
	await _shot("10_population_window")
	game.nation_window.open("budget")
	await _frames(5)
	await _shot("11_budget_window")
	game.nation_window.open("production")
	await _frames(5)
	await _shot("12_production_window")
	game.nation_window.close()
	# ocupación visible
	var bcap := int(gs.countries["BRM"]["capital"])
	var ids: Array = [bcap]
	for n in gs.provinces[bcap]["neighbors"]:
		if gs.provinces[n].get("owner", "") == "BRM":
			ids.append(n)
	for id in ids:
		gs.provinces[id]["controller"] = "FRK"
		print("ocupada: ", gs.provinces[id]["name"])
	game.world_map.refresh_overlay()
	game.camera.center_on(gs.provinces[bcap]["center"], 2.4)
	await _frames(50)
	await _shot("13_occupation_overlay")
	print("capturas en ", ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("user://") else out_dir)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
