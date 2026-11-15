extends Node
## Pruebas deterministas de la capa mágica y de la cadena de integración (M4):
##   godot --headless --path . res://tests/VictoriaMagicTest.tscn

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
	gs.flags["ai_disabled"] = true
	var with_branch := "FRK"   # technology 1, military 1, politics 1 (prototipo)
	var no_branch := "HIB"     # 0,0,0,0
	print("-- antes del despertar")
	check(not gs.flags.get("GLOBAL_MAGIC_ACTIVATED", false) and not gs.flags.get("magic_unlocked", true), "la magia empieza bloqueada")
	check(not VTechnologySystem.can_research(gs, with_branch, "arcane_theory"), "la tecnología mágica no es investigable antes del despertar")
	check(not VMarketSystem.is_available(gs, "mana_crystal"), "el cristal de maná no está en el mercado")
	check(not VProductionSystem.can_build_type(gs, with_branch, "mana_refinery"), "no se pueden construir fábricas mágicas")
	check(not VDecisionSystem.list_available(gs, with_branch).has("found_arcane_academy"), "las decisiones mágicas no aparecen")
	print("-- despertar (evento global de datos)")
	gs.player_tag = with_branch
	VEventSystem.debug_fire(gs, "magic.world.awakening")
	check(gs.flags.get("GLOBAL_MAGIC_ACTIVATED", false) and gs.flags.get("magic_unlocked", false), "GLOBAL_MAGIC_ACTIVATED y magic_unlocked activados")
	var q := VEventSystem.pending(gs)
	check(not q.is_empty() and q[0]["id"] == "magic.world.awakening", "el jugador recibe la ventana del acontecimiento mundial")
	VEventSystem.choose(gs, 0, 0)
	gs.player_tag = ""
	check(VTechnologySystem.can_research(gs, with_branch, "arcane_theory"), "nación con rama de tecnología: puede investigar Teoría arcana")
	check(not VTechnologySystem.can_research(gs, no_branch, "arcane_theory"), "nación sin ramas: no puede")
	check(not VTechnologySystem.can_research(gs, with_branch, "ley_line_cartography"), "rama de economía 0 en Frankia: sin Cartografía de líneas ley")
	check(VTechnologySystem.can_research(gs, "RHE", "ley_line_cartography"), "Liga Renana (economía 1) sí puede: desarrollos distintos por nación")
	check(VMarketSystem.is_available(gs, "mana_crystal"), "los bienes mágicos entran en el mercado")
	var deposits := 0
	for id in range(1, gs.first_sea_id):
		if float(gs.provinces[id].get("magic", {}).get("deposit", 0.0)) > 0.0:
			deposits += 1
	check(deposits > 10, "aparecen yacimientos arcanos (%d provincias)" % deposits)
	var gs_b := VDataLoader.new_game()
	VMagicSystem.activate(gs_b)
	var same := true
	for id in range(1, gs.first_sea_id):
		if gs.provinces[id].get("magic", {}) != gs_b.provinces[id].get("magic", {}):
			same = false
			break
	check(same, "la siembra de yacimientos es determinista")
	print("-- economía mágica")
	# el yacimiento produce cristal que entra al mercado
	var dep_prov := -1
	var dep_tag := ""
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		if float(p.get("magic", {}).get("deposit", 0.0)) > 0.0 and p["owner"] != "" and p["controller"] == p["owner"]:
			dep_prov = id
			dep_tag = p["owner"]
			break
	var acc: Dictionary = gs.market["acc_supply"].get(dep_tag, {})
	var s0 := float(acc.get("mana_crystal", 0.0))
	VMagicSystem.country_monthly(gs, dep_tag)
	check(float(gs.market["acc_supply"].get(dep_tag, {}).get("mana_crystal", 0.0)) > s0, "el yacimiento de %s produce cristal de maná para el mercado" % gs.provinces[dep_prov]["name"])
	# fábrica mágica: con la tecnología, se puede construir y consume/produce por VProductionSystem
	VTechnologySystem.complete(gs, "RHE", "ley_line_cartography")
	VTechnologySystem.complete(gs, "RHE", "mana_refinement")
	check(VProductionSystem.can_build_type(gs, "RHE", "mana_refinery"), "con Refinado de maná se puede construir una refinería")
	var si: Dictionary = gs.country_state_instances("RHE")[0]
	si["factories"].append({"id": gs.new_id("factory"), "type": "mana_refinery", "level": 1, "open": true, "hiring": 1.0, "cash": 500.0,
		"stock": {"mana_crystal": 50.0, "sulphur": 20.0}, "loss_months": 0, "subsidized": false, "employment": 1.0, "profit": 0.0})
	var f: Dictionary = si["factories"][-1]
	VProductionSystem._normalize_factory(f, int(f["id"]))
	f["stock"] = {"mana_crystal": 2.0, "sulphur": 1.0}
	var crafts := 0
	for id in si["provinces"]:
		for s in gs.provinces[id]["pop_slots"]:
			if gs.pops.type_id[s] == gs.pops.T_CRAFTSMEN:
				crafts += gs.pops.size[s]
	if crafts < 9000:
		VPopulationSystem.make_pop(gs, "craftsmen", 12000, gs.provinces[si["provinces"][0]]["culture"], gs.provinces[si["provinces"][0]]["religion"], int(si["provinces"][0]), 0.2)
	var dem0 := float(gs.market["acc_demand"].get("RHE", {}).get("mana_crystal", 0.0))
	var sup0 := float(gs.market["acc_supply"].get("RHE", {}).get("arcane_reagents", 0.0))
	VProductionSystem.process_state_instance(gs, si)
	check(float(f["output"]) > 0.0 and float(gs.market["acc_supply"].get("RHE", {}).get("arcane_reagents", 0.0)) > sup0, "la refinería produce reactivos arcanos (%.2f)" % float(f["output"]))
	check(float(gs.market["acc_demand"].get("RHE", {}).get("mana_crystal", 0.0)) > dem0, "y demanda cristal de maná en el mercado")
	print("-- magos")
	var prov := int(gs.countries[with_branch]["capital"])
	gs.provinces[prov]["magic"] = {"potential": 1.0, "deposit": 0.0}
	gs.unit_index.erase("magic_by_country")
	var lit_ok := false
	for s in gs.provinces[prov]["pop_slots"]:
		if gs.pops.type_id[s] == gs.pops.T_CLERGY:
			gs.pops.literacy[s] = 0.6
			gs.pops.size[s] = maxi(gs.pops.size[s], 80000)
			lit_ok = true
	check(lit_ok, "hay clero en la capital")
	var magi0 := _magi(with_branch)
	VMagicSystem.country_monthly(gs, with_branch)
	var magi1 := _magi(with_branch)
	check(magi1 > magi0, "aparecen magos como POP real (%d)" % magi1)
	var ms := -1
	for s in gs.provinces[prov]["pop_slots"]:
		if gs.pops.type_name(s) == "magi":
			ms = s
	check(ms >= 0 and gs.pops.literacy[ms] > 0.0 and gs.pops.n_ideo > 0 and gs.pops.culture_names[gs.pops.culture_id[ms]] != "", "el mago tiene tamaño, alfabetización, ideología, cultura y religión")
	var no_magi0 := _magi(no_branch)
	var nprov := int(gs.countries[no_branch]["capital"])
	gs.provinces[nprov]["magic"] = {"potential": 1.0, "deposit": 0.0}
	gs.unit_index.erase("magic_by_country")
	VMagicSystem.country_monthly(gs, no_branch)
	check(_magi(no_branch) == no_magi0, "en una nación sin ramas no aparecen magos")
	var sim := VWorldSimulation.new(gs)
	sim.run_days(35)
	check(gs.pops.employment[ms] >= 0.0 and gs.pops.life[ms] > 0.0, "el mago compra necesidades y tiene empleo (vida %.2f)" % gs.pops.life[ms])
	print("-- cadena de integración")
	var tag := "PRS"   # tecnología 1, economía 1, militar 1, política 1
	var c: Dictionary = gs.countries[tag]
	c["treasury"] = 10000.0
	c["literacy"] = maxf(float(c["literacy"]), 0.3)  # requisito de la academia
	VEventSystem.debug_fire(gs, "magic.world.arcane_research", tag)
	var funded := VScopedState.has_country_flag(gs, tag, "ARCANE_RESEARCH_FUNDED")
	if not funded:
		# la IA eligió esperar: el jugador puede financiarla (misma opción, efectos reales)
		VEventSystem.apply_option(gs, gs.event_defs["magic.world.arcane_research"], 0, {"tag": tag})
	check(VScopedState.has_country_flag(gs, tag, "ARCANE_RESEARCH_FUNDED"), "evento de investigación arcana → bandera de nación")
	check(VDecisionSystem.list_available(gs, tag).has("found_arcane_academy"), "la decisión «Fundar la Academia Arcana» pasa a estar disponible")
	var cap0 := float(VMageModel.capacity(gs, tag)["target"])
	var err := VDecisionSystem.take(gs, tag, "found_arcane_academy")
	check(err == "" and "arcane_theory" in c["technologies"], "fundar la academia desbloquea Teoría arcana (%s)" % err)
	check(gs.mod(tag, "research") > 0.0 and VScopedState.has_country_modifier(gs, tag, "arcane_academy"), "modificador de la academia activo")
	var cap1 := float(VMageModel.capacity(gs, tag)["target"])
	check(VMageModel.academies(gs, tag) == 1 and cap1 > cap0, "la academia amplía la capacidad mágica sostenible (%d → %d)" % [int(cap0), int(cap1)])
	var err2 := VDecisionSystem.take(gs, tag, "fund_ley_survey")
	check(err2 == "", "estudio de líneas ley (rama de economía) (%s)" % err2)
	var mp := VMagicSystem.country_magic_provinces(gs, tag)
	var found := false
	for id in mp:
		if float(gs.provinces[id]["magic"].get("deposit", 0.0)) > 0.0:
			found = true
			VEventSystem.debug_fire(gs, "magic.world.ley_discovery", tag, int(id))
			break
	check(found, "descubrimiento de yacimiento en una provincia de Parsa")
	var s1 := float(gs.market["acc_supply"].get(tag, {}).get("mana_crystal", 0.0))
	VMagicSystem.country_monthly(gs, tag)
	check(float(gs.market["acc_supply"].get(tag, {}).get("mana_crystal", 0.0)) > s1, "el bien mágico entra en el mercado desde Parsa")
	VTechnologySystem.complete(gs, tag, "ley_line_cartography")
	VTechnologySystem.complete(gs, tag, "mana_refinement")
	check(VProductionSystem.can_build_type(gs, tag, "mana_refinery"), "la refinería de maná es posible")
	check(VDecisionSystem.list_available(gs, tag).has("regulate_magical_practice") or VScopedState.has_country_flag(gs, tag, "MAGIC_POLICY_SET"), "la política de la magia entra en juego (decisión de regulación)")
	print("-- guardado")
	var path := VSaveSystem.save_game(gs, "_magic_test")
	var e2 := []
	var g2 := VSaveSystem.load_game(path, e2)
	check(g2 != null, "carga (%s)" % (e2[0] if not e2.is_empty() else "ok"))
	if g2:
		check(g2.flags.get("GLOBAL_MAGIC_ACTIVATED", false) and g2.flags.get("magic_unlocked", false), "banderas mágicas conservadas")
		check(float(g2.provinces[prov].get("magic", {}).get("potential", 0.0)) == 1.0, "datos mágicos de provincia conservados")
		check(_magi_in(g2, with_branch) > 0 and _magi_in(g2, with_branch) == _magi(with_branch), "los magos sobreviven al guardado (%d)" % _magi_in(g2, with_branch))
		check(VScopedState.has_country_flag(g2, tag, "ARCANE_ACADEMY_FOUNDED") and g2.mod(tag, "mage_capacity") > 0.0 and VMageModel.academies(g2, tag) == 1, "banderas, academias y modificadores mágicos conservados")
		check(VTechnologySystem.can_research(g2, "RHE", "arcane_engineering") or "arcane_engineering" in g2.countries["RHE"]["technologies"] or not VTechnologySystem.can_research(g2, no_branch, "arcane_theory"), "el acceso por ramas se mantiene tras cargar")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _magi(tag: String) -> int:
	return _magi_in(gs, tag)


func _magi_in(g: VGameState, tag: String) -> int:
	var n := 0
	for id in g.countries[tag]["provinces"]:
		for s in g.provinces[id]["pop_slots"]:
			if g.pops.type_name(s) == "magi":
				n += g.pops.size[s]
	return n
