extends Node
## Contenido y marco de lore (M5): paquetes, espacios de nombres, manifiesto de arte, cadenas con ramas,
## banderas que cambian eventos posteriores, efectos económicos, eventos que reaccionan a la guerra y a la
## magia reales, crónica con categorías, biblia de lore, escenarios e historia, sendas mágicas y diagnóstico.
##   godot --headless --path . res://tests/VictoriaContentTest.tscn

var failures := 0
var gs: VGameState


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	await get_tree().process_frame
	gs = VDataLoader.new_game()
	gs.player_tag = ""
	test_framework()
	test_chains()
	test_war_reactivity()
	test_magic_reactivity()
	test_chronicle()
	test_lore_and_history()
	test_diagnostics()
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _sched(id: String) -> bool:
	for s in VScopedState.es(gs)["scheduled"]:
		if s["id"] == id:
			return true
	return false


func test_framework() -> void:
	print("-- paquetes, espacios de nombres y arte")
	check(gs.content_packs == ["core", "prototype"] and gs.scenario_id == "prototype_136", "escenario y paquetes por defecto (%s, %s)" % [gs.scenario_id, str(gs.content_packs)])
	check(gs.data_errors.is_empty(), "contenido sin errores de datos (%d)" % gs.data_errors.size())
	var bad := []
	var ns_ok := true
	for id in gs.event_defs:
		var root: String = String(id).get_slice(".", 0)
		if not (root in ["core", "magic", "country", "region"]):
			ns_ok = false
			bad.append(id)
		var art: String = gs.event_defs[id]["art"]
		if art != "" and not gs.art_manifest.has(art):
			bad.append(id + ":" + art)
	check(ns_ok, "todos los eventos usan espacio de nombres (core / magic / country / region)")
	check(bad.is_empty(), "todas las ilustraciones están en el manifiesto de arte (%s)" % str(bad))
	check(gs.art_manifest.size() >= 15 and gs.art_manifest.size() <= 25, "categorías visuales: %d" % gs.art_manifest.size())
	check(gs.event_defs.size() >= 100 and gs.event_defs.size() <= 150, "eventos totales en el rango de calidad (%d)" % gs.event_defs.size())
	var prot := 0
	for id in gs.event_defs:
		if String(id).begins_with("country."):
			prot += 1
	check(prot > 0, "el contenido terrestre está en el paquete prototype (%d eventos country.*)" % prot)


func test_chains() -> void:
	print("-- cadenas, ramas y reactividad")
	var tag := "FRK"
	var boom: Dictionary = gs.event_defs["core.economy.speculative_boom"]
	var crash: Dictionary = gs.event_defs["core.economy.market_crash"]
	check(not VEventConditions.check(gs, crash["trigger"], {"tag": tag}), "el crac no puede ocurrir sin la burbuja descontrolada")
	VEventSystem.apply_option(gs, boom, 0, {"tag": tag})
	check(VScopedState.has_country_flag(gs, tag, "BOOM_UNCHECKED") and _sched("core.economy.market_crash"), "rama A: bandera BOOM_UNCHECKED y crac programado")
	check(VEventConditions.check(gs, crash["trigger"], {"tag": tag}), "la bandera habilita el crac posterior")
	var tag2 := "BRI"
	VEventSystem.apply_option(gs, boom, 1, {"tag": tag2})
	check(VScopedState.has_country_flag(gs, tag2, "BOOM_REGULATED") and _sched("core.economy.soft_landing"), "rama B: regulación y aterrizaje suave programado")
	check(not VEventConditions.check(gs, crash["trigger"], {"tag": tag2}), "la rama regulada no lleva al crac")
	# las opciones posteriores dependen de la vía elegida antes
	var nic: Dictionary = gs.event_defs["core.economy.new_industrial_class"]
	VScopedState.set_country_flag(gs, tag, "STATE_INDUSTRY")
	check(VEventSystem.option_available(gs, nic, 1, {"tag": tag}) and not VEventSystem.option_available(gs, nic, 0, {"tag": tag}), "la industria estatal abre una opción y cierra la otra")
	# un evento económico cambia la economía
	var td: Dictionary = gs.event_defs["core.economy.trade_dependency"]
	var t0 := float(gs.countries[tag]["budget"]["tariffs"])
	VEventSystem.apply_option(gs, td, 0, {"tag": tag})
	check(float(gs.countries[tag]["budget"]["tariffs"]) > t0 and VScopedState.has_country_flag(gs, tag, "PROTECTIONIST_TURN"), "los aranceles suben (%.2f → %.2f)" % [t0, float(gs.countries[tag]["budget"]["tariffs"])])
	var tr0 := float(gs.countries[tag]["treasury"])
	VEventSystem.apply_option(gs, crash, 0, {"tag": tag})
	check(float(gs.countries[tag]["treasury"]) < tr0 and gs.mod(tag, "bank_capacity") < 0.0, "rescatar a los bancos cuesta tesoro y deja pánico bancario")
	# cadenas: número de eventos con follow-up
	var chains := 0
	for id in gs.event_defs:
		for o in gs.event_defs[id]["options"]:
			if not o["follow_up"].is_empty():
				chains += 1
				break
	check(chains >= 25, "eventos que abren o continúan cadenas: %d" % chains)


