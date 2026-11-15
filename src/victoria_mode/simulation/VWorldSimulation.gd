class_name VWorldSimulation
extends RefCounted
## Orquestador de la simulación por ticks (diario y mensual).
## Cada sistema vive en su propio módulo; aquí solo se decide el orden de ejecución.
##
## Fase actual (milestone 1): presupuesto básico (impuestos por estrato y gastos),
## puntos de investigación, crecimiento mensual de POPs y ranking mensual.
## Las fases siguientes sustituirán el presupuesto básico por mercado/producción completos.

const TAX_PER_CAPITA := {"poor": 0.000006, "middle": 0.00006, "rich": 0.0004}

var gs: VGameState


func _init(state: VGameState) -> void:
	gs = state
	refresh_caches()


func on_day() -> void:
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		_daily_budget(c)


func on_month() -> void:
	VPopulationSystem.monthly_growth(gs)
	refresh_caches()
	VRankingSystem.recalculate(gs)


## Agregados que no cambian cada día (por estrato, clero, población total).
func refresh_caches() -> void:
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		var strata := {"poor": 0, "middle": 0, "rich": 0}
		var clergy_lit := 0.0
		var total := 0
		for id in c["provinces"]:
			for pop in gs.provinces[id]["pops"]:
				var s := int(pop["size"])
				total += s
				var st: String = gs.pop_types.get(pop["type"], {}).get("strata", "poor")
				strata[st] += s
				if pop["type"] == "clergy":
					clergy_lit += float(s) * float(pop["literacy"])
		c["strata_pop"] = strata
		c["population"] = total
		c["clergy_literacy"] = clergy_lit


func _daily_budget(c: Dictionary) -> void:
	var b: Dictionary = c["budget"]
	var strata: Dictionary = c.get("strata_pop", {"poor": 0, "middle": 0, "rich": 0})
	var income := 0.0
	income += float(strata["poor"]) * TAX_PER_CAPITA["poor"] * float(b["tax_poor"])
	income += float(strata["middle"]) * TAX_PER_CAPITA["middle"] * float(b["tax_middle"])
	income += float(strata["rich"]) * TAX_PER_CAPITA["rich"] * float(b["tax_rich"])
	var pop := float(c.get("population", 0))
	var mil: Dictionary = c["military"]
	var expense := 0.0
	expense += (float(mil["brigades"]) * 1.4 + float(mil["ships"]) * 0.9) * float(b["military"])
	expense += pop * 0.0000012 * float(b["education"])
	expense += pop * 0.0000010 * float(b["administration"])
	expense += float(strata["poor"]) * 0.0000015 * float(b["social"])
	c["income_daily"] = income
	c["expense_daily"] = expense
	c["treasury"] = float(c["treasury"]) + income - expense
	var rp := float(c.get("clergy_literacy", 0.0)) * 0.00002 * (0.5 + float(b["education"]))
	c["research_points_daily"] = rp
	c["research_points"] = float(c.get("research_points", 0.0)) + rp
