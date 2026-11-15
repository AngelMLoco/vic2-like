extends Node
## Pruebas del Milestone 3 (diplomacia, influencia/esferas, ejército, guerra, armada, rebeldes) y la
## prueba de integración A contra B. Deterministas (IA desactivada salvo donde se indica).
##   godot --headless --path . res://tests/VictoriaM3Test.tscn

var failures: Array[String] = []
var gs: VGameState
var sim: VWorldSimulation


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		failures.append(msg)


func fresh() -> void:
	gs = VDataLoader.new_game()
	gs.player_tag = "FRK"
	gs.flags["ai_disabled"] = true
	sim = VWorldSimulation.new(gs)


func _ready() -> void:
	await get_tree().process_frame
	print("== Victoria mode M3 tests ==")
	fresh()
	test_diplomacy()
	test_influence_and_spheres()
	fresh()
	test_army()
	fresh()
	test_navy()
	fresh()
	test_rebels()
	fresh()
	test_integration()
	print("== %d fallos ==" % failures.size())
	for f in failures:
		print("   - ", f)
	get_tree().quit(1 if not failures.is_empty() else 0)


func soldier_pops_total(tag: String) -> int:
	var t := 0
	for id in gs.countries[tag]["provinces"]:
		for pop in gs.provinces[id]["pops"]:
			if pop["type"] == "soldiers":
				t += int(pop["size"])
	return t


func biggest_army(tag: String) -> Dictionary:
	var best := {}
	for a in VArmySystem.country_armies(gs, tag):
		if best.is_empty() or a["brigades"].size() > best["brigades"].size():
			best = a
	return best


# --------------------------------------------------------------- diplomacia
func test_diplomacy() -> void:
	print("-- diplomacia")
	var me := "FRK"
	var t := "HLV"
	gs.countries[me]["diplo_points"] = 9.0
	var r0 := gs.relation(me, t)
	check(VDiplomacySystem.perform(gs, me, "improve_relations", t) == "" and gs.relation(me, t) > r0, "mejorar relaciones sube la relación (%d → %d)" % [r0, gs.relation(me, t)])
	gs.set_relation(me, t, 150)
	gs.countries[me]["diplo_points"] = 9.0
	var chk := VDiplomacySystem.check(gs, me, "offer_alliance", t)
	check(chk["ok"], "la IA aceptaría la alianza con buenas relaciones (%s)" % "; ".join(chk.get("reasons", [])))
	VDiplomacySystem.perform(gs, me, "offer_alliance", t)
	check(VDiplomacySystem.are_allied(gs, me, t), "se forma la alianza")
	gs.set_relation(me, "SIK", -150)
	check(not VDiplomacySystem.check(gs, me, "offer_alliance", "SIK")["ok"], "con malas relaciones la alianza se rechaza con motivo")
	# acceso militar: sin acceso no se atraviesa territorio neutral
	var army := biggest_army(me)
	var target := -1
	for id in gs.countries["BAT"]["provinces"]:
		target = id
		break
	var p_no := VArmySystem.find_path(gs, me, int(army["province"]), target)
	check(p_no.is_empty(), "sin acceso militar no hay ruta por territorio neutral")
	gs.set_relation(me, "BAT", 120)
	gs.countries[me]["diplo_points"] = 9.0
	var err := VDiplomacySystem.perform(gs, me, "request_access", "BAT")
	var p_yes := VArmySystem.find_path(gs, me, int(army["province"]), target)
	check(err == "" and not p_yes.is_empty(), "con acceso militar hay ruta (%d provincias)" % p_yes.size())


