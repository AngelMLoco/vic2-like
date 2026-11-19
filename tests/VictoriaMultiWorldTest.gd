extends Node
## M6: arquitectura multi-mundo. Registro de mundos, escenario → mundo, aislamiento entre mundos (Tierra →
## mundo de prueba → Tierra sin contaminación), validador, mundo fantástico importado jugable, guardado con
## identidad del mundo y rechazo de versiones de mapa incorrectas.
##   godot --headless --path . res://tests/VictoriaMultiWorldTest.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	await get_tree().process_frame
	test_registry()
	test_validator()
	test_isolation()
	test_saves()
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)


static func fingerprint(gs: VGameState) -> Dictionary:
	var pop := 0
	var own := 0
	var nb := 0
	for id in range(1, gs.max_id + 1):
		var p: Dictionary = gs.provinces[id]
		pop += int(p.get("population", 0))
		own += (String(p.get("owner", "")) + ":" + str(id)).hash() & 0xffff
		nb += p["neighbors"].size()
	return {"max_id": gs.max_id, "first_sea": gs.first_sea_id, "first_lake": gs.first_lake_id, "w": gs.map_width,
		"h": gs.map_height, "states": gs.states.size(), "countries": gs.countries.size(), "cultures": gs.cultures.size(),
		"religions": gs.religions.size(), "goods": gs.goods.size(), "pop": pop, "own": own, "nb": nb}


func test_registry() -> void:
	print("-- registro de mundos y escenarios")
	var ids := []
	for w in VWorlds.list_worlds():
		ids.append(w["id"])
	check("prototype_earth" in ids and "aether" in ids and "test_fantasy" in ids, "mundos registrados: %s" % str(ids))
	check(VWorlds.world_of(VWorlds.scenario("prototype_136")) == "prototype_earth", "prototype_136 → prototype_earth")
	check(VWorlds.world_of(VWorlds.scenario("aether_era1")) == "aether", "aether_era1 → aether")
	check(VWorlds.world_of({}) == "prototype_earth", "un escenario sin «world» (anterior a M6) es del prototipo")
	var aether := VWorlds.world_meta("aether")
	check(not bool(aether.get("enabled", true)) and VWorlds.world_problem(aether) != "", "Aether registrado pero deshabilitado (%s)" % VWorlds.world_problem(aether))
	check("prototype" in aether.get("forbidden_packs", []), "Aether nunca carga el paquete prototype")
	var sc_aether := VWorlds.scenario("aether_era1")
	check(sc_aether.get("content_packs", []) == ["core", "fantasy"], "aether_era1 usa core + fantasy")
	var playable := []
	for sc in VWorlds.playable_scenarios():
		playable.append(sc["id"])
	check(playable == ["prototype_136"], "el jugador solo ve escenarios válidos: %s" % str(playable))
	var with_test := []
	for sc in VWorlds.playable_scenarios(true):
		with_test.append(sc["id"])
	check("test_fantasy_1" in with_test and not ("aether_era1" in with_test), "el mundo de prueba existe solo para pruebas: %s" % str(with_test))
	var e := VWorlds.world_meta("prototype_earth")
	for k in ["id", "name", "width", "height", "wrap_x", "description", "default_scenario", "map_version"]:
		check(e.has(k), "metadatos del mundo: %s = %s" % [k, str(e.get(k))])


func test_validator() -> void:
	print("-- validador de mundos")
	var re := VWorldValidator.validate_scenario("prototype_136")
	check(re["errors"].is_empty(), "la Tierra valida sin errores (%d avisos)" % re["warnings"].size())
	if not re["errors"].is_empty() or not re["warnings"].is_empty():
		print(VWorldValidator.describe(re, 8))
	var rt := VWorldValidator.validate_scenario("test_fantasy_1")
	check(rt["errors"].is_empty(), "el mundo de prueba importado valida sin errores (%d avisos)" % rt["warnings"].size())
	if not rt["errors"].is_empty() or not rt["warnings"].is_empty():
		print(VWorldValidator.describe(rt, 8))
	var ra := VWorldValidator.validate_scenario("aether_era1")
	check(not ra["errors"].is_empty(), "Aether sin datos no valida (%s)" % str(ra["errors"][0]) if not ra["errors"].is_empty() else "Aether sin datos no valida")
	# copia rota del mundo de prueba
	var dst := "user://_mw_broken/"
	var src: String = VWorlds.root_of("test_fantasy")
	for rel in VWorlds.WORLD_FILES:
		DirAccess.make_dir_recursive_absolute((dst + rel).get_base_dir())
		DirAccess.copy_absolute(src + rel, dst + rel)
	var provs: Array = VJson.load_array(dst + "provinces/provinces.json")
	provs[0]["culture"] = "no_existe"
	provs[1]["owner"] = "ZZZ"
	provs[2]["rgo"] = "unobtainium"
	provs[3]["id"] = provs[4]["id"]
	_write(dst + "provinces/provinces.json", provs)
	var states: Array = VJson.load_array(dst + "states/states.json")
	states[0]["provinces"].append(99999)
	_write(dst + "states/states.json", states)
	var adj := [{"a": 1, "b": 99999, "type": "sea_strait", "name": "roto"}]
	_write(dst + "map/adjacencies.json", adj)
	var rb := VWorldValidator.validate_dir(dst)
	var text := "\n".join(rb["errors"])
	check(text.contains("cultura inexistente «no_existe»"), "detecta cultura inexistente")
	check(text.contains("propietario inexistente «ZZZ»"), "detecta propietario inexistente")
	check(text.contains("RGO inexistente «unobtainium»"), "detecta RGO inexistente")
	check(text.contains("id repetido"), "detecta ids repetidos")
	check(text.contains("99999"), "detecta referencias a ids inexistentes (estado y adyacencia)")
	check(text.contains("no tiene estado") or text.contains("falta la provincia"), "detecta provincias sin estado o ausentes")


