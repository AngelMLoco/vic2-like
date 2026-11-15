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


## Consumo mensual de un ejército a plena fuerza, cacheado como [[bien, cantidad, precio base], …].
## Se invalida cuando cambian sus brigadas (attach_brigade borra «_need»). La fuerza actual se aplica
## como un multiplicador (strength_ratio) sin reconstruir nada.
static func need_full(gs: VGameState, army: Dictionary) -> Array:
	var cached = army.get("_need")
	if cached != null:
		return cached
	var need := {}
	for bid in army["brigades"]:
		var b: Dictionary = gs.brigades.get(bid, {})
		if b.is_empty():
			continue
		var sup: Dictionary = gs.unit_types.get(b["type"], {}).get("supply", {})
		for g in sup:
			need[g] = float(need.get(g, 0.0)) + float(sup[g])
	var out := []
	for g in need:
		out.append([g, float(need[g]), float(gs.goods.get(g, {}).get("base_price", 1.0))])
	army["_need"] = out
	return out


static func strength_ratio(gs: VGameState, army: Dictionary) -> float:
	var n: int = army["brigades"].size()
	return float(VArmySystem.army_strength(gs, army)) / float(n * gs.unit_manpower) if n > 0 else 0.0


## Consumo mensual de bienes de un ejército.
static func army_monthly_need(gs: VGameState, army: Dictionary) -> Dictionary:
	var r := strength_ratio(gs, army)
	var need := {}
	for e in need_full(gs, army):
		need[e[0]] = float(e[1]) * r
	return need


## Consumo mensual total de las fuerzas de una nación (ejércitos + flotas).
static func country_monthly_need(gs: VGameState, tag: String) -> Dictionary:
	var need := {}
	for a in VUnitIndex.country_armies(gs, tag):
		var r := strength_ratio(gs, a)
		for e in need_full(gs, a):
			need[e[0]] = float(need.get(e[0], 0.0)) + float(e[1]) * r
	for f in VUnitIndex.country_fleets(gs, tag):
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


const EMPTY := []

## Organización máxima por tipo de unidad (caché).
static var _max_org := {}