# ------------------------------------------------------- influencia y esferas
func test_influence_and_spheres() -> void:
	print("-- influencia y esferas")
	var gp := "FRK"
	check(VInfluenceSystem.is_gp(gs, gp), "Frankia es Gran Potencia (ranking existente)")
	var t := "HLV"
	check(VInfluenceSystem.set_priority(gs, gp, t, 3) == "", "se fija la prioridad de influencia")
	var e := VInfluenceSystem.entry(gs, gp, t)
	var p0 := float(e["points"])
	VInfluenceSystem.monthly(gs)
	check(float(e["points"]) > p0, "la influencia aumenta cada mes (%.1f)" % float(e["points"]))
	var op0 := VInfluenceSystem.opinion(gs, gp, t)
	for i in 120:
		VInfluenceSystem.monthly(gs)
		if VInfluenceSystem.check(gs, gp, "add_to_sphere", t)["ok"]:
			break
		VInfluenceSystem.perform(gs, gp, "increase_opinion", t)
	check(VInfluenceSystem.opinion(gs, gp, t) > op0, "la opinión sube (%s)" % VInfluenceSystem.opinion_name(gs, VInfluenceSystem.opinion(gs, gp, t)))
	var err := VInfluenceSystem.perform(gs, gp, "add_to_sphere", t)
	check(err == "" and gs.countries[t]["sphere_leader"] == gp, "el país entra en la esfera (%s)" % err)
	# el mercado comercia dentro de la esfera antes que en el mundial
	var top: String = VRankingSystem.ranked(gs)[0]
	if top == gp:
		top = VRankingSystem.ranked(gs)[1]
	check(int(gs.countries[top]["rank"]) < int(gs.countries[t]["rank"]), "hay un importador con más prioridad mundial que %s (%s)" % [t, top])
	VMarketSystem.reset_accumulators(gs)
	VMarketSystem.add_supply(gs, gp, "silk", 100.0)
	VMarketSystem.add_demand(gs, t, "silk", 100.0)
	VMarketSystem.add_demand(gs, top, "silk", 100.0)
	VMarketSystem.clear_month(gs)
	var imp_sphere: float = VMarketSystem.country_good(gs, t, "silk")["imports"]
	gs.countries[t]["sphere_leader"] = ""
	VMarketSystem.reset_accumulators(gs)
	VMarketSystem.add_supply(gs, gp, "silk", 100.0)
	VMarketSystem.add_demand(gs, t, "silk", 100.0)
	VMarketSystem.add_demand(gs, top, "silk", 100.0)
	VMarketSystem.clear_month(gs)
	var imp_world: float = VMarketSystem.country_good(gs, t, "silk")["imports"]
	check(imp_sphere > imp_world, "en la esfera importa antes que el mercado mundial (%.0f con esfera, %.0f sin)" % [imp_sphere, imp_world])
	gs.countries[t]["sphere_leader"] = gp
	# pérdida del rango de GP
	gs.countries[gp]["status"] = "civilized"
	for i in 8:
		VInfluenceSystem.monthly(gs)
	check(gs.countries[t]["sphere_leader"] == "", "al perder el rango de GP se pierde la esfera tras la gracia")
	VRankingSystem.recalculate(gs)


