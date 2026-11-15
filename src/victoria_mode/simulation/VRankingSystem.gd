class_name VRankingSystem
extends RefCounted
## Ranking nacional estilo Victoria II:  Prestigio + Industria + Militar = Puntuación total.
## Las 8 primeras naciones civilizadas son Grandes Potencias; las 8 siguientes, Potencias Secundarias.
## Las no civilizadas no pueden ser Gran Potencia.

const GREAT_POWERS := 8
const SECONDARY_POWERS := 8

const STATUS_NAMES := {
	"great_power": "Gran Potencia",
	"secondary_power": "Potencia Secundaria",
	"civilized": "Nación civilizada",
	"uncivilized": "Nación no civilizada",
}


static func industry_score(gs: VGameState, tag: String) -> float:
	var score := 0.0
	for si in gs.country_state_instances(tag):
		for f in si["factories"]:
			score += float(f["level"]) * 4.0 * (0.5 + 0.5 * float(f.get("employment", 1.0)))
	return score


static func military_score(gs: VGameState, tag: String) -> float:
	var mil: Dictionary = gs.countries[tag]["military"]
	var soldiers := 0
	for id in gs.owned_provinces(tag):
		for pop in gs.provinces[id]["pops"]:
			if pop["type"] == "soldiers":
				soldiers += int(pop["size"])
	return float(mil.get("brigades", 0)) * 2.2 + float(mil.get("ships", 0)) * 0.9 + sqrt(float(soldiers)) * 0.05


static func recalculate(gs: VGameState) -> void:
	var rows := []
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			c["rank"] = 0
			c["total_score"] = 0.0
			continue
		c["industry_score"] = industry_score(gs, tag)
		c["military_score"] = military_score(gs, tag)
		c["total_score"] = float(c["prestige"]) + float(c["industry_score"]) + float(c["military_score"])
		rows.append(tag)
	# civilizadas primero (Victoria: una no civilizada nunca supera a una civilizada en el ranking de potencias)
	rows.sort_custom(func(a, b):
		var ca: Dictionary = gs.countries[a]
		var cb: Dictionary = gs.countries[b]
		var civ_a: bool = ca.get("civilized", true)
		var civ_b: bool = cb.get("civilized", true)
		if civ_a != civ_b:
			return civ_a
		return float(ca["total_score"]) > float(cb["total_score"]))
	for i in rows.size():
		var c: Dictionary = gs.countries[rows[i]]
		c["rank"] = i + 1
		if not c.get("civilized", true):
			c["status"] = "uncivilized"
		elif i < GREAT_POWERS:
			c["status"] = "great_power"
		elif i < GREAT_POWERS + SECONDARY_POWERS:
			c["status"] = "secondary_power"
		else:
			c["status"] = "civilized"


static func ranked(gs: VGameState) -> Array:
	var rows := []
	for tag in gs.country_order:
		if int(gs.countries[tag]["rank"]) > 0:
			rows.append(tag)
	rows.sort_custom(func(a, b): return int(gs.countries[a]["rank"]) < int(gs.countries[b]["rank"]))
	return rows


static func status_name(status: String) -> String:
	return STATUS_NAMES.get(status, status)
