extends Node
## Pruebas del motor de eventos y decisiones (M4):
##   godot --headless --path . res://tests/VictoriaEventTest.tscn

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
	test_loader()
	test_events()
	test_player_queue()
	test_decisions()
	test_frequency()
	test_save()
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Inyecta un evento de prueba (mismo compilador y validación que los datos).
func add_event(d: Dictionary) -> Dictionary:
	var errs := []
	var e := VEventSystem._compile_event(gs, d, errs)
	check(errs.is_empty(), "el evento de prueba %s compila sin errores %s" % [d["id"], str(errs)])
	gs.event_defs[d["id"]] = e
	VEventSystem._build_index(gs)
	return e


# ------------------------------------------------------------------ carga y errores de datos
func test_loader() -> void:
	print("-- carga y validación")
	check(gs.data_errors.is_empty(), "los datos del juego cargan sin errores (%d)" % gs.data_errors.size())
	check(gs.event_defs.size() >= 30 and gs.decision_defs.size() >= 8, "eventos %d · decisiones %d" % [gs.event_defs.size(), gs.decision_defs.size()])
	var errs := []
	VEventSystem._compile_event(gs, {"id": "bad.1", "trigger": {"no_such_condition": 1, "tag": "ZZZ", "has_technology": "magic_rocket", "good_price": {"unobtainium": 2}},
		"options": [{"name": "x", "effects": {"no_such_effect": 1, "add_country_modifier": {"id": "nope"}}, "follow_up": {"id": "bad.2"}}]}, errs)
	var joined := " | ".join(errs)
	check("condición desconocida «no_such_condition»" in joined, "detecta condición desconocida")
	check("país desconocido «ZZZ»" in joined, "detecta país desconocido")
	check("tecnología desconocida «magic_rocket»" in joined, "detecta tecnología desconocida")
	check("bien desconocido «unobtainium»" in joined, "detecta bien desconocido")
	check("efecto desconocido «no_such_effect»" in joined, "detecta efecto desconocido")
	check("modificador desconocido «nope»" in joined, "detecta modificador inválido")
	var errs2 := []
	VEventSystem._compile_event(gs, {"id": "bad.3", "options": []}, errs2)
	check(" ".join(errs2).contains("no tiene opciones"), "detecta evento sin opciones")
	# ids duplicados y follow-up inválido: carga desde un directorio temporal
	var root := "user://_evtest/"
	DirAccess.make_dir_recursive_absolute(root + "events")
	var f := FileAccess.open(root + "events/test.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"events": [
		{"id": "dup", "options": [{"name": "a", "follow_up": {"id": "missing.event"}}]},
		{"id": "dup", "options": [{"name": "b"}]}]}))
	f.close()
	var gs2 := VGameState.new()
	gs2.countries = gs.countries
	gs2.goods = gs.goods
	gs2.technologies = gs.technologies
	VEventSystem.load_definitions(gs2, root)
	var j2 := " | ".join(gs2.data_errors)
	check("id de evento duplicado «dup»" in j2, "detecta id de evento duplicado")
	check("follow-up a un evento inexistente «missing.event»" in j2, "detecta follow-up inválido")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "events/test.json"))