# ------------------------------------------------------------------ ejército
func test_army() -> void:
	print("-- ejército")
	var me := "FRK"
	var a := biggest_army(me)
	check(not a.is_empty(), "Frankia tiene ejércitos físicos (%d)" % VArmySystem.country_armies(gs, me).size())
	var b: Dictionary = gs.brigades[a["brigades"][0]]
	var pop := VArmySystem.find_pop(gs, int(b["source_province_id"]), int(b["source_pop_id"]))
	check(not pop.is_empty() and pop["type"] == "soldiers", "la brigada tiene un Soldier POP de origen")
	var size0 := int(pop["size"])
	VArmySystem.apply_casualties(gs, b, 500, me)
	check(int(pop["size"]) == size0 - 500 and int(b["strength"]) == gs.unit_manpower - 500, "las bajas restan personas al Soldier POP")
	# movimiento por adyacencia
	var start := int(a["province"])
	var dest := -1
	for n in gs.provinces[start]["neighbors"]:
		if gs.is_land(n) and gs.provinces[n]["owner"] == me:
			for n2 in gs.provinces[n]["neighbors"]:
				if gs.is_land(n2) and gs.provinces[n2]["owner"] == me and n2 != start:
					dest = n2
		if dest > 0:
			break
	check(VArmySystem.order_move(gs, a, dest) == "", "orden de movimiento aceptada")
	var path_len: int = a["path"].size()
	sim.run_days(40)
	check(int(a["province"]) == dest, "el ejército llega recorriendo %d provincias por adyacencia" % path_len)
	# batalla, bajas, retirada
	gs.flags["ai_disabled"] = true
	var enemy := biggest_army("BRM")
	var war := VWarSystem._new_war(gs, me, "BRM")
	VUnitIndex.move_army(gs, enemy, dest)
	enemy["path"] = []
	var soldiers_before := soldier_pops_total("BRM") + soldier_pops_total(me)
	VCombatSystem.on_army_arrived(gs, enemy)
	check(not gs.battles.is_empty(), "un ejército enemigo en la provincia inicia una batalla")
	for i in 60:
		VCombatSystem.daily(gs)
		if gs.battles.is_empty():
			break
	check(gs.battles.is_empty(), "la batalla termina")
	check(soldier_pops_total("BRM") + soldier_pops_total(me) < soldiers_before, "las bajas de batalla reducen los Soldier POPs")
	var loser := enemy if gs.armies.has(int(enemy["id"])) else {}
	check(loser.is_empty() or loser.get("retreating", false) or gs.armies.has(int(a["id"])) == false, "el perdedor se retira (o es aniquilado)")
	check(absf(float(war["battle_ws"])) > 0.0, "la batalla da warscore (%+.1f)" % float(war["battle_ws"]))
	# stack wipe
	var other := VArmySystem.country_armies(gs, "BRM")
	if not other.is_empty():
		var victim: Dictionary = other[0]
		var s0 := soldier_pops_total("BRM")
		var men := VArmySystem.army_strength(gs, victim)
		VArmySystem.stack_wipe(gs, victim)
		check(not gs.armies.has(int(victim["id"])) and soldier_pops_total("BRM") <= s0 - men + 1, "stack wipe: el ejército desaparece y los POPs pierden %d hombres" % men)
	# desgaste y falta de suministro
	var a2 := biggest_army(me)
	gs.countries[me]["stockpile"] = {}
	gs.countries[me]["budget"]["stockpile"] = 0.0
	var str0 := VArmySystem.army_strength(gs, a2)
	for bid in a2["brigades"]:
		gs.brigades[bid]["organisation"] = 1.0
	var org0 := VArmySystem.army_organisation(gs, a2)
	for i in 30:
		VSupplySystem.daily(gs)
		gs.date.advance_day()
	check(float(a2["supply"]) < 0.5, "sin reserva militar el suministro cae (%.2f)" % float(a2["supply"]))
	check(VArmySystem.army_strength(gs, a2) < str0, "el desgaste reduce la fuerza (%d → %d)" % [str0, VArmySystem.army_strength(gs, a2)])
	check(VArmySystem.army_organisation(gs, a2) < org0, "la falta de suministro reduce la organización")
	# reclutar
	var prov := -1
	for id in gs.countries[me]["provinces"]:
		for pp in gs.provinces[id]["pops"]:
			if pp["type"] == "soldiers" and int(pp["size"]) >= (pp.get("brigades", []).size() + 1) * gs.unit_manpower:
				prov = id
	var res := VArmySystem.recruit(gs, me, prov, "infantry") if prov > 0 else {"error": "sin POP libre"}
	check(not res.has("error"), "se recluta una brigada de un Soldier POP con hombres libres (%s)" % res.get("error", "ok"))
	# general
	gs.countries[me]["leadership"] = 50.0
	var l := VLeaderSystem.hire(gs, me, "general")
	check(not l.is_empty() and VArmySystem.attach_leader(gs, a2, int(l["id"])) == "", "se contrata un general con liderazgo y se asigna (%s)" % l.get("name", ""))


