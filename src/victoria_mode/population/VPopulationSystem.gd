class_name VPopulationSystem
extends RefCounted
## POPs: generación inicial a partir de datos y agregados (provincia, estado, país).
##
## Un POP es un grupo homogéneo: tipo + cultura + religión en una provincia.
## Campos (base para fases posteriores): type, size, culture, religion, province, money,
## literacy, militancy, consciousness, ideology{}, issues{}, employed, needs{life,everyday,luxury}.

const IDEOLOGY_BY_STRATA := {
	"poor": {"tradicionalista": 0.45, "conservador": 0.35, "liberal": 0.12, "radical": 0.05, "socialista": 0.03},
	"middle": {"tradicionalista": 0.25, "conservador": 0.40, "liberal": 0.28, "radical": 0.07},
	"rich": {"tradicionalista": 0.40, "conservador": 0.45, "liberal": 0.15},
}


static func generate_initial(gs: VGameState) -> void:
	var dist: Dictionary = gs.pop_distribution
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		var total := int(p.get("base_population", p["population"]))
		var owner: String = p["owner"]
		var shares := {}
		if owner == "":
			shares = dist.get("unowned", {}).duplicate()
		else:
			var c: Dictionary = gs.countries[owner]
			if c.get("civilized", true):
				shares = dist.get("civilized", {}).duplicate()
				if int(p["infrastructure"]) > 0 or id == int(c["capital"]):
					for k in dist.get("civilized_developed", {}):
						shares[k] = dist["civilized_developed"][k]
			else:
				shares = dist.get("uncivilized", {}).duplicate()
		var used := 0.0
		for k in shares:
			used += float(shares[k])
		var good: Dictionary = gs.goods.get(p["rgo"], {})
		var worker := "farmers" if good.get("rgo", "farm") == "farm" else "labourers"
		shares[worker] = shares.get(worker, 0.0) + max(0.0, 1.0 - used)
		var pops: Array = []
		var lit_base := 0.02
		if owner != "":
			lit_base = float(gs.countries[owner]["literacy"])
		for t in shares:
			var size := int(round(total * float(shares[t])))
			if size < 10:
				continue
			pops.append(make_pop(gs, t, size, p["culture"], p["religion"], id, lit_base))
		p["pops"] = pops
		recalc_province(gs, id)


static func make_pop(gs: VGameState, type_id: String, size: int, culture: String, religion: String, province_id: int, lit_base: float) -> Dictionary:
	var pt: Dictionary = gs.pop_types.get(type_id, {})
	var strata: String = pt.get("strata", "poor")
	var pop := {
		"id": gs.next_pop_id,
		"type": type_id,
		"size": size,
		"culture": culture,
		"religion": religion,
		"province": province_id,
		"money": float(size) * (0.01 if strata == "poor" else (0.08 if strata == "middle" else 0.6)),
		"literacy": clampf(lit_base * float(pt.get("literacy_mult", 1.0)), 0.0, 1.0),
		"militancy": 1.0,
		"consciousness": 0.5 if strata == "poor" else 1.5,
		"ideology": IDEOLOGY_BY_STRATA.get(strata, {}).duplicate(),
		"issues": {},
		"employed": 1.0,
		"needs": {"life": 1.0, "everyday": 0.4 if strata != "poor" else 0.2, "luxury": 0.3 if strata == "rich" else 0.0},
	}
	gs.next_pop_id += 1
	return pop


static func recalc_province(gs: VGameState, id: int) -> void:
	var p: Dictionary = gs.provinces[id]
	var total := 0
	for pop in p["pops"]:
		total += int(pop["size"])
	p["population"] = total


## Crecimiento mensual según el life rating y la satisfacción de necesidades vitales.
static func monthly_growth(gs: VGameState) -> void:
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		var lr := float(p["life_rating"])
		for pop in p["pops"]:
			var life_needs := float(pop["needs"]["life"])
			var rate := (lr - 15.0) * 0.00004 * life_needs - (1.0 - life_needs) * 0.0005
			pop["size"] = max(1, int(round(float(pop["size"]) * (1.0 + rate))))
		recalc_province(gs, id)


# ------------------------------------------------------------- agregados
## Suma de POPs por tipo en un conjunto de provincias: {type: size}
static func sizes_by(gs: VGameState, province_ids: Array, field: String = "type") -> Dictionary:
	var out := {}
	for id in province_ids:
		for pop in gs.provinces[id]["pops"]:
			var k = pop[field]
			out[k] = out.get(k, 0) + int(pop["size"])
	return out


## Distribución ideológica ponderada por tamaño de POP.
static func ideology_mix(gs: VGameState, province_ids: Array) -> Dictionary:
	var out := {}
	var total := 0.0
	for id in province_ids:
		for pop in gs.provinces[id]["pops"]:
			var s := float(pop["size"])
			total += s
			for k in pop["ideology"]:
				out[k] = out.get(k, 0.0) + float(pop["ideology"][k]) * s
	if total > 0.0:
		for k in out:
			out[k] /= total
	return out


static func weighted_average(gs: VGameState, province_ids: Array, field: String) -> float:
	var total := 0.0
	var acc := 0.0
	for id in province_ids:
		for pop in gs.provinces[id]["pops"]:
			var s := float(pop["size"])
			total += s
			acc += float(pop[field]) * s
	return acc / total if total > 0.0 else 0.0


static func country_pops(gs: VGameState, tag: String) -> Array:
	var out := []
	for id in gs.owned_provinces(tag):
		out.append_array(gs.provinces[id]["pops"])
	return out