func test_war_reactivity() -> void:
	print("-- guerra real")
	var tag := "FRK"
	var gv: Dictionary = gs.event_defs["core.war.great_victory"]
	check(not VEventConditions.check(gs, gv["trigger"], {"tag": tag, "losses": 30000}), "sin guerra no hay gran victoria")
	var enemy := ""
	for n in VDiplomacySystem.neighbor_countries(gs, tag):
		if not gs.countries[n]["provinces"].is_empty() and not (n in gs.countries[tag]["allies"]):
			enemy = n
			break
	VEventEffects.apply(gs, {"start_war": {"cb": "humiliate"}}, {"tag": tag, "target": enemy})
	check(not gs.countries[tag]["wars"].is_empty(), "guerra declarada contra %s" % enemy)
	check(VEventConditions.check(gs, gv["trigger"], {"tag": tag, "losses": 30000}), "con guerra y muchas bajas enemigas, la gran victoria es posible")
	check(not VEventConditions.check(gs, gv["trigger"], {"tag": tag, "losses": 500}), "una escaramuza no es una gran victoria")
	var hp: Dictionary = gs.event_defs["core.war.humiliating_peace"]
	check(VEventConditions.check(gs, hp["trigger"], {"tag": tag, "result": "defeat", "goals": 1}) and not VEventConditions.check(gs, hp["trigger"], {"tag": tag, "result": "victory", "goals": 1}), "la paz humillante responde al resultado real de la paz")
	var cf: Dictionary = gs.event_defs["core.war.capital_fallen"]
	var cap := int(gs.countries[tag]["capital"])
	check(VEventConditions.check(gs, cf["trigger"], {"tag": tag, "prov": cap}) and not VEventConditions.check(gs, cf["trigger"], {"tag": tag, "prov": int(gs.countries[tag]["provinces"][-1]) if int(gs.countries[tag]["provinces"][-1]) != cap else -1}), "la caída de la capital solo se dispara en la capital")
	var war_entries := VChronicle.entries_for(gs, tag, "war")
	check(not war_entries.is_empty() and VChronicle.line(war_entries[0]).begins_with("Año "), "la crónica cuenta la guerra («%s»)" % (VChronicle.line(war_entries[0]) if not war_entries.is_empty() else ""))
	VEventSystem.apply_option(gs, hp, 0, {"tag": tag, "target": enemy})
	check(VScopedState.has_country_flag(gs, tag, "REVANCHISM") and gs.mod(tag, "military_strength") > 0.0, "jurar revancha deja revanchismo")
	var rl: Dictionary = gs.event_defs["core.war.revanchist_league"]
	check(not VEventConditions.check(gs, rl["trigger"], {"tag": tag}), "la liga de la revancha espera a que termine la guerra")


func test_magic_reactivity() -> void:
	print("-- magia real")
	var tag := "BAY"
	var um: Dictionary = gs.event_defs["magic.social.unemployed_magi"]
	check(not VEventSystem._prefilter(gs, um, {"tag": tag}), "sin despertar no hay eventos de sociedad mágica")
	VMagicSystem.activate(gs)
	var c: Dictionary = gs.countries[tag]
	if not c.has("type_sizes"):
		c["type_sizes"] = {}
	c["type_sizes"]["magi"] = 5000
	c["_magi_info"] = {"unemployment": 0.1, "share": 0.001, "magi": 5000.0, "target": 6000.0, "ratio": 0.83}
	check(not VEventConditions.check(gs, um["trigger"], {"tag": tag}), "con pleno empleo no hay crisis de magos")
	c["_magi_info"]["unemployment"] = 0.5
	check(VEventSystem._prefilter(gs, um, {"tag": tag}) and VEventConditions.check(gs, um["trigger"], {"tag": tag}), "con magos en paro la crisis es posible")
	VEventSystem.apply_option(gs, um, 0, {"tag": tag})
	check(gs.mod(tag, "mage_state_posts") > 0.0, "la respuesta crea plazas públicas para magos")
	var wh: Dictionary = gs.event_defs["magic.social.witch_hunt"]
	VScopedState.set_country_flag(gs, tag, "WITCH_HUNTS")
	VEventSystem.apply_option(gs, wh, 1, {"tag": tag})
	check(VMagicPolicy.level_id(gs, tag) == "magic_prohibited", "la caza de brujos puede acabar en prohibición (decreto)")
	check(_sched("magic.social.persecution_aftermath"), "y deja una secuela programada")
	var magic_entries := VChronicle.entries_for(gs, tag, "magic")
	check(not magic_entries.is_empty(), "la crónica recoge la persecución (%s)" % (VChronicle.line(magic_entries[0]) if not magic_entries.is_empty() else ""))
	var cc: Dictionary = gs.event_defs["magic.social.church_condemns_magic"]
	c["type_sizes"]["magi"] = 3000
	var rel_ok := VEventConditions.check(gs, cc["trigger"], {"tag": tag})
	var att := VMageModel.religion_attitude(gs, String(c["religion"]))
	check(rel_ok == (att in ["regulated", "suspicious", "heretical"]), "la condena del clero depende de la actitud mágica de la religión (%s)" % att)
	# sendas mágicas: nivel ≠ escuela
	gs.countries["FRK"]["magic_branches"]["military"] = {"level": 2, "paths": ["battlemage"]}
	var node := VEventConditions.compile(gs, {"magic_path": {"military": "battlemage"}, "magic_branch": {"military": 2}}, [], "t")
	check(VMagicSystem.branch_level(gs, "FRK", "military") == 2 and VEventConditions.check(gs, node, {"tag": "FRK"}), "rama con nivel y sendas ({level, paths})")


