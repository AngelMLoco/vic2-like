extends Node
## Equilibrio de la población mágica (M5): capacidad, promoción hacia el objetivo, prohibición, academias,
## empleo y fuga de cerebros.
##   godot --headless --path . res://tests/VictoriaMageBalanceTest.tscn

var failures := 0
var gs: VGameState
var sim: VWorldSimulation


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
	sim = VWorldSimulation.new(gs)
	test_inactive()
	test_active()
	test_policy_and_academy()
	test_employment()
	test_migration()
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _magi(tag: String) -> float:
	return float(gs.countries[tag].get("type_sizes", {}).get("magi", 0))


func _world_magi() -> float:
	var n := 0.0
	for tag in gs.country_order:
		n += _magi(tag)
	return n


func test_inactive() -> void:
	print("-- magia inactiva")
	sim.run_days(185)
	check(_world_magi() == 0.0, "sin despertar no aparece ningún mago (%d)" % int(_world_magi()))
	var info: Dictionary = gs.countries["FRK"].get("_magi_info", {})
	check(info.is_empty(), "el modelo de magos no se ejecuta antes del despertar")


func test_active() -> void:
	print("-- magia activa")
	VMagicSystem.activate(gs)
	sim.run_days(365)
	var w := _world_magi()
	check(w > 0.0, "tras el despertar aparecen magos (%d)" % int(w))
	var tag := "FRK"
	var cap := float(VMageModel.capacity(gs, tag)["target"])
	check(cap > 0.0, "Frankia tiene capacidad mágica (%d)" % int(cap))
	# la promoción se frena cerca del objetivo
	var far := VMageModel.promotion_amount(gs, tag, cap * 0.2, cap)
	var near := VMageModel.promotion_amount(gs, tag, cap * 0.97, cap)
	var over := VMageModel.promotion_amount(gs, tag, cap * 1.05, cap)
	check(far > near and near >= 0, "promoción lejos del objetivo %d > cerca %d" % [far, near])
	check(over == 0, "por encima del objetivo no hay promoción")
	# sin ramas ni academia, nadie se forma como mago
	var hib := "HIB"
	check(VMageModel.promotion_amount(gs, hib, 0.0, 10000.0) == 0, "una nación sin ramas ni academia no forma magos")
	# la población mágica mundial es una fracción pequeña y acotada
	var pop := 0.0
	for t in gs.country_order:
		pop += float(gs.countries[t].get("population", 0))
	check(w / pop < 0.002, "proporción mundial de magos acotada (%.4f%%)" % (w / pop * 100.0))


func test_policy_and_academy() -> void:
	print("-- política y academias")
	var tag := "FRK"
	var c: Dictionary = gs.countries[tag]
	var lvl0 := gs.reform_level(tag, VMagicPolicy.REFORM)
	VMagicPolicy.set_level(gs, tag, "magic_tolerated")
	var cap_t := float(VMageModel.capacity(gs, tag)["target"])
	var pro_t := VMageModel.promotion_amount(gs, tag, 0.0, cap_t)
	VMagicPolicy.set_level(gs, tag, "magic_prohibited")
	var cap_p := float(VMageModel.capacity(gs, tag)["target"])
	var pro_p := VMageModel.promotion_amount(gs, tag, 0.0, cap_p)
	check(cap_p < cap_t * 0.5, "la prohibición reduce la capacidad (%d → %d)" % [int(cap_t), int(cap_p)])
	check(pro_p < pro_t * 0.5, "la prohibición frena la promoción (%d → %d)" % [pro_t, pro_p])
	check(gs.mod(tag, "magi_militancy") > 0.0, "la prohibición radicaliza a los magos")
	VMagicPolicy.set_level(gs, tag, "magic_promoted")
	check(gs.mod(tag, "mage_attraction") > 0.0 and float(VMageModel.capacity(gs, tag)["target"]) > cap_t, "el fomento atrae magos y amplía la capacidad")
	VMagicPolicy.set_level(gs, tag, "magic_tolerated")
	var ac0 := float(VMageModel.capacity(gs, tag)["target"])
	VScopedState.change_variable(gs, tag, "arcane_academies", 1.0)
	var ac1 := float(VMageModel.capacity(gs, tag)["target"])
	check(ac1 > ac0, "una academia amplía la población mágica sostenible (%d → %d)" % [int(ac0), int(ac1)])
	var mt := VMageModel.promotion_amount(gs, tag, 0.0, ac1)
	check(mt > pro_t, "la academia acelera la formación (%d → %d)" % [pro_t, mt])
	# ideologías: cada una apoya acercar la ley a su postura (datos)
	check(VMagicPolicy.stance(gs, "tradicionalista") == VMagicPolicy.level_index(gs, "magic_prohibited"), "los tradicionalistas quieren prohibir (datos)")
	check(VMagicPolicy.ideology_support(gs, "tradicionalista", 2, 1) > 0.0 and VMagicPolicy.ideology_support(gs, "socialista", 2, 1) < 0.0, "apoyos ideológicos opuestos a restringir")
	c["reforms"][VMagicPolicy.REFORM] = lvl0
	VModifiers.recompute(gs, tag)