# ------------------------------------------------------------------ motor de eventos
func test_events() -> void:
	print("-- eventos")
	var c: Dictionary = gs.countries["FRK"]
	# trigger verdadero / falso
	var e1 := add_event({"id": "t.cond", "scope": "country", "trigger": {"tag": "FRK", "treasury": 0, "civilized": true}, "options": [{"name": "a"}]})
	check(VEventConditions.check(gs, e1["trigger"], {"tag": "FRK"}), "trigger verdadero")
	var e2 := add_event({"id": "t.cond2", "scope": "country", "trigger": {"treasury": 1e15}, "options": [{"name": "a"}]})
	check(not VEventConditions.check(gs, e2["trigger"], {"tag": "FRK"}), "trigger falso")
	check(not VEventConditions.check(gs, e1["trigger"], {"tag": "BRI"}), "condición de país (tag) excluye a otras naciones")
	# efecto de opción + once
	var t0 := float(c["treasury"])
	var e3 := add_event({"id": "t.once", "scope": "country", "once": true, "options": [{"name": "a", "effects": {"add_treasury": 100}}]})
	check(VEventSystem._consider(gs, e3, {"tag": "FRK"}, "force"), "el evento ocurre")
	check(is_equal_approx(float(c["treasury"]), t0 + 100.0), "la opción aplica su efecto (tesoro +100)")
	check(not VEventSystem._consider(gs, e3, {"tag": "FRK"}, "force"), "fire_only_once: no vuelve a ocurrir")
	# cooldown
	var e4 := add_event({"id": "t.cd", "scope": "country", "type": "major", "cooldown": 3, "options": [{"name": "a"}]})
	VEventSystem._consider(gs, e4, {"tag": "FRK"}, "force")
	check(not VEventSystem._consider(gs, e4, {"tag": "FRK"}, "force"), "cooldown: bloqueado dentro del plazo")
	gs.month_index += 3
	check(VEventSystem._consider(gs, e4, {"tag": "FRK"}, "force"), "cooldown: vuelve a estar disponible tras 3 meses")
	# MTTH determinista y con la frecuencia esperada
	var e5 := add_event({"id": "t.mtth", "scope": "country", "mtth": {"months": 12}, "options": [{"name": "a"}]})
	var r1 := VEventSystem._roll(gs, e5, {"tag": "FRK"})
	check(r1 == VEventSystem._roll(gs, e5, {"tag": "FRK"}), "MTTH determinista (misma tirada con el mismo estado)")
	var hits := 0
	var saved: int = gs.date.day
	for i in 2000:
		gs.date.day = 1 + (i % 28)
		gs.date.month = 1 + (i / 28) % 12
		gs.date.year = 140 + i / 336
		if VEventSystem._roll(gs, e5, {"tag": "FRK"}):
			hits += 1
	gs.date.year = 136
	gs.date.month = 1
	gs.date.day = saved
	var expected := 1.0 - pow(0.5, 1.0 / 12.0)
	check(absf(float(hits) / 2000.0 - expected) < 0.02, "frecuencia MTTH %.3f ≈ esperada %.3f" % [float(hits) / 2000.0, expected])
	var e5b := add_event({"id": "t.mtth2", "scope": "country", "mtth": {"months": 120, "modifiers": [{"factor": 0.01, "tag": "FRK"}]}, "options": [{"name": "a"}]})
	var m1 := 0
	var m2 := 0
	for i in 200:
		gs.date.day = 1 + i % 28
		gs.date.month = 1 + i / 28
		if VEventSystem._roll(gs, e5b, {"tag": "FRK"}):
			m1 += 1
		if VEventSystem._roll(gs, e5b, {"tag": "BRI"}):
			m2 += 1
	gs.date.month = 1
	gs.date.day = 1
	check(m1 > m2 * 5, "modificador de MTTH (factor 0.01 para FRK): %d frente a %d" % [m1, m2])
	# ámbitos: provincia y global
	var cap := int(c["capital"])
	var e6 := add_event({"id": "t.prov", "scope": "province", "province_candidates": "capital", "trigger": {"is_capital": true},
		"options": [{"name": "a", "effects": {"set_province_flag": "TEST_PFLAG"}}]})
	VEventSystem._consider_provinces(gs, e6, "FRK")
	check(VScopedState.has_province_flag(gs, cap, "TEST_PFLAG"), "ámbito provincia: el evento ocurre en la capital y pone una bandera de provincia")
	var c6 := VEventConditions.compile(gs, {"province_flag": "TEST_PFLAG"}, [], "t")
	check(VEventConditions.check(gs, c6, {"tag": "FRK", "prov": cap}), "condición de bandera de provincia")
	var e7 := add_event({"id": "t.global", "scope": "global", "type": "hidden", "trigger": {"not_flag": "TEST_GFLAG"}, "options": [{"name": "a", "effects": {"set_flag": "TEST_GFLAG"}}]})
	gs.month_index += 1
	VEventSystem.monthly(gs)
	check(gs.flags.get("TEST_GFLAG", false), "ámbito global: el evento mensual global ocurre y pone una bandera global")
	# banderas de nación
	var e8 := add_event({"id": "t.cflag", "scope": "country", "type": "hidden", "options": [{"name": "a", "effects": {"set_country_flag": ["A_FLAG", "B_FLAG"]}}]})
	VEventSystem._consider(gs, e8, {"tag": "FRK"}, "force")
	check(VScopedState.has_country_flag(gs, "FRK", "A_FLAG") and VScopedState.has_country_flag(gs, "FRK", "B_FLAG"), "banderas de nación (lista)")
	check(VEventConditions.check(gs, VEventConditions.compile(gs, {"country_flag": "A_FLAG"}, [], "t"), {"tag": "FRK"}), "condición country_flag")
	# IA: pesos y no siempre la opción A
	var e9 := add_event({"id": "t.ai", "scope": "country", "options": [{"name": "a", "ai_weight": 0}, {"name": "b", "ai_weight": 10}]})
	check(VEventAI.choose(gs, e9, {"tag": "FRK"}) == 1, "la IA respeta los pesos (opción con peso 0 nunca)")
	var e10 := add_event({"id": "t.ai2", "scope": "country", "options": [{"name": "a", "ai_weight": 10}, {"name": "b", "ai_weight": 10}]})
	var seen := {}
	for t in gs.country_order:
		seen[VEventAI.choose(gs, e10, {"tag": t})] = true
	check(seen.size() == 2, "la IA no elige siempre la opción A")
	check(VEventAI.choose(gs, e10, {"tag": "FRK"}) == VEventAI.choose(gs, e10, {"tag": "FRK"}), "elección de la IA determinista")
	var e11 := add_event({"id": "t.ai3", "scope": "country", "options": [{"name": "a", "trigger": {"treasury": 1e15}, "ai_weight": 100}, {"name": "b", "ai_weight": 1}]})
	check(VEventAI.choose(gs, e11, {"tag": "FRK"}) == 1, "la IA no elige opciones cuyo trigger falla")
	# follow-up
	add_event({"id": "t.fu2", "scope": "country", "cadence": "follow_up", "type": "hidden", "options": [{"name": "a", "effects": {"set_country_flag": "FOLLOWED"}}]})
	var e12 := add_event({"id": "t.fu1", "scope": "country", "type": "hidden", "options": [{"name": "a", "follow_up": {"id": "t.fu2", "days": 2}}]})
	VEventSystem._consider(gs, e12, {"tag": "FRK"}, "force")
	check(not VScopedState.has_country_flag(gs, "FRK", "FOLLOWED"), "el follow-up aún no ha ocurrido")
	var sim := VWorldSimulation.new(gs)
	sim.run_days(3)
	check(VScopedState.has_country_flag(gs, "FRK", "FOLLOWED"), "el follow-up ocurre a los 2 días")
	# modificador temporal y caducidad
	var r0 := gs.mod("FRK", "research")
	var e13 := add_event({"id": "t.mod", "scope": "country", "type": "hidden", "options": [{"name": "a", "effects": {"add_country_modifier": {"id": "salon_culture", "months": 2}}}]})
	VEventSystem._consider(gs, e13, {"tag": "FRK"}, "force")
	check(is_equal_approx(gs.mod("FRK", "research"), r0 + 0.05), "modificador temporal aplicado (investigación %+.2f)" % (gs.mod("FRK", "research") - r0))
	gs.month_index += 2
	VScopedState.expire(gs)
	check(is_equal_approx(gs.mod("FRK", "research"), r0), "el modificador caduca a los 2 meses")
	var ep := add_event({"id": "t.pmod", "scope": "province", "type": "hidden", "province_candidates": "capital", "options": [{"name": "a", "effects": {"add_province_modifier": {"id": "riots", "months": 1}}}]})
	VEventSystem._consider(gs, ep, {"tag": "FRK", "prov": cap}, "force")
	check(gs.provinces[cap].has("pmods") and float(gs.provinces[cap]["pmods"].get("militancy", 0.0)) > 0.0, "modificador de provincia aplicado")
	gs.month_index += 1
	VScopedState.expire(gs)
	check(not gs.provinces[cap].has("pmods"), "el modificador de provincia caduca")
	# on_action
	var e14 := add_event({"id": "t.onaction", "scope": "country", "type": "hidden", "cadence": "on_action", "on_action": "reform_passed", "options": [{"name": "a", "effects": {"set_country_flag": "ON_REFORM"}}]})
	VEventSystem.notify(gs, "reform_passed", {"tag": "FRK"})
	check(VScopedState.has_country_flag(gs, "FRK", "ON_REFORM"), "on_action: el gancho «reform_passed» dispara su evento")
	for id in ["t.cond", "t.cond2", "t.once", "t.cd", "t.mtth", "t.mtth2", "t.prov", "t.global", "t.cflag", "t.ai", "t.ai2", "t.ai3", "t.fu1", "t.fu2", "t.mod", "t.pmod", "t.onaction"]:
		gs.event_defs.erase(id)
	VEventSystem._build_index(gs)