func test_chronicle() -> void:
	print("-- crónica")
	VChronicle.on_action(gs, "rebellion_won", {"tag": "FRK"})
	var pol := VChronicle.entries_for(gs, "FRK", "politics")
	check(not pol.is_empty() and String(pol[0].get("text", "")).contains("rebeldes"), "historia emergente desde on_action (%s)" % (VChronicle.line(pol[0]) if not pol.is_empty() else ""))
	var all := VChronicle.entries_for(gs, "FRK", "", 200)
	var cats := {}
	for e in all:
		cats[e.get("cat", "")] = true
	check(cats.size() >= 3, "la crónica de Frankia tiene varias categorías (%s)" % str(cats.keys()))
	var world := VChronicle.entries_for(gs, "BRI", "magic")
	var awakening := false
	for e in world:
		if String(e.get("text", "")).contains("magia regresó"):
			awakening = true
	check(awakening, "el despertar aparece en la crónica de cualquier nación")


func test_lore_and_history() -> void:
	print("-- biblia de lore, escenarios e historia")
	var root := "user://_lorepack/"
	DirAccess.make_dir_recursive_absolute(root + "content/lp/lore")
	var f := FileAccess.open(root + "content/lp/lore/religions.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"lore_type": "religion", "entries": [
		{"id": "fe_a", "name": "Fe A", "magic_attitude": "sacred"},
		{"id": "fe_b", "name": "Fe B"},
		{"id": "fe_c", "name": "Fe C", "magic_attitude": "maybe"}]}))
	f.close()
	var g2 := VGameState.new()
	g2.content_packs = ["lp"]
	VLoreLoader.load_all(g2, root)
	var j := " | ".join(g2.data_errors)
	check(g2.lore.get("religion", {}).has("fe_a"), "la biblia de lore se carga (religión «fe_a»)")
	check(j.contains("magic_attitude") and j.contains("fe_b"), "detecta campos obligatorios ausentes y actitudes no válidas")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "content/lp/lore/religions.json"))
	var g3 := VDataLoader.new_game("no_such_scenario")
	check(" ".join(g3.data_errors).contains("escenario desconocido"), "un escenario desconocido es un error de datos")
	VDataLoader._apply_late_history(gs, {"flags": ["HIST_FLAG"], "rivals": [["FRK", "BRI"]], "countries": {"FRK": {"flags": ["HIST_C"], "variables": {"legacy": 3}, "modifiers": [{"id": "urban_growth", "months": 0}]}}})
	check(gs.flags.get("HIST_FLAG", false) and VScopedState.has_country_flag(gs, "FRK", "HIST_C") and is_equal_approx(VScopedState.get_variable(gs, "FRK", "legacy"), 3.0), "la historia declara banderas y variables")
	check("BRI" in gs.countries["FRK"].get("rivals", []) and gs.relation("FRK", "BRI") <= -100, "la historia declara rivalidades")
	var node := VEventConditions.compile(gs, {"is_rival": true}, [], "t")
	check(VEventConditions.check(gs, node, {"tag": "FRK", "target": "BRI"}), "condición is_rival")


func test_diagnostics() -> void:
	print("-- diagnóstico de militancia y conciencia")
	var sim := VWorldSimulation.new(gs)
	sim.run_days(130)
	var md: Dictionary = gs.market.get("mil_diag", {})
	var cd: Dictionary = gs.market.get("con_diag", {})
	check(md.has("events") and md.has("magic") and md.has("temporary_modifiers") and md.has("war_exhaustion") and md.has("unemployment"), "militancia separada por componentes (%d)" % md.size())
	check(cd.has("literacy") and cd.has("events") and cd.has("temporary_modifiers"), "conciencia separada por componentes (%d)" % cd.size())
	var cum := VPopulationSystem.cumulative_diagnosis(gs, "mil")
	check(not cum.is_empty() and int(gs.market["diag_cum"]["n"]) >= 1, "promedios acumulados disponibles (%d muestras)" % int(gs.market.get("diag_cum", {}).get("n", 0)))
	var st: Dictionary = VScopedState.es(gs)["stats"]
	check(st.has("ai_visible") and st.has("type_normal"), "métricas de eventos diferenciadas (%s)" % str(st.keys().slice(0, 8)))
