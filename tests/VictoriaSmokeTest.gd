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

	# ================= Milestone 2: población, economía, política, tecnología =================
	print("-- milestone 2")
	var frk: Dictionary = gs.countries["FRK"]
	var any_pop: int = gs.provinces[cap]["pop_slots"][0]
	var basket := VPopulationSystem.needs_basket(gs, gs.pops.type_name(any_pop), "life")
	var pop_d := gs.pops.get_pop_details(any_pop)
	check(not basket.is_empty() and pop_d.has("needs_satisfaction") and pop_d.has("cash") and pop_d.has("issues"), "los POPs tienen necesidades, efectivo e issues")
	# un mes completo de simulación
	var lit0 := float(frk["literacy"])
	for i in 31:
		game.clock._tick()
	var incomes := 0
	for id in frk["provinces"]:
		for pop in gs.provinces[id]["pop_slots"]:
			if gs.pops.income[pop] > 0.0:
				incomes += 1
	check(incomes > 100, "los POPs reciben renta (%d POPs con ingresos)" % incomes)
	var w: Dictionary = gs.market["world"]
	check(float(w["supply"].get("grain", 0.0)) > 0.0 and float(w["demand"].get("grain", 0.0)) > 0.0, "los bienes tienen oferta y demanda (grano %.0f / %.0f)" % [float(w["supply"].get("grain", 0.0)), float(w["demand"].get("grain", 0.0))])
	var changed := 0
	for g in gs.market["price"]:
		if absf(float(gs.market["price"][g]) - float(gs.market["base"][g])) > 0.001:
			changed += 1
	check(changed > 10, "los precios cambian (%d bienes)" % changed)
	var rgo_out := 0.0
	for id in frk["provinces"]:
		rgo_out += float(gs.provinces[id]["rgo_data"]["output"])
	check(rgo_out > 0.0, "los RGO producen (%.0f unidades/mes en Frankia)" % rgo_out)
	var consumed := false
	var produced := false
	for key in gs.state_instances:
		for f in gs.state_instances[key]["factories"]:
			if float(f["output"]) > 0.0:
				produced = true
			if float(f["expenses"]) > 0.0 and not f["stock"].is_empty():
				consumed = true
	check(consumed, "las fábricas compran y consumen insumos")
	check(produced, "las fábricas producen")
	var needs_ok := true
	for pop in gs.provinces[cap]["pop_slots"]:
		if not (gs.pops.life[pop] >= 0.0 and gs.pops.life[pop] <= 1.0):
			needs_ok = false
	check(needs_ok, "satisfacción de necesidades en [0,1]")
	# desempleo forzado: un RGO sin plazas
	var test_p: Dictionary = gs.provinces[int(frk["provinces"][3])]
	var saved_size := float(test_p["rgo_data"]["base_size"])
	test_p["rgo_data"]["base_size"] = 0.01
	VProductionSystem.process_province(gs, int(test_p["id"]))
	var wt := VProductionSystem.rgo_worker_type(gs, test_p["rgo"])
	var unemployed := false
	for pop in test_p["pop_slots"]:
		if gs.pops.type_name(pop) == wt and gs.pops.employment[pop] < 0.5:
			unemployed = true
	check(unemployed, "puede haber desempleo real (RGO sin plazas)")
	test_p["rgo_data"]["base_size"] = saved_size
	# presupuesto e impuestos
	frk["budget"]["tax_poor"] = 0.05
	var farmer := -1
	for pop in gs.provinces[cap]["pop_slots"]:
		if gs.pops.type_id[pop] == gs.pops.T_FARMERS:
			farmer = pop
	var before_cash: float = gs.pops.cash[farmer]
	VBudgetSystem.credit_income(gs, "FRK", farmer, 100.0)
	var net_low: float = gs.pops.cash[farmer] - before_cash
	frk["budget"]["tax_poor"] = 0.6
	before_cash = gs.pops.cash[farmer]
	VBudgetSystem.credit_income(gs, "FRK", farmer, 100.0)
	var net_high: float = gs.pops.cash[farmer] - before_cash
	check(net_high < net_low, "los impuestos reducen la renta neta de los POPs (%.1f < %.1f)" % [net_high, net_low])
	var t_before := float(frk["treasury"])
	for i in 30:
		game.clock._tick()
	check(float(frk["budget_last"]["tax_poor"]) > 0.0 and float(frk["treasury"]) != t_before, "el presupuesto mueve el tesoro (impuestos pobres %.0f)" % float(frk["budget_last"]["tax_poor"]))
	frk["budget"]["tax_poor"] = 0.15
	# aranceles
	var imp_good := ""
	for g in gs.market["import_share"].get("FRK", {}):
		if float(gs.market["import_share"]["FRK"][g]) > 0.05:
			imp_good = g
	frk["budget"]["tariffs"] = 0.0
	var p0 := VMarketSystem.buy_price(gs, "FRK", imp_good) if imp_good != "" else 0.0
	frk["budget"]["tariffs"] = 0.5
	var p1 := VMarketSystem.buy_price(gs, "FRK", imp_good) if imp_good != "" else 0.0
	check(imp_good != "" and p1 > p0, "los aranceles encarecen las importaciones (%s: %.2f → %.2f)" % [imp_good, p0, p1])
	frk["budget"]["tariffs"] = 0.1
	# elecciones (Britannia tiene monarquía parlamentaria)
	var res := VPoliticsSystem.hold_election(gs, "BRI")
	check(float(res.get("total", 0.0)) > 0.0, "se pueden celebrar elecciones con POPs reales (%s)" % VPoliticsSystem.ruling_party(gs, "BRI").get("name", "?"))
	# reformas por niveles
	var bri: Dictionary = gs.countries["BRI"]
	bri["upper_house"] = {"liberal": 0.8, "conservador": 0.2}
	bri["reform_cooldown"] = 0
	var lvl0 := gs.reform_level("BRI", "press")
	check(not VPoliticsSystem.can_change_reform(gs, "BRI", "school_system", 1)["ok"], "una cámara liberal rechaza ampliar reformas sociales")
	var r_err := VPoliticsSystem.change_reform(gs, "BRI", "trade_unions", 1)
	check(r_err == "" and gs.reform_level("BRI", "trade_unions") == 1, "una reforma política avanza un nivel con una cámara liberal (%s)" % (r_err if r_err != "" else gs.reforms["trade_unions"]["levels"][1]["name"]))
	check(VPoliticsSystem.change_reform(gs, "BRI", "voting", 1) != "", "no se puede cambiar otra reforma durante el tiempo de espera")
	check(gs.reform_level("BRI", "press") == lvl0, "las reformas no saltan de nivel")
	# tecnología e inventos
	var techs0: int = frk["technologies"].size()
	var avail := VTechnologySystem.available(gs, "FRK")
	check(not avail.is_empty() and VTechnologySystem.set_research(gs, "FRK", avail[0]), "se puede elegir investigación")
	frk["research_progress"] = float(gs.technologies[avail[0]]["cost"])
	VTechnologySystem.monthly(gs, "FRK", true)
	check(frk["technologies"].size() > techs0, "la tecnología se completa (%s)" % gs.technologies[avail[0]]["name"])
	var pool := VTechnologySystem.invention_pool(gs, "FRK")
	if pool.is_empty():
		VTechnologySystem.complete(gs, "FRK", "water_mills")
		pool = VTechnologySystem.invention_pool(gs, "FRK")
	var mods_before: Dictionary = frk["mods"].duplicate()
	VTechnologySystem.activate_invention(gs, "FRK", pool[0])
	check(pool[0] in frk["inventions"] and frk["mods"] != mods_before, "un invento se activa y cambia modificadores (%s)" % gs.inventions[pool[0]]["name"])
	# un año completo sin intervención
	var y0 := gs.date.year
	var t_year := Time.get_ticks_msec()
	for i in 365:
		game.clock._tick()
	print("  un año simulado con interfaz en %.1f s" % ((Time.get_ticks_msec() - t_year) / 1000.0))
	check(gs.date.year == y0 + 1, "la simulación avanza un año completo sin error")
	check(absf(float(frk["literacy"]) - lit0) > 0.0005, "la alfabetización cambia (%.3f → %.3f)" % [lit0, float(frk["literacy"])])
	var promo := 0
	var migr := 0
	for tag in gs.countries:
		var m: Dictionary = gs.countries[tag].get("acc_mobility_last", {})
		promo += int(m.get("promoted", 0)) + int(m.get("changed_job", 0))
		migr += int(m.get("migrated", 0))
	check(promo > 0, "hay promoción/cambio de oficio (%d el último mes)" % promo)
	check(migr > 0, "hay migración interna (%d el último mes)" % migr)
	check(int(frk["rank"]) > 0 and gs.country_population("FRK") > 1000000, "Frankia sigue viva tras un año")
	for key in ["production", "budget", "technology", "politics", "population", "trade", "alerts"]:
		game.nation_window.open(key)
	game.nation_window.close()
	check(true, "las pestañas del milestone 2 se construyen con datos simulados")
	print(VProfiler.report(gs))

	# guardado / carga
	var path := VSaveSystem.save_game(gs, "smoke_test")
	check(path != "" and FileAccess.file_exists(path), "guardado escrito")
	var err := []
	var gs2 := VSaveSystem.load_game(path, err)
	check(gs2 != null and gs2.player_tag == "FRK" and gs2.date.text() == gs.date.text(), "carga restaura nación y fecha")
	if gs2:
		check(gs2.country_population("FRK") == gs.country_population("FRK"), "carga restaura POPs")
		var f2: Dictionary = gs2.countries["FRK"]
		check(absf(float(f2["treasury"]) - float(frk["treasury"])) < 0.01 and absf(float(f2.get("debt", 0.0)) - float(frk.get("debt", 0.0))) < 0.01, "carga restaura tesoro y deuda")
		check(absf(float(gs2.market["price"]["grain"]) - float(gs.market["price"]["grain"])) < 0.0001, "carga restaura precios del mercado")
		check(f2["technologies"] == frk["technologies"] and f2["reforms"] == frk["reforms"], "carga restaura tecnologías y reformas")
		var fc1 := 0
		var fc2 := 0
		for key in gs.state_instances:
			fc1 += gs.state_instances[key]["factories"].size()
		for key in gs2.state_instances:
			fc2 += gs2.state_instances[key]["factories"].size()
		check(fc1 == fc2, "carga restaura las fábricas (%d)" % fc1)
		var cash1 := 0.0
		var cash2 := 0.0
		for id in frk["provinces"]:
			for pop in gs.provinces[id]["pop_slots"]:
				cash1 += gs.pops.cash[pop]
			for pop in gs2.provinces[id]["pop_slots"]:
				cash2 += gs2.pops.cash[pop]
		check(absf(cash1 - cash2) < 0.5, "carga restaura el efectivo de los POPs")
	var bad := {"save_version": 1, "mode": "victoria_mode", "header": {}}
	var bad_path := "user://victoria_mode/saves/_v1_test.json"
	var fh := FileAccess.open(bad_path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(bad))
	fh.close()
	var err2 := []
	check(VSaveSystem.load_game(bad_path, err2) == null and not err2.is_empty(), "una partida v1 se rechaza con un mensaje limpio")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("== %d fallos ==" % failures.size())
	for f in failures:
		print("   - ", f)
	get_tree().quit(1 if not failures.is_empty() else 0)
