extends Node
## Prueba de humo del Modo B. Ejecutar:
##   godot --headless --path . res://tests/VictoriaSmokeTest.tscn
## Sale con código 0 si todo pasa, 1 si algo falla.

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		print("  FAIL ", msg)
		failures.append(msg)


func _ready() -> void:
	await get_tree().process_frame
	print("== Victoria mode smoke test ==")
	var t0 := Time.get_ticks_msec()
	var game: Node = load("res://src/victoria_mode/VictoriaGame.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	print("  carga de escena: %d ms" % (Time.get_ticks_msec() - t0))
	var gs: VGameState = game.gs

	check(gs.first_sea_id - 1 > 2000, "más de 2000 provincias terrestres (%d)" % (gs.first_sea_id - 1))
	check(gs.states.size() > 500, "más de 500 estados (%d)" % gs.states.size())
	check(gs.living_countries().size() > 60, "más de 60 naciones vivas (%d)" % gs.living_countries().size())
	check(gs.date.year == 136, "fecha inicial año 136")
	var multi_state := 0
	for tag in gs.living_countries():
		if gs.country_state_instances(tag).size() >= 3:
			multi_state += 1
	check(multi_state >= 30, "al menos 30 naciones con 3+ estados (%d)" % multi_state)
	var split := 0
	for sid in gs.states:
		if gs.state_is_split(sid):
			split += 1
	check(split > 0, "existen estados divididos entre propietarios (%d)" % split)
	var gps := 0
	for tag in gs.countries:
		if gs.countries[tag]["status"] == "great_power":
			gps += 1
	check(gps == 8, "8 grandes potencias")

	# picking: el centro de la capital de Frankia debe devolver esa provincia
	var cap := int(gs.countries["FRK"]["capital"])
	var picked: int = game.world_map.province_at(gs.provinces[cap]["center"])
	check(picked == cap, "picking por píxel en la capital de Frankia (%d == %d)" % [picked, cap])

	# selección de país y juego
	game._on_map_clicked(gs.provinces[cap]["center"])
	check(game.select_focus_tag == "FRK", "clic en el mapa selecciona la nación propietaria")
	game._start_playing("FRK")
	check(gs.player_tag == "FRK" and game.top_bar.visible, "JUGAR inicia la partida con barra superior")

	for m in VMapModes.MODES:
		if m["available"]:
			game.set_mapmode(m["id"])
	check(true, "todos los mapmodes disponibles se calculan sin error")
	game.set_mapmode("political")

	game._select_province(cap)
	check(game.province_panel.visible, "panel de provincia visible al seleccionar")
	for key in ["production", "budget", "technology", "politics", "population", "trade", "diplomacy", "military", "alerts"]:
		game.nation_window.open(key)
	game.nation_window.close()
	check(true, "todas las pestañas nacionales se construyen")

	var treasury0 := float(gs.countries["FRK"]["treasury"])
	var pop0 := gs.country_population("FRK")
	for i in 62:
		game.clock._tick()
	check(gs.date.month == 3 and gs.date.day == 4, "62 días avanzan la fecha a 4 de marzo (%s)" % gs.date.text())
	check(float(gs.countries["FRK"]["treasury"]) != treasury0, "el tesoro cambia con el tiempo")
	check(gs.country_population("FRK") != pop0, "la población cambia mensualmente")

	# ocupación (owner ≠ controller) y cambio de propietario sin tocar geometría
	var some: int = gs.countries["FRK"]["provinces"][1]
	gs.provinces[some]["controller"] = "BRM"
	game.world_map.refresh_overlay()
	check(gs.provinces[some]["owner"] == "FRK", "ocupar no cambia el propietario")
	gs.provinces[some]["controller"] = "FRK"
	gs.change_owner([some], "BRM")
	check(gs.provinces[some]["owner"] == "BRM" and some in gs.countries["BRM"]["provinces"], "change_owner transfiere la provincia")
	gs.change_owner([some], "FRK")

	# guardado / carga
	var path := VSaveSystem.save_game(gs, "smoke_test")
	check(path != "" and FileAccess.file_exists(path), "guardado escrito")
	var err := []
	var gs2 := VSaveSystem.load_game(path, err)
	check(gs2 != null and gs2.player_tag == "FRK" and gs2.date.text() == gs.date.text(), "carga restaura nación y fecha")
	if gs2:
		check(gs2.country_population("FRK") == gs.country_population("FRK"), "carga restaura POPs")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("== %d fallos ==" % failures.size())
	for f in failures:
		print("   - ", f)
	get_tree().quit(1 if not failures.is_empty() else 0)
