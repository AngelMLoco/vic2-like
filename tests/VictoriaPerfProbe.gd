## Sonda de rendimiento del pipeline mensual por provincia (sin interfaz):
##   godot --headless --path . -s tests/VictoriaPerfProbe.gd
extends SceneTree

func _init() -> void:
	pass

func _process(_d: float) -> bool:
	var gs := VDataLoader.new_game()
	var sim := VWorldSimulation.new(gs)
	sim.run_days(40)
	var ids := []
	for id in range(1, gs.first_sea_id):
		if gs.provinces[id]["owner"] != "":
			ids.append(id)
	print("provincias con dueño %d · POPs vivos %d (slots %d)" % [ids.size(), gs.pops.count(), gs.pops.id.size()])
	var t := Time.get_ticks_usec()
	for id in ids:
		VPopulationSystem.process_province(gs, id)
	print("population.process_province all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		VProductionSystem.process_province(gs, id)
	print("production.process_province all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		if (gs.month_index + id) % 2 == 1:
			gs.month_index += 1
			VMobilitySystem.process_province(gs, id)
			gs.month_index -= 1
		else:
			VMobilitySystem.process_province(gs, id)
	print("mobility all (todas las provincias): %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		var pp: Dictionary = gs.provinces[id]
		VMobilitySystem._vacancies(gs, pp, pp["owner"], gs.countries[pp["owner"]])
	print("  mobility._vacancies all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		var pp: Dictionary = gs.provinces[id]
		var cc: Dictionary = gs.countries[pp["owner"]]
		VMobilitySystem._migrate(gs, pp, pp["owner"], cc, {})
	print("  mobility._migrate all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for id in ids:
		VPopulationSystem.recalc_province(gs, id)
	print("  recalc_province all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	var ps := gs.pops
	for s in ps.id.size():
		if ps.id[s] >= 0:
			VPopulationSystem._drift_ideology(gs, s, ps.t_strata[ps.type_id[s]], 0.2, 1.0, 0.5, 0.03, 1.0)
	print("drift all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for s in ps.id.size():
		if ps.id[s] >= 0:
			VPopulationSystem.update_issues(gs, s, gs.provinces[ps.province[s]]["owner"])
	print("issues all: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	quit()
	return true