# ------------------------------------------------------------------ cola del jugador
func test_player_queue() -> void:
	print("-- cola del jugador")
	gs.player_tag = "FRK"
	var t0 := float(gs.countries["FRK"]["treasury"])
	add_event({"id": "t.p1", "scope": "country", "options": [{"name": "a", "effects": {"add_treasury": 10}}, {"name": "b", "effects": {"add_treasury": 20}}]})
	add_event({"id": "t.p2", "scope": "country", "type": "major", "options": [{"name": "a"}]})
	VEventSystem.debug_fire(gs, "t.p1", "FRK")
	VEventSystem.debug_fire(gs, "t.p2", "FRK")
	var q := VEventSystem.pending(gs)
	check(q.size() == 2 and q[0]["id"] == "t.p1" and q[1]["id"] == "t.p2", "dos eventos del jugador quedan en cola, en orden")
	check(is_equal_approx(float(gs.countries["FRK"]["treasury"]), t0), "la opción no se aplica hasta que el jugador elige")
	VEventSystem.choose(gs, 0, 1)
	check(is_equal_approx(float(gs.countries["FRK"]["treasury"]), t0 + 20.0) and VEventSystem.pending(gs).size() == 1, "el jugador elige la opción B; el siguiente evento sigue en cola")
	VEventSystem.choose(gs, 0, 0)
	check(VEventSystem.pending(gs).is_empty(), "cola vacía tras resolver")
	gs.event_defs.erase("t.p1")
	gs.event_defs.erase("t.p2")
	VEventSystem._build_index(gs)
	gs.player_tag = ""


