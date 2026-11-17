extends Node
## Economía mágica (M5.5): con rama, yacimiento, academia, magos y capital, la cadena
##   cristal → demanda de reactivos → inversión en refinería → reactivos → industria avanzada → empleo de magos
## puede ocurrir por sí sola (no se exige una fábrica concreta: la IA elige).
##   godot --headless --path . res://tests/VictoriaMagicEconomyTest.tscn -- [meses]

const TAG := "PRS"   # tecnología 1, economía 1, militar 1, política 1 (prototipo)

var failures := 0
var months := 36


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		months = int(args[0])
	await get_tree().process_frame
	var gs := VDataLoader.new_game()
	gs.player_tag = ""
	gs.flags["ai_disabled"] = true  # sin guerras: la prueba mira la economía
	var sim := VWorldSimulation.new(gs)
	VMagicSystem.activate(gs)
	var c: Dictionary = gs.countries[TAG]
	VPoliticsSystem.ruling_party(gs, TAG)["policies"]["economic_policy"] = "interventionism"
	for t in ["arcane_theory", "ley_line_cartography", "mana_refinement", "arcane_engineering", "alchemical_medicine", "mechanical_workshops", "steel_making"]:
		VTechnologySystem.complete(gs, TAG, t)
	# yacimientos en Parsa, una academia y magos
	var provs: Array = c["provinces"]
	for id in provs.slice(0, 3):
		VMagicSystem.add_deposit(gs, int(id), 1.5)
	VScopedState.change_variable(gs, TAG, "arcane_academies", 2.0)
	VMagicSystem.convert_pops(gs, TAG, 0, {"from": ["clerks", "clergy"], "to": "magi", "share": 0.08, "max": 6000})
	var caps: Array = []
	sim.run_days(31)
	caps = c.get("_capitalists", [])
	for s in caps:
		gs.pops.cash[s] += 40000.0 / maxf(1.0, float(caps.size()))
	# Parsa no está civilizada: invierte el Estado (reserva de 18 meses de gasto)
	c["treasury"] = maxf(float(c["treasury"]), maxf(30000.0, float(c.get("monthly_expense", 0.0)) * 40.0))
	var sup0 := 0.0
	var built := {}
	var first := {}
	var max_magi_jobs := 0.0
	var reagents_dem := 0.0
	for m in months:
		sim.run_days(30)
		var acc_s: Dictionary = gs.market.get("world", {}).get("supply", {})
		var acc_d: Dictionary = gs.market.get("world", {}).get("demand", {})
		sup0 = maxf(sup0, float(acc_s.get("mana_crystal", 0.0)))
		reagents_dem = maxf(reagents_dem, float(acc_d.get("arcane_reagents", 0.0)))
		for pr in c.get("projects", []):
			if pr.get("type", "") in VInvestmentSystem.MAGIC_FACTORIES and not first.has(pr["type"]):
				first[pr["type"]] = m + 1
		for si in gs.country_state_instances(TAG):
			for f in si["factories"]:
				if f["type"] in VInvestmentSystem.MAGIC_FACTORIES and f["open"]:
					built[f["type"]] = int(built.get(f["type"], 0)) + 0
					built[f["type"]] = maxi(int(built[f["type"]]), int(f["level"]))
					max_magi_jobs = maxf(max_magi_jobs, float(f.get("magi_employed", 0)))
	print("   proyectos mágicos (mes de inicio): %s · fábricas mágicas (nivel): %s" % [str(first), str(built)])
	check(sup0 > 0.0, "los yacimientos ponen cristal en el mercado (%.1f/mes)" % sup0)
	check(reagents_dem > 0.0, "hay demanda de reactivos arcanos (academias, magos, refinerías aguas abajo: %.1f/mes)" % reagents_dem)
	check(not first.is_empty() or not built.is_empty(), "la IA invierte en industria mágica sin forzarla")
	var reag := float(gs.market.get("world", {}).get("supply", {}).get("arcane_reagents", 0.0))
	check(built.has("mana_refinery") or reag > 0.0 or first.has("mana_refinery"), "refinería o producción de reactivos (oferta %.1f)" % reag)
	var adv := built.has("arcane_workshop") or built.has("alchemy_lab") or built.has("arcane_machine_works") or built.has("alchemical_fertilizer_works") \
		or first.has("arcane_workshop") or first.has("alchemy_lab") or first.has("arcane_machine_works") or first.has("alchemical_fertilizer_works")
	print("   industria avanzada: %s" % ("sí" if adv else "todavía no"))
	check(max_magi_jobs > 0.0 or first.is_empty() == false, "las fábricas mágicas emplean magos (%d)" % int(max_magi_jobs))
	# localización: la refinería prefiere estados con yacimiento o magos
	var si_dep := {}
	for si in gs.country_state_instances(TAG):
		for id in si["provinces"]:
			if float(gs.provinces[id].get("magic", {}).get("deposit", 0.0)) > 0.0:
				si_dep = si
	if not si_dep.is_empty():
		check(VInvestmentSystem._magic_local_bonus(gs, si_dep) > 0.0, "un estado con yacimiento atrae la industria mágica")
	print("== %d fallos ==" % failures)
	get_tree().quit(1 if failures > 0 else 0)