## Tick diario: consumo de la reserva, desgaste, organización y moral de todos los ejércitos.
## Cada ejército se procesa cada 3 días (escalonado; en combate, a diario) con paso triple.
static func daily(gs: VGameState) -> void:
	var d := gs.date.ordinal()
	if _max_org.is_empty() or _max_org.size() != gs.unit_types.size():
		_max_org = {}
		for t in gs.unit_types:
			_max_org[t] = float(gs.unit_types[t].get("organisation", 1.0))
	for aid in gs.armies.keys():
		var a: Dictionary = gs.armies.get(aid, {})
		if a.is_empty():
			continue
		var brigs: Array = a["brigades"]
		if brigs.is_empty():
			continue
		var step := 3.0
		if int(a["battle"]) > 0:
			step = 1.0
		elif (int(aid) + d) % 3 != 0:
			continue
		var tag: String = a["country"]
		var rebel := int(a.get("rebel_faction", 0)) > 0
		var c: Dictionary = gs.countries.get(tag, {})
		var strength := VArmySystem.army_strength(gs, a)
		# 1) consumo de la reserva militar
		var supply := 1.0
		if not rebel and not c.is_empty():
			var stock: Dictionary = c["stockpile"]
			var k := float(strength) / float(brigs.size() * gs.unit_manpower) / 30.0 * step
			var want_value := 0.0
			var got_value := 0.0
			for e in need_full(gs, a):
				var want := float(e[1]) * k
				if want <= 0.0:
					continue
				var g: String = e[0]
				var have := float(stock.get(g, 0.0))
				var take := minf(have, want)
				stock[g] = have - take
				want_value += want * float(e[2])
				got_value += take * float(e[2])
			supply = got_value / want_value if want_value > 0.0 else 1.0
		elif rebel:
			supply = 0.7
		var a_supply := float(a.get("supply", 1.0)) * 0.6 + supply * 0.4
		a["supply"] = a_supply
		if int(a["embarked"]) > 0:
			continue
		var prov := int(a["province"])
		var p: Dictionary = gs.provinces[prov]
		# 2) desgaste (límite cacheado por ejército: provincia, versión de acceso y mes)
		var sl: Array = a.get("_sl", EMPTY)
		var limit := 0.0
		if not sl.is_empty() and int(sl[0]) == prov and int(sl[1]) == gs.access_version and int(sl[2]) == gs.month_index:
			limit = float(sl[3])
		else:
			limit = supply_limit(gs, tag, prov)
			a["_sl"] = [prov, gs.access_version, gs.month_index, limit]
		var here_list: Array = VUnitIndex.armies_in(gs, prov)
		var here := float(brigs.size()) if here_list.size() == 1 else float(VUnitIndex.brigades_in(gs, tag, prov))
		var rate := 0.0
		if here > limit and limit > 0.0:
			rate += (here - limit) / limit * 0.003
		rate += (1.0 - a_supply) * 0.002
		rate += 0.0005 * float(gs.terrain_types.get(p.get("terrain", "plains"), {}).get("attrition", 0))
		if not rebel and VWarSystem.at_war_with(gs, tag, p["controller"]):
			rate += 0.0005
		rate *= step
		if rate > 0.0:
			a["attrition"] = float(a.get("attrition", 0.0)) + rate
		# 3) organización y moral (fuera de combate)
		var in_battle := int(a["battle"]) > 0
		var rec := 0.0
		var morale := float(a.get("morale", 1.0))
		var new_morale := morale
		var org_loss := a_supply < 0.5
		if not in_battle:
			var mil := 0.5
			if not rebel and not c.is_empty():
				mil = float(c["budget"].get("military", 0.5)) * float(c.get("pay_ratio", 1.0))
			var friendly: bool = p["controller"] == tag or (rebel and p["controller"] == VGameState.REBEL_TAG)
			var l_org := 0.0
			var l_mor := 0.0
			if int(a.get("leader", 0)) > 0:
				l_org = VArmySystem.leader_stat(gs, a, "organisation")
				l_mor = VArmySystem.leader_stat(gs, a, "morale")
			rec = 0.02 * step * a_supply * (0.4 + mil) * (1.0 + l_org) * (1.2 if friendly else 0.8)
			if a.get("retreating", false):
				rec *= 0.3
			var mor := morale + step * (0.01 * a_supply * (0.5 + mil) * (1.0 + l_mor) - (0.01 if a_supply < 0.4 else 0.0))
			new_morale = clampf(mor, 0.2, 1.0 + l_mor)
			a["morale"] = new_morale
		# ejército asentado: todas las brigadas en su organización máxima, sin pérdida por suministro y con
		# la moral igual → el bucle de organización no cambiaría nada (resultado exacto)
		var do_org: bool = not in_battle and not (a.get("_org_full", false) and not org_loss and new_morale == morale)
		# una sola pasada por las brigadas: bajas por desgaste y organización
		if rate > 0.0 or do_org:
			var cas_tag := tag if not rebel else ""
			var all_full := true
			for bid in brigs:
				var b: Dictionary = gs.brigades[bid]
				if rate > 0.0:
					var men := int(float(b["strength"]) * rate)
					if men > 0:
						VArmySystem.apply_casualties(gs, b, men, cas_tag)
				if do_org:
					var o := float(b["organisation"])
					if org_loss:
						o -= 0.01 * step
					else:
						o += rec
					var maxo := float(_max_org.get(b["type"], 1.0)) * morale
					o = clampf(o, 0.0, maxo)
					b["organisation"] = o
					if o < maxo:
						all_full = false
			if do_org:
				a["_org_full"] = all_full
		# ejércitos sin hombres desaparecen
		if rate > 0.0 and VArmySystem.army_strength(gs, a) < 100:
			VArmySystem.destroy_army(gs, a)