# ------------------------------------------------------------------ decisiones
func test_decisions() -> void:
	print("-- decisiones")
	var c: Dictionary = gs.countries["FRK"]
	var errs := []
	var mk := func(d: Dictionary) -> Dictionary:
		var errs2 := []
		var base := {"id": d["id"], "name": d["id"], "desc": "", "category": "political", "tags": {}, "requires_flag": "",
			"visible": VEventConditions.compile(gs, d.get("visible", {}), errs2, "t"), "available": VEventConditions.compile(gs, d.get("available", {}), errs2, "t"),
			"cost": d.get("cost", {}), "effects": VEventEffects.validate(gs, d.get("effects", {}), errs2, "t"), "ai_base": float(d.get("ai", 0.0)), "ai_mods": [],
			"cooldown": int(d.get("cooldown", 0)), "once": bool(d.get("once", false))}
		for t in d.get("tags", []):
			base["tags"][t] = true
		gs.decision_defs[d["id"]] = base
		return base
	var d1: Dictionary = mk.call({"id": "td.vis", "tags": ["BRI"]})
	check(not VDecisionSystem.is_visible(gs, "FRK", d1) and VDecisionSystem.is_visible(gs, "BRI", d1), "visible solo para su nación")
	var d2: Dictionary = mk.call({"id": "td.av", "available": {"treasury": 1e15}})
	var why := VDecisionSystem.unavailable_reason(gs, "FRK", d2)
	check(why.begins_with("Requiere:") and "tesoro" in why, "no disponible con motivo legible: «%s»" % why)
	c["treasury"] = 5000.0
	var p0 := float(c.get("prestige", 0.0))
	mk.call({"id": "td.take", "cost": {"treasury": 1000, "prestige": 1}, "effects": {"add_prestige": 5, "set_country_flag": "TOOK_IT"}, "cooldown": 6})
	var err := VDecisionSystem.take(gs, "FRK", "td.take")
	check(err == "" and is_equal_approx(float(c["treasury"]), 4000.0), "tomar la decisión cobra el coste (tesoro −1000)")
	check(VScopedState.has_country_flag(gs, "FRK", "TOOK_IT") and is_equal_approx(float(c["prestige"]), p0 - 1.0 + 5.0), "la decisión aplica sus efectos")
	var err2 := VDecisionSystem.take(gs, "FRK", "td.take")
	check(err2.contains("esperar"), "cooldown de la decisión: «%s»" % err2)
	check(not VDecisionSystem.list_available(gs, "FRK").has("td.take"), "no aparece como disponible durante el cooldown")
	# IA: con peso 1 la toma en su trimestre
	mk.call({"id": "td.ai", "ai": 1.0, "effects": {"set_country_flag": "AI_TOOK"}, "once": true})
	gs.flags.erase("ai_disabled")
	var idx := gs.country_order.find("BRI")
	for m in 3:
		gs.month_index += 1
		VDecisionSystem.ai_country(gs, "BRI", idx)
	check(VScopedState.has_country_flag(gs, "BRI", "AI_TOOK"), "la IA toma decisiones disponibles")
	gs.flags["ai_disabled"] = true
	# decisiones reales del juego
	var lists := VDecisionSystem.list_for(gs, "FRK")
	check(lists["available"].size() + lists["potential"].size() > 0, "Frankia ve decisiones del juego (%d disponibles, %d potenciales)" % [lists["available"].size(), lists["potential"].size()])
	for id in ["td.vis", "td.av", "td.take", "td.ai"]:
		gs.decision_defs.erase(id)