func _write(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func test_isolation() -> void:
	print("-- aislamiento entre mundos")
	var earth := VDataLoader.new_game("prototype_136")
	var fp1 := fingerprint(earth)
	check(earth.world_id == "prototype_earth" and earth.scenario_id == "prototype_136", "Tierra: world_id %s, escenario %s" % [earth.world_id, earth.scenario_id])
	check(fp1["max_id"] == 3457 and fp1["first_sea"] == 2923 and fp1["countries"] == 89 and fp1["states"] == 1060,
		"Tierra: %d provincias, %d estados, %d países (sin cambios respecto a M5.6)" % [fp1["max_id"], fp1["states"], fp1["countries"]])
	check(earth.data_errors.is_empty(), "Tierra sin errores de datos (%d)" % earth.data_errors.size())
	var test := VDataLoader.new_game("test_fantasy_1")
	var fp2 := fingerprint(test)
	check(test.world_id == "test_fantasy" and test.map_version >= 1, "mundo de prueba: world_id %s, mapa v%d" % [test.world_id, test.map_version])
	check(fp2["max_id"] != fp1["max_id"] and fp2["countries"] == 3 and fp2["w"] != fp1["w"],
		"otro mundo: %d provincias (%d terrestres), %d estados, %d países, %dx%d" % [fp2["max_id"], test.first_sea_id - 1, fp2["states"], fp2["countries"], fp2["w"], fp2["h"]])
	check(not test.countries.has("FRK") and not earth.countries.has("TFA"), "sin países del otro mundo")
	check(not test.cultures.has("hibernia") and test.cultures.has("test_culture_a"), "culturas propias del mundo")
	check(fp2["goods"] == fp1["goods"], "reglas compartidas: mismos bienes (%d)" % fp2["goods"])
	check(test.data_errors.is_empty(), "mundo de prueba sin errores de datos: %s" % str(test.data_errors.slice(0, 3)))
	check(not ("prototype" in test.content_packs), "el mundo fantástico no carga el paquete prototype (%s)" % str(test.content_packs))
	var nat := 0
	for id in test.event_defs:
		if String(id).begins_with("country."):
			nat += 1
	check(nat == 0, "sin eventos nacionales del prototipo")
	var seas := 0
	for id in range(test.first_sea_id, test.first_lake_id):
		if test.provinces[id]["neighbors"].size() > 0:
			seas += 1
	check(seas >= 4, "zonas marítimas reales (%d), no un único océano" % seas)
	var sim := VWorldSimulation.new(test)
	sim.run_days(120)
	var pop := 0
	for tag in test.countries:
		pop += int(test.countries[tag].get("population", 0))
	check(pop > 0 and test.date.year == 1, "el mundo de prueba simula 120 días (población %d)" % pop)
	var ships := 0
	for fid in test.fleets:
		ships += 1
	check(ships > 0, "flotas creadas en el mundo de prueba (%d)" % ships)
	var earth2 := VDataLoader.new_game("prototype_136")
	check(fingerprint(earth2) == fp1, "Tierra recargada idéntica tras cargar otro mundo")


func test_saves() -> void:
	print("-- guardado con identidad del mundo")
	for sid in ["prototype_136", "test_fantasy_1"]:
		var gs := VDataLoader.new_game(sid)
		gs.player_tag = gs.country_order[0]
		var path := VSaveSystem.save_game(gs, "_mw_" + sid)
		var raw: Dictionary = VJson.load_dict(path)
		check(int(raw["save_version"]) == 7 and raw["world_id"] == gs.world_id and int(raw["map_version"]) == gs.map_version,
			"%s: el save guarda world_id %s y mapa v%d" % [sid, raw["world_id"], int(raw["map_version"])])
		var err := []
		var back := VSaveSystem.load_game(path, err)
		check(back != null and back.world_id == gs.world_id and back.scenario_id == sid and back.map_version == gs.map_version and back.max_id == gs.max_id,
			"%s: carga en su mundo (%s, %s)" % [sid, back.world_id if back else "-", str(err)])
		if sid == "test_fantasy_1":
			# versión de mapa distinta → rechazo
			raw["map_version"] = int(raw["map_version"]) + 1
			_write(path, raw)
			err = []
			check(VSaveSystem.load_game(path, err) == null and not err.is_empty(), "rechaza otra versión del mapa: «%s»" % (err[0] if not err.is_empty() else ""))
			# save de un mundo con el escenario de otro → rechazo
			raw["map_version"] = gs.map_version
			raw["world_id"] = "prototype_earth"
			_write(path, raw)
			err = []
			check(VSaveSystem.load_game(path, err) == null and not err.is_empty(), "nunca aplica un save sobre la geometría de otro mundo: «%s»" % (err[0] if not err.is_empty() else ""))
		else:
			# v6 (anterior a M6) → migra al prototipo terrestre
			raw.erase("world_id")
			raw.erase("map_version")
			raw["save_version"] = 6
			_write(path, raw)
			var err6 := []
			var g6 := VSaveSystem.load_game(path, err6)
			check(g6 != null and g6.world_id == "prototype_earth", "un save v6 se migra al prototipo terrestre (%s)" % str(err6))
		DirAccess.remove_absolute(path)