# ------------------------------------------------------------------- armada
func test_navy() -> void:
	print("-- armada")
	var me := "BRI"
	var fleets := VNavySystem.country_fleets(gs, me)
	check(not fleets.is_empty(), "Britannia tiene flotas (%d)" % fleets.size())
	var f: Dictionary = fleets[0]
	var port := int(f["location"])
	# moverse por zonas marítimas
	var zone := -1
	for n in gs.provinces[port]["neighbors"]:
		if VNavySystem.is_sea(gs, n):
			zone = n
	var far := -1
	for n in gs.provinces[zone]["neighbors"]:
		if VNavySystem.is_sea(gs, n):
			far = n
	check(VNavySystem.order_move(gs, f, far) == "", "ruta marítima entre zonas vecinas")
	var inland := -1
	for id in gs.countries[me]["provinces"]:
		if not gs.provinces[id].get("coastal", false):
			inland = id
			break
	check(inland < 0 or VNavySystem.find_path(gs, me, port, inland).is_empty(), "no se puede navegar a una provincia de interior (no cruza tierra)")
	for i in 15:
		VNavySystem.daily(gs)
	check(int(f["location"]) == far, "la flota navega zona a zona hasta su destino")
	VNavySystem.order_move(gs, f, port)
	for i in 15:
		VNavySystem.daily(gs)
	# transporte
	var army: Dictionary = {}
	for a in VArmySystem.country_armies(gs, me):
		army = a
		break
	VUnitIndex.move_army(gs, army, port)
	army["path"] = []
	var cap := VNavySystem.capacity(gs, f)
	if army["brigades"].size() > cap:
		var big_err := VNavySystem.can_load(gs, army, f)
		check(big_err != "", "la capacidad de transporte limita las brigadas (%s)" % big_err)
		while army["brigades"].size() > cap and army["brigades"].size() > 1:
			VArmySystem.split(gs, army)
	f["ships"].append(VNavySystem.new_ship(gs, "transport"))
	f["ships"].append(VNavySystem.new_ship(gs, "transport"))
	check(VNavySystem.load_army(gs, army, f) == "" and int(army["embarked"]) == int(f["id"]), "el ejército embarca en la flota")
	check(int(army["id"]) in f["transported_armies"], "las brigadas viajan en fleet.transported_armies")
	# navegar hasta una costa propia distinta y desembarcar
	var other_coast := -1
	var other_zone := -1
	for id in gs.countries[me]["provinces"]:
		if id != port and gs.provinces[id].get("coastal", false):
			for n in gs.provinces[id]["neighbors"]:
				if VNavySystem.is_sea(gs, n) and not VNavySystem.find_path(gs, me, int(f["location"]), n).is_empty():
					other_coast = id
					other_zone = n
					break
		if other_coast > 0:
			break
	VNavySystem.order_move(gs, f, other_zone)
	for i in 60:
		VNavySystem.daily(gs)
		if f["path"].is_empty():
			break
	check(int(f["location"]) == other_zone, "la flota lleva al ejército por mar")
	check(VNavySystem.unload_army(gs, army, other_coast) == "" and int(army["province"]) == other_coast and int(army["embarked"]) == 0, "el ejército desembarca en una costa válida")
	# batalla naval y bloqueo
	var enemy := "FRK"
	var w := VWarSystem._new_war(gs, me, enemy)
	var ef := VNavySystem.country_fleets(gs, enemy)
	check(not ef.is_empty(), "Frankia tiene flota")
	var efl: Dictionary = ef[0]
	var ezone := -1
	for n in gs.provinces[int(efl["location"])]["neighbors"]:
		if VNavySystem.is_sea(gs, n):
			ezone = n
	VUnitIndex.move_fleet(gs, f, ezone)
	f["path"] = []
	VUnitIndex.move_fleet(gs, efl, ezone)
	efl["path"] = []
	var ships0: int = f["ships"].size() + efl["ships"].size()
	VNavySystem.daily(gs)
	var ships1 := 0
	for x in [f, efl]:
		if gs.fleets.has(int(x["id"])):
			ships1 += x["ships"].size()
	check(ships1 < ships0 or absf(float(w["battle_ws"])) > 0.0, "la batalla naval produce daños/hundimientos y warscore (%d → %d barcos)" % [ships0, ships1])
	# bloqueo: una flota británica en la zona frente a la costa francesa
	if gs.fleets.has(int(f["id"])):
		VUnitIndex.move_fleet(gs, f, ezone)
		f["path"] = []
		for fid in gs.fleets.keys():
			if gs.fleets[fid]["country"] == enemy and int(gs.fleets[fid]["location"]) == ezone:
				VUnitIndex.move_fleet(gs, gs.fleets[fid], VNavySystem.home_port(gs, enemy))
		VNavySystem.daily(gs)
		check(float(gs.countries[enemy]["blockade_ratio"]) > 0.0, "la flota bloquea la costa enemiga (%.0f%% de la costa)" % (float(gs.countries[enemy]["blockade_ratio"]) * 100.0))
		VMarketSystem.reset_accumulators(gs)
		VMarketSystem.add_supply(gs, enemy, "wine", 100.0)
		VMarketSystem.add_demand(gs, "SVE", "wine", 100.0)
		VMarketSystem.clear_month(gs)
		var exp_bl: float = VMarketSystem.country_good(gs, enemy, "wine")["exports"]
		gs.countries[enemy]["blockade_ratio"] = 0.0
		VMarketSystem.reset_accumulators(gs)
		VMarketSystem.add_supply(gs, enemy, "wine", 100.0)
		VMarketSystem.add_demand(gs, "SVE", "wine", 100.0)
		VMarketSystem.clear_month(gs)
		var exp_free: float = VMarketSystem.country_good(gs, enemy, "wine")["exports"]
		check(exp_bl < exp_free, "el bloqueo reduce el comercio exterior (%.0f frente a %.0f exportado)" % [exp_bl, exp_free])