# ------------------------------------------------------------------ frecuencia con jugador
func test_frequency() -> void:
	print("-- frecuencia (3 años con jugador)")
	gs.player_tag = "FRK"
	gs.flags.erase("ai_disabled")
	var sim := VWorldSimulation.new(gs)
	var shown := 0
	var majors := 0
	for d in 1095:
		sim.run_days(1)
		var q := VEventSystem.pending(gs)
		while not q.is_empty():
			var e: Dictionary = gs.event_defs[q[0]["id"]]
			shown += 1
			if e["type"] == "major":
				majors += 1
			VEventSystem.choose(gs, 0, VEventAI.choose(gs, e, q[0]["ctx"]))
	var per_year := shown / 3.0
	print("     ventanas para el jugador: %d en 3 años (%.1f/año, %d mayores)" % [shown, per_year, majors])
	check(per_year <= 15.0, "sin spam de eventos (%.1f ventanas/año)" % per_year)
	gs.player_tag = ""
	gs.flags["ai_disabled"] = true


# ------------------------------------------------------------------ guardado
func test_save() -> void:
	print("-- guardado v5")
	VScopedState.set_country_flag(gs, "FRK", "SAVED_FLAG")
	VScopedState.change_variable(gs, "FRK", "test_var", 42.0, true)
	VScopedState.add_country_modifier(gs, "FRK", "urban_growth", 12, "test")
	var hist: int = VScopedState.es(gs)["history"].size()
	var path := VSaveSystem.save_game(gs, "_event_test")
	var err := []
	var g2 := VSaveSystem.load_game(path, err)
	check(g2 != null, "carga v5 (%s)" % (err[0] if not err.is_empty() else "ok"))
	if g2:
		check(VScopedState.has_country_flag(g2, "FRK", "SAVED_FLAG") and is_equal_approx(VScopedState.get_variable(g2, "FRK", "test_var"), 42.0), "banderas y variables de nación se conservan")
		check(VScopedState.has_country_modifier(g2, "FRK", "urban_growth") and g2.mod("FRK", "pop_growth") > 0.0, "modificadores temporales se conservan y vuelven a aplicarse")
		check(VScopedState.es(g2)["history"].size() == hist and hist > 0, "historial de eventos conservado (%d entradas)" % hist)
		check(not VScopedState.es(g2)["decisions"].get("FRK", {}).is_empty(), "decisiones tomadas conservadas")
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	data["save_version"] = 4
	var fw := FileAccess.open(path, FileAccess.WRITE)
	fw.store_string(JSON.stringify(data))
	fw.close()
	var err2 := []
	check(VSaveSystem.load_game(path, err2) == null and not err2.is_empty(), "una partida v4 se rechaza limpiamente")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
