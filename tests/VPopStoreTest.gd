extends Node
## Pruebas del almacén de POPs (VPopStore):
##   godot --headless --path . res://tests/VPopStoreTest.tscn

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
	var ps := gs.pops
	print("-- almacén")
	check(ps.verify(gs) == "", "almacén coherente tras generar (%s)" % ps.verify(gs))
	check(ps.count() > 15000, "POPs generados (%d)" % ps.count())
	var prov := int(gs.countries["FRK"]["capital"])
	var n0: int = gs.provinces[prov]["pop_slots"].size()
	# crear y leer/escribir
	var s := VPopulationSystem.make_pop(gs, "clerks", 5000, "franco", "catolica", prov, 0.3)
	check(ps.is_alive(s) and ps.type_name(s) == "clerks" and ps.size[s] == 5000, "crear un POP (slot %d, id %d)" % [s, ps.id[s]])
	check(gs.provinces[prov]["pop_slots"].size() == n0 + 1 and s in gs.provinces[prov]["pop_slots"], "el POP queda en la lista de su provincia")
	ps.cash[s] = 123.5
	ps.militancy[s] = 2.25
	var d := ps.get_pop_details(s)
	check(is_equal_approx(float(d["cash"]), 123.5) and is_equal_approx(float(d["militancy"]), 2.25) and d["type"] == "clerks", "leer/escribir campos (capa de compatibilidad)")
	check(ps.slot_of(ps.id[s]) == s, "id estable → slot en O(1)")
	# mover
	var other := -1
	for id in gs.countries["FRK"]["provinces"]:
		if int(id) != prov:
			other = int(id)
			break
	ps.move(gs, s, other)
	check(ps.province[s] == other and s in gs.provinces[other]["pop_slots"] and not (s in gs.provinces[prov]["pop_slots"]), "mover un POP de provincia")
	VPopulationSystem.recalc_province(gs, prov)
	VPopulationSystem.recalc_province(gs, other)
	check(ps.verify(gs) == "", "población de las provincias correcta tras mover")
	# promocionar parte de un POP (VMobilitySystem: traslado a un POP del tipo destino)
	var farmers := -1
	for x in gs.provinces[prov]["pop_slots"]:
		if ps.type_id[x] == ps.T_FARMERS:
			farmers = x
	var f0: int = ps.size[farmers]
	var tot0 := int(gs.provinces[prov]["population"])
	var dst := VMobilitySystem._transfer(gs, farmers, gs.provinces[prov], "craftsmen", 1000)
	VPopulationSystem.recalc_province(gs, prov)
	check(ps.size[farmers] == f0 - 1000 and ps.type_name(dst) == "craftsmen" and int(gs.provinces[prov]["population"]) == tot0, "promocionar: 1.000 campesinos pasan a artesanos de fábrica sin perder población")
	# fusionar
	var a := VPopulationSystem.make_pop(gs, "clerks", 2000, "franco", "catolica", prov, 0.3)
	var b := VPopulationSystem.make_pop(gs, "clerks", 3000, "franco", "catolica", prov, 0.3)
	var b_id: int = ps.id[b]
	ps.cash[a] = 10.0
	ps.cash[b] = 20.0
	var merged_before := int(ps.stats["merged"])
	ps.merge(gs, b, a)
	VPopulationSystem.recalc_province(gs, prov)
	check(ps.size[a] == 5000 and is_equal_approx(ps.cash[a], 30.0) and not ps.is_alive(b), "fusionar: tamaño y dinero sumados, el absorbido desaparece")
	check(ps.slot_of(b_id) == a and int(ps.stats["merged"]) == merged_before + 1, "el id del POP fusionado resuelve al que lo absorbió")
	# borrar y reutilizar slot
	var free_before := ps.free_list.size()
	ps.free_slot(gs, a)
	check(not ps.is_alive(a) and ps.free_list.size() == free_before + 1, "borrar un POP deja su slot en la lista libre")
	var c2 := VPopulationSystem.make_pop(gs, "clergy", 700, "franco", "catolica", prov, 0.3)
	check(c2 == a, "la lista libre reutiliza el slot (%d)" % c2)
	VPopulationSystem.recalc_province(gs, prov)
	VPopulationSystem.recalc_province(gs, other)
	check(ps.verify(gs) == "", "almacén coherente tras crear/mover/fusionar/borrar (%s)" % ps.verify(gs))
	# enlaces de Soldier POP
	print("-- Soldier POP y brigadas")
	var army := {}
	for ar in VArmySystem.country_armies(gs, "FRK"):
		army = ar
		break
	var br: Dictionary = gs.brigades[army["brigades"][0]]
	var sp := VArmySystem.brigade_pop(gs, br)
	check(sp >= 0 and ps.type_id[sp] == ps.T_SOLDIERS and int(br["id"]) in ps.brigade_links(sp), "la brigada encuentra su Soldier POP (slot %d) y el POP la enlaza" % sp)
	# fusionar el Soldier POP en otro: el enlace sigue funcionando
	var sp_id: int = ps.id[sp]
	var twin := ps.allocate(gs, "soldiers", 4000, ps.culture_names[ps.culture_id[sp]], ps.religion_names[ps.religion_id[sp]], ps.province[sp])
	ps.merge(gs, sp, twin)
	var sp2 := VArmySystem.brigade_pop(gs, br)
	check(sp2 == twin and int(br["id"]) in ps.brigade_links(twin) and int(br["source_pop_id"]) == ps.id[twin], "tras fusionar el Soldier POP la brigada apunta al POP resultante")
	var size_b: int = ps.size[twin]
	VArmySystem.apply_casualties(gs, br, 300, "FRK")
	check(ps.size[twin] == size_b - 300, "las bajas siguen restando personas al POP enlazado")
	VPopulationSystem.recalc_province(gs, ps.province[twin])
	# simular y comprobar agregados
	print("-- simulación y agregados")
	var sim := VWorldSimulation.new(gs)
	sim.run_days(62)
	check(ps.verify(gs, false) == "", "almacén coherente tras 2 meses (%s)" % ps.verify(gs, false))
	var tot := 0
	var mil := 0.0
	for id in gs.countries["FRK"]["provinces"]:
		for x in gs.provinces[id]["pop_slots"]:
			tot += ps.size[x]
			mil += ps.militancy[x] * ps.size[x]
	var c: Dictionary = gs.countries["FRK"]
	check(abs(int(c["population"]) - tot) <= tot / 200, "población nacional = suma de POPs (%d / %d)" % [int(c["population"]), tot])
	check(absf(float(c["avg_militancy"]) - mil / tot) < 0.2, "militancia media nacional coherente (%.2f / %.2f)" % [float(c["avg_militancy"]), mil / tot])
	check(gs.market.has("mil_diag") and gs.market["mil_diag"].has("net"), "diagnóstico de militancia disponible")
	# guardar / cargar
	print("-- guardado v4")
	var path := VSaveSystem.save_game(gs, "_popstore_test")
	var err := []
	var gs2 := VSaveSystem.load_game(path, err)
	check(gs2 != null, "carga de la partida v4 (%s)" % (err[0] if not err.is_empty() else "ok"))
	if gs2:
		var ps2 := gs2.pops
		check(ps2.count() == ps.count(), "mismo número de POPs (%d)" % ps2.count())
		check(ps2.verify(gs2) == "", "almacén cargado coherente (%s)" % ps2.verify(gs2))
		var same := true
		for x in ps.id.size():
			if ps.id[x] < 0:
				continue
			var y := ps2.slot_of(ps.id[x])
			if y < 0 or ps2.size[y] != ps.size[x] or absf(ps2.cash[y] - ps.cash[x]) > 1e-6 or ps2.type_name(y) != ps.type_name(x) \
					or absf(ps2.militancy[y] - ps.militancy[x]) > 1e-9 or ps2.issues[y] != ps.issues[x] \
					or absf(ps2.ideology[y * ps2.n_ideo] - ps.ideology[x * ps.n_ideo]) > 1e-9:
				same = false
				print("     difiere el POP id %d" % ps.id[x])
				break
		check(same, "los campos de todos los POPs se conservan")
		check(ps2.slot_of(sp_id) >= 0 and ps2.id[ps2.slot_of(sp_id)] == ps.id[twin], "los alias de POPs fusionados se conservan")
		check(ps2.slot_of(b_id) < 0, "el alias de un POP absorbido por otro que luego se borró ya no resuelve")
		var br2: Dictionary = gs2.brigades[int(br["id"])]
		var sp3 := VArmySystem.brigade_pop(gs2, br2)
		check(sp3 >= 0 and int(br["id"]) in ps2.brigade_links(sp3), "el enlace brigada ↔ Soldier POP sobrevive al guardado")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)