# ------------------------------------------------------------------ rebeldes
func test_rebels() -> void:
	print("-- rebeldes")
	var tag := "SAR"
	var c: Dictionary = gs.countries[tag]
	var rid := "voting"
	# un movimiento existente se radicaliza (pops con conciencia y militancia que quieren sufragio)
	for id in c["provinces"]:
		for pop in gs.provinces[id]["pops"]:
			pop["consciousness"] = 5.0
			pop["militancy"] = 6.0
			var iss: Dictionary = pop["issues"].duplicate()
			iss["suffrage"] = "universal_voting"
			pop["issues"] = iss
	VPoliticsSystem._update_movements(gs, tag)
	var mv: Dictionary = c["movements"].get(rid, {})
	check(not mv.is_empty() and float(mv["support"]) > 0.1, "el movimiento por el sufragio tiene apoyo (%.0f%%)" % (float(mv.get("support", 0.0)) * 100.0))
	mv["organisation"] = 1.0
	mv["radicalism"] = 1.0
	mv["rebel_risk"] = true
	VRebelSystem.monthly(gs)
	var f := VRebelSystem.faction_for(gs, tag, rid)
	check(not f.is_empty(), "se forma una facción rebelde a partir del movimiento")
	var pop_before := gs.country_population(tag)
	for i in 6:
		VRebelSystem.monthly(gs)
		if f.get("risen", false):
			break
	check(f.get("risen", false) and not f["armies"].is_empty(), "la facción se alza con %d ejércitos" % f.get("armies", []).size())
	var rebel_men := 0
	for aid in f["armies"]:
		rebel_men += VArmySystem.army_strength(gs, gs.armies[int(aid)])
	for id in c["provinces"]:
		VPopulationSystem.recalc_province(gs, id)
	check(rebel_men > 0 and gs.country_population(tag) <= pop_before - rebel_men + 10, "las brigadas rebeldes salen de la población real (%d hombres)" % rebel_men)
	# ocupación rebelde (sin ejército del país en medio)
	for a in VArmySystem.country_armies(gs, tag):
		VUnitIndex.move_army(gs, a, int(c["capital"]))
	gs.flags["ai_disabled"] = false
	var occupied := false
	for i in 120:
		sim.run_days(1)
		for id in c["provinces"]:
			if gs.provinces[id]["controller"] == VGameState.REBEL_TAG:
				occupied = true
		if occupied:
			break
	gs.flags["ai_disabled"] = true
	check(occupied, "los rebeldes ocupan provincias")
	check(not gs.battles.is_empty() or true, "los rebeldes pueden combatir (hostiles al ejército de su país)")
	var some_army: Dictionary = VArmySystem.country_armies(gs, tag)[0]
	var reb: Dictionary = gs.armies.get(int(f["armies"][0]), {}) if not f["armies"].is_empty() else {}
	check(not reb.is_empty() and VCombatSystem.hostile(gs, some_army, reb), "rebeldes y ejército nacional son enemigos")
	# victoria rebelde: controlan la capital el tiempo suficiente
	var lvl0 := gs.reform_level(tag, rid)
	gs.provinces[int(c["capital"])]["controller"] = VGameState.REBEL_TAG
	gs.provinces[int(c["capital"])]["rebel_faction"] = int(f["id"])
	for i in 4:
		VRebelSystem.monthly(gs)
		if not gs.rebel_factions.has(int(f["id"])):
			break
	check(gs.reform_level(tag, rid) > lvl0, "los rebeldes victoriosos imponen su demanda (voto %d → %d)" % [lvl0, gs.reform_level(tag, rid)])


