## Sonda de rendimiento del pipeline mensual (sin interfaz):
##   godot --headless --path . -s tests/VictoriaPerfProbe.gd
extends SceneTree

func _init() -> void:
	pass

func _process(_d: float) -> bool:
	var gs := VDataLoader.new_game()
	var sim := VWorldSimulation.new(gs)
	sim.run_days(40)
	var ids := []
	var npops := 0
	for id in range(1, gs.first_sea_id):
		if gs.provinces[id]["owner"] != "":
			ids.append(id)
			npops += gs.provinces[id]["pops"].size()
	print("owned provinces %d pops %d" % [ids.size(), npops])
	var t := Time.get_ticks_usec()
	var s := 0.0
	for id in ids:
		for pop in gs.provinces[id]["pops"]:
			s += float(pop["size"]) + float(pop["cash"]) + float(pop["literacy"]) + float(pop["militancy"]) + float(pop["consciousness"]) + float(pop["employment"])
	print("baseline 6 reads: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		VPopulationSystem.process_province(gs, id)
	print("population.process_province all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	var agg := VPopulationSystem.new_agg()
	for id in ids:
		for pop in gs.provinces[id]["pops"]:
			VPopulationSystem._agg_add(gs, agg, pop, "poor", "")
	print("_agg_add all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		for pop in gs.provinces[id]["pops"]:
			VBudgetSystem.credit_income(gs, gs.provinces[id]["owner"], pop, 1.0)
	print("credit_income all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		VProductionSystem.process_province(gs, id)
	print("production.process_province all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		VMobilitySystem.process_province(gs, id)
	print("mobility all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		for pop in gs.provinces[id]["pops"]:
			VPopulationSystem._drift_ideology(gs, pop, "poor", 0.2, 1.0, 0.5, 0.03, 1.0)
	print("drift all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		for pop in gs.provinces[id]["pops"]:
			VPopulationSystem.update_issues(gs, pop, gs.provinces[id]["owner"])
	print("issues all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	quit()
	return true
