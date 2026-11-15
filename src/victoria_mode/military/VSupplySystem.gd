class_name VSupplySystem
extends RefCounted
## Suministro, límite de suministro, desgaste (attrition), organización y moral.
##
## El suministro NO son puntos mágicos: cada brigada consume cada mes los bienes de su tipo
## (unit_types.json → supply) de la reserva militar del Estado (country.stockpile), que se llena
## comprando al mercado con VBudgetSystem.buy_stockpile() según el slider «reserva militar».
## Sin reserva: supply < 1 → baja la organización, se refuerza peor, hay desgaste y se combate peor.
##
## Límite de suministro de la provincia: base × terreno × infraestructura × relación con el dueño.
## Por encima del límite hay desgaste: bajas reales que salen de los POPs de soldados.


## Consumo mensual de bienes de un ejército.
static func army_monthly_need(gs: VGameState, army: Dictionary) -> Dictionary:
	var need := {}
	for bid in army["brigades"]:
		var b: Dictionary = gs.brigades.get(bid, {})
		if b.is_empty():
			continue
		var sup: Dictionary = gs.unit_types.get(b["type"], {}).get("supply", {})
		var frac := float(b["strength"]) / float(gs.unit_manpower)
		for g in sup:
			need[g] = float(need.get(g, 0.0)) + float(sup[g]) * frac
	return need


## Consumo mensual total de las fuerzas de una nación (ejércitos + flotas).
static func country_monthly_need(gs: VGameState, tag: String) -> Dictionary:
	var need := {}
	for aid in gs.armies:
		var a: Dictionary = gs.armies[aid]
		if a["country"] != tag or int(a.get("rebel_faction", 0)) > 0:
			continue
		var n := army_monthly_need(gs, a)
		for g in n:
			need[g] = float(need.get(g, 0.0)) + float(n[g])
	for fid in gs.fleets:
		var f: Dictionary = gs.fleets[fid]
		if f["country"] != tag:
			continue
		for s in f["ships"]:
			var sup: Dictionary = gs.ship_types.get(s["type"], {}).get("supply", {})
			for g in sup:
				need[g] = float(need.get(g, 0.0)) + float(sup[g])
	return need


static func supply_limit(gs: VGameState, tag: String, province_id: int) -> float:
	var p := gs.province(province_id)
	if p.is_empty():
		return 0.0
	var terr := float(gs.terrain_types.get(p.get("terrain", "plains"), {}).get("supply_limit", 1.0))
	var base := 8.0 * terr * (1.0 + 0.25 * float(p.get("infrastructure", 0))) * (1.0 + gs.mod(tag, "supply_limit"))
	var owner: String = p["owner"]
	if owner == tag or p["controller"] == tag:
		return base
	if VDiplomacySystem.are_allied(gs, tag, owner):
		return base * 0.8
	if VWarSystem.at_war_with(gs, tag, owner):
		return base * 0.5
	return base * 0.65


## Tick diario: consumo de la reserva, desgaste, organización y moral de todos los ejércitos.
static func daily(gs: VGameState) -> void:
	var per_prov := {}
	for aid in gs.armies:
		var a: Dictionary = gs.armies[aid]
		if int(a["embarked"]) > 0:
			continue
		var k: String = a["country"] + str(int(a["province"]))
		per_prov[k] = int(per_prov.get(k, 0)) + a["brigades"].size()
	var d := gs.date.ordinal()
	for aid in gs.armies.keys():
		var a: Dictionary = gs.armies.get(aid, {})
		if a.is_empty() or a["brigades"].is_empty():
			continue
		# cada ejército se procesa cada 3 días (escalonado; en combate, a diario) con paso triple
		var step := 3.0
		if int(a["battle"]) > 0:
			step = 1.0
		elif (int(aid) + d) % 3 != 0:
			continue
		var tag: String = a["country"]
		var rebel := int(a.get("rebel_faction", 0)) > 0
		# 1) consumo diario de la reserva militar
		var supply := 1.0
		if not rebel and gs.countries.has(tag):
			var stock: Dictionary = gs.countries[tag]["stockpile"]
			var need := army_monthly_need(gs, a)
			var want_value := 0.0
			var got_value := 0.0
			for g in need:
				var want := float(need[g]) / 30.0 * step
				if want <= 0.0:
					continue
				var have := float(stock.get(g, 0.0))
				var take := minf(have, want)
				stock[g] = have - take
				var bp := float(gs.goods.get(g, {}).get("base_price", 1.0))
				want_value += want * bp
				got_value += take * bp
			supply = got_value / want_value if want_value > 0.0 else 1.0
		elif rebel:
			supply = 0.7
		a["supply"] = float(a.get("supply", 1.0)) * 0.6 + supply * 0.4
		if int(a["embarked"]) > 0:
			continue
		var prov := int(a["province"])
		var p := gs.province(prov)
		# 2) desgaste
		var limit := supply_limit(gs, tag, prov)
		var here := float(per_prov.get(tag + str(prov), a["brigades"].size()))
		var rate := 0.0
		if here > limit and limit > 0.0:
			rate += (here - limit) / limit * 0.003
		rate += (1.0 - float(a["supply"])) * 0.002
		if not p.is_empty():
			rate += 0.0005 * float(gs.terrain_types.get(p.get("terrain", "plains"), {}).get("attrition", 0))
			if not rebel and VWarSystem.at_war_with(gs, tag, p["controller"]):
				rate += 0.0005
		rate *= step
		if rate > 0.0:
			a["attrition"] = float(a.get("attrition", 0.0)) + rate
			for bid in a["brigades"]:
				var b: Dictionary = gs.brigades[bid]
				var men := int(float(b["strength"]) * rate)
				if men > 0:
					VArmySystem.apply_casualties(gs, b, men, tag if not rebel else "")
		# 3) organización y moral (fuera de combate)
		if int(a["battle"]) == 0:
			var mil := 0.5
			if not rebel and gs.countries.has(tag):
				mil = float(gs.countries[tag]["budget"].get("military", 0.5)) * float(gs.countries[tag].get("pay_ratio", 1.0))
			var friendly: bool = not p.is_empty() and (p["controller"] == tag or (rebel and p["controller"] == VGameState.REBEL_TAG))
			var rec := 0.02 * step * float(a["supply"]) * (0.4 + mil) * (1.0 + VArmySystem.leader_stat(gs, a, "organisation")) * (1.2 if friendly else 0.8)
			if a.get("retreating", false):
				rec *= 0.3
			for bid in a["brigades"]:
				var b: Dictionary = gs.brigades[bid]
				var maxo := float(gs.unit_types.get(b["type"], {}).get("organisation", 1.0)) * float(a.get("morale", 1.0))
				var o := float(b["organisation"])
				if float(a["supply"]) < 0.5:
					o -= 0.01 * step
				else:
					o += rec
				b["organisation"] = clampf(o, 0.0, maxo)
			var mor := float(a.get("morale", 1.0))
			mor += step * (0.01 * float(a["supply"]) * (0.5 + mil) * (1.0 + VArmySystem.leader_stat(gs, a, "morale")) - (0.01 if float(a["supply"]) < 0.4 else 0.0))
			a["morale"] = clampf(mor, 0.2, 1.0 + VArmySystem.leader_stat(gs, a, "morale"))
		# ejércitos sin hombres desaparecen
		if rate > 0.0 and VArmySystem.army_strength(gs, a) < 100:
			VArmySystem.destroy_army(gs, a)