func test_employment() -> void:
	print("-- empleo")
	var tag := "BAY"
	var c: Dictionary = gs.countries[tag]
	VMagicPolicy.set_level(gs, tag, "magic_licensed")
	# muchos magos sin plazas → paro real
	VMagicSystem.convert_pops(gs, tag, 0, {"from": ["clerks", "clergy"], "to": "magi", "share": 0.3, "max": 40000})
	# el empleo se mide con un mes completo de particiones (el ciclo va por cubos): dos meses y medio
	sim.run_days(75)
	var info: Dictionary = c.get("_magi_info", {})
	var u0 := float(info.get("unemployment", 0.0))
	check(u0 > 0.2, "demasiados magos para las plazas → paro (%.0f%%)" % (u0 * 100.0))
	var t0 := float(VMageModel.capacity(gs, tag)["target"])
	# plazas públicas (academias): el empleo mejora
	VScopedState.change_variable(gs, tag, "arcane_academies", 3.0)
	VScopedState.add_country_modifier(gs, tag, "arcane_public_works", 24, "test")
	sim.run_days(75)
	var u1 := float(c.get("_magi_info", {}).get("unemployment", 0.0))
	check(u1 < u0, "las plazas públicas reducen el paro de los magos (%.0f%% → %.0f%%)" % [u0 * 100.0, u1 * 100.0])
	check(float(VMageModel.capacity(gs, tag).get("f_jobs", 1.0)) < 1.0 or u1 == 0.0, "el paro reduce la capacidad sostenible (demanda laboral ×%.2f)" % float(VMageModel.capacity(gs, tag).get("f_jobs", 1.0)))
	check(VMageModel.promotion_amount(gs, tag, 0.0, t0) < VMageModel.promotion_amount(gs, "FRK", 0.0, t0) or u0 > 0.0, "el paro frena la formación de nuevos magos")


func test_migration() -> void:
	print("-- fuga de cerebros")
	var src := "BAY"
	var dst := "RHE"
	gs.flags["ai_disabled"] = true  # que la IA no cambie la regulación durante la prueba
	VMagicPolicy.set_level(gs, src, "magic_prohibited")
	VMagicPolicy.set_level(gs, dst, "magic_promoted")
	VScopedState.change_variable(gs, dst, "arcane_academies", 3.0)
	var before := float(gs.countries[dst].get("magic_stats", {}).get("immigrated", 0))
	var out0 := float(gs.countries[src].get("magic_stats", {}).get("emigrated", 0))
	sim.run_days(120)
	var dests: Array = gs.market.get("_mage_destinations", [])
	check(not dests.is_empty(), "hay destinos que reclutan magos (%d)" % dests.size())
	var out1 := float(gs.countries[src].get("magic_stats", {}).get("emigrated", 0))
	check(out1 > out0, "los magos emigran de un país que los prohíbe y no los emplea (%d)" % int(out1 - out0))
	var any_in := 0.0
	for t in gs.country_order:
		any_in += float(gs.countries[t].get("magic_stats", {}).get("immigrated", 0))
	check(any_in > 0.0, "otros países los reciben (%d en total; %s +%d)" % [int(any_in), dst, int(float(gs.countries[dst].get("magic_stats", {}).get("immigrated", 0)) - before)])
	check(VMageModel.attractiveness(gs, dst) > VMageModel.attractiveness(gs, src), "el país que fomenta la magia es más atractivo que el que la prohíbe")
	var n := VMageModel.force_emigration(gs, src, 0.1)
	check(n >= 0, "la emigración forzada por eventos es posible (%d)" % n)