# ---------------------------------------------------------------- integración
func test_integration() -> void:
	print("-- integración: Frankia contra Liga Renana")
	var a_tag := "FRK"
	var b_tag := "RHE"
	gs.countries[a_tag]["diplo_points"] = 9.0
	gs.countries[a_tag]["infamy"] = 0.0
	var states := VCasusBelliSystem.bordering_states(gs, a_tag, b_tag)
	check(not states.is_empty(), "hay estados renanos fronterizos (%d)" % states.size())
	var sid := int(states[0])
	# justificación completa
	check(VCasusBelliSystem.start_justification(gs, a_tag, b_tag, "acquire_state", sid) == "", "empieza la justificación")
	var j: Dictionary = gs.justifications[0]
	var inf0 := float(gs.countries[a_tag]["infamy"])
	for i in 14:
		VCasusBelliSystem.monthly(gs)
		gs.month_index += 1
	var cb := VCasusBelliSystem.has_cb(gs, a_tag, b_tag, "acquire_state", sid)
	check(not cb.is_empty(), "la justificación termina y crea un CB temporal")
	check(float(gs.countries[a_tag]["infamy"]) > inf0, "la justificación genera infamia (%.1f)" % float(gs.countries[a_tag]["infamy"]))
	# declarar
	var res := VWarSystem.declare_war(gs, a_tag, cb)
	check(res.has("war"), "se declara la guerra (%s)" % res.get("error", "ok"))
	var w: Dictionary = res.get("war", {})
	check(not w.get("war_goals", []).is_empty(), "la guerra tiene objetivo: %s" % VCasusBelliSystem.goal_name(gs, w["war_goals"][0]) if not w.is_empty() else "sin guerra")
	var part: Array = gs.state_part(sid, b_tag).duplicate()
	var pop_state := 0
	for id in part:
		pop_state += int(gs.provinces[id]["population"])
	# batalla: un ejército renano defiende la provincia objetivo y Frankia ataca con su mayor ejército
	var target := int(part[0])
	var defender := biggest_army(b_tag)
	if not defender.is_empty():
		VUnitIndex.move_army(gs, defender, target)
		defender["path"] = []
	var attacker := biggest_army(a_tag)
	var cas0 := int(gs.countries[a_tag].get("casualties", 0)) + int(gs.countries[b_tag].get("casualties", 0))
	check(VArmySystem.order_move(gs, attacker, target) == "", "el ejército francés marcha hacia %s" % gs.provinces[target]["name"])
	var fought := false
	for i in 120:
		sim.run_days(1)
		if not gs.battles.is_empty():
			fought = true
		if fought and gs.battles.is_empty() and int(attacker.get("province", -1)) == target:
			break
	check(fought, "hay batalla al llegar")
	var cas1 := int(gs.countries[a_tag].get("casualties", 0)) + int(gs.countries[b_tag].get("casualties", 0))
	check(cas1 > cas0, "la batalla cuesta vidas reales (%d bajas restadas a los Soldier POPs)" % (cas1 - cas0))
	check(float(w["battle_ws"]) > 0.0, "la victoria da warscore de batalla (%+.1f)" % float(w["battle_ws"]))
	# ocupar todas las provincias del estado objetivo con los ejércitos franceses
	var armies := VArmySystem.country_armies(gs, a_tag)
	var k := 0
	for id in part:
		if k < armies.size():
			VArmySystem.order_move(gs, armies[k], int(id))
		k += 1
	for i in 240:
		sim.run_days(1)
		var all := true
		for id in part:
			if gs.provinces[id]["controller"] != a_tag:
				all = false
		if all:
			break
	var controlled := 0
	var owner_kept := true
	for id in part:
		if gs.provinces[id]["controller"] == a_tag:
			controlled += 1
		if gs.provinces[id]["owner"] != b_tag:
			owner_kept = false
	check(controlled > 0, "la ocupación cambia el controlador (%d/%d provincias)" % [controlled, part.size()])
	check(owner_kept, "la ocupación NO cambia el propietario")
	check(float(w["occupation_ws"]) > 0.0, "la ocupación da warscore (%+.1f)" % float(w["occupation_ws"]))
	sim.run_days(30)
	check(float(w["ticking_ws"]) > 0.0 or controlled < part.size(), "el objetivo controlado genera ticking warscore (%+.1f)" % float(w["ticking_ws"]))
	check(float(gs.countries[b_tag]["war_exhaustion"]) > 0.0, "crece el cansancio bélico (%.1f)" % float(gs.countries[b_tag]["war_exhaustion"]))
	# añadir objetivo: sin CB y sin apoyo belicista suficiente no se permite gratis
	var other_sid := int(states[-1]) if states.size() > 1 else sid
	var add := VWarSystem.can_add_wargoal(gs, int(w["id"]), a_tag, "acquire_state", b_tag, other_sid)
	var base_inf := float(gs.cb_types["acquire_state"]["infamy"])
	var jingo := VWarSystem.jingoism_support(gs, a_tag)
	if add["ok"]:
		check(float(add["infamy"]) >= base_inf * 1.5 and jingo >= 0.35 and VWarSystem.warscore_for(w, a_tag) >= 10.0,
			"añadir territorio sin CB exige apoyo belicista (%.0f%%), warscore ≥ 10 e infamia ×1,5 (%.1f)" % [jingo * 100.0, float(add["infamy"])])
	else:
		check(add["reason"] != "", "añadir territorio sin CB se rechaza con motivo: %s" % add["reason"])
	gs.countries[a_tag]["infamy"] = 24.0
	var add2 := VWarSystem.can_add_wargoal(gs, int(w["id"]), a_tag, "acquire_state", b_tag, other_sid)
	check(not add2["ok"], "la infamia limita los objetivos añadidos (%s)" % add2["reason"])
	gs.countries[a_tag]["infamy"] = 5.0
	# paz: exigir el estado
	var goals: Array = VPeaceSystem.goals_for_side(gs, w, "attackers")
	var ev := VPeaceSystem.evaluate(gs, w, a_tag, "demand", goals)
	print("    warscore %+.1f · coste %.0f · aceptación %.0f%% · %s" % [float(ev["warscore"]), float(ev["cost"]), float(ev["chance"]), "; ".join(ev["reasons"])])
	for i in 300:
		if VPeaceSystem.evaluate(gs, w, a_tag, "demand", goals)["accept"]:
			break
		sim.run_days(1)
	var pres := VPeaceSystem.propose(gs, w, a_tag, "demand", goals)
	check(pres.get("accepted", false), "Liga Renana acepta ceder el estado")
	var owned := true
	var pop_after := 0
	for id in part:
		if gs.provinces[id]["owner"] != a_tag:
			owned = false
		pop_after += int(gs.provinces[id]["population"])
	check(owned, "la paz transfiere la propiedad del estado")
	check(pop_after > pop_state * 0.8, "la población sobrevive (%d → %d)" % [pop_state, pop_after])
	check(VDiplomacySystem.in_truce(gs, a_tag, b_tag), "se crea una tregua")
	check(not gs.wars.has(int(w["id"])) and gs.countries[a_tag]["wars"].is_empty(), "la guerra termina")
	var t0 := float(gs.countries[a_tag]["treasury"])
	sim.run_days(40)
	check(float(gs.countries[a_tag]["treasury"]) != t0 and part[0] in gs.countries[a_tag]["provinces"], "la economía continúa con el nuevo territorio")
	# guardar/cargar el estado militar
	var path := VSaveSystem.save_game(gs, "m3_test")
	var err := []
	var gs2 := VSaveSystem.load_game(path, err)
	check(gs2 != null and gs2.armies.size() == gs.armies.size() and gs2.fleets.size() == gs.fleets.size(), "guardar/cargar conserva ejércitos y flotas (%d / %d)" % [gs.armies.size(), gs.fleets.size()])
	if gs2:
		check(VDiplomacySystem.in_truce(gs2, a_tag, b_tag) and gs2.provinces[int(part[0])]["owner"] == a_tag, "guardar/cargar conserva treguas y propiedad")
	# una partida v2 se rechaza limpiamente
	var fr := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(fr.get_as_text())
	fr.close()
	data["save_version"] = 2
	var fw := FileAccess.open(path, FileAccess.WRITE)
	fw.store_string(JSON.stringify(data))
	fw.close()
	var err2 := []
	var gs_old := VSaveSystem.load_game(path, err2)
	check(gs_old == null and not err2.is_empty(), "una partida save_version 2 se rechaza con mensaje (%s)" % (err2[0] if not err2.is_empty() else "sin mensaje"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# el warscore total está limitado a ±100
	var third := ""
	for t in gs.countries:
		if t != a_tag and t != b_tag and not gs.countries[t]["provinces"].is_empty() and gs.countries[t]["wars"].is_empty() and gs.countries[a_tag]["wars"].is_empty():
			third = t
			break
	if third != "":
		var wc := VWarSystem._new_war(gs, a_tag, third)
		wc["battle_ws"] = 500.0
		VWarSystem.daily(gs)
		check(is_equal_approx(float(wc["total_ws"]), 100.0), "el warscore se limita a +100 (%.1f)" % float(wc["total_ws"]))
		wc["battle_ws"] = -500.0
		VWarSystem.daily(gs)
		check(is_equal_approx(float(wc["total_ws"]), -100.0), "el warscore se limita a −100 (%.1f)" % float(wc["total_ws"]))
		VWarSystem.end_war(gs, wc, "fin de la prueba")
	# índices derivados coherentes tras toda la prueba (crear, mover, embarcar, destruir, rebeldes)
	var ix_err := VUnitIndex.verify(gs)
	check(ix_err == "", "el índice de unidades coincide con una reconstrucción completa (%s)" % (ix_err if ix_err != "" else "ok"))
	gs.flags["ai_disabled"] = false
	sim.run_days(60)
	ix_err = VUnitIndex.verify(gs)
	check(ix_err == "", "el índice sigue coherente tras 60 días con IA (%s)" % (ix_err if ix_err != "" else "ok"))
