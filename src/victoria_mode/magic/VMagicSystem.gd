class_name VMagicSystem
extends RefCounted
## Capa mágica (prototipo; lore NO definitivo). Datos en data/victoria_mode/magic/.
##
## · Despertar: el evento global (data, no código) aplica «activate_magic» → GLOBAL_MAGIC_ACTIVATED y
##   magic_unlocked (compatibilidad con VTechnologySystem), siembra determinista de yacimientos arcanos por
##   terreno y gancho on_action «magic_activated».
## · Ramas: country.magic_branches {technology, economy, military, politics} (0 = sin rama, 1, 2…). Las
##   tecnologías mágicas declaran magic_branch + min_level + requires_flag; VTechnologySystem las filtra.
## · Provincias: p["magic"] = {"potential": 0…1, "deposit": nivel} — capa secundaria: NO sustituye el RGO.
##   El índice de provincias mágicas por nación evita recorrer el mapa.
## · Economía: los yacimientos producen cristal arcano que entra al mercado (VMarketSystem.add_supply) y paga
##   a los trabajadores de la provincia; refinerías y talleres son fábricas normales (factories.json).
## · Magos: tipo de POP de datos (pop_types.json). Aparecen por promoción rara desde POPs alfabetizados en
##   provincias con potencial mágico de naciones con rama (VMobilitySystem._transfer: personas reales).

const BRANCHES := ["technology", "economy", "military", "politics"]
const BRANCH_NAMES := {"technology": "tecnología", "economy": "economía", "military": "ejército", "politics": "política"}
const FLAG := "GLOBAL_MAGIC_ACTIVATED"


static func is_active(gs: VGameState) -> bool:
	return gs.flags.get(FLAG, false)


static func branch_level(gs: VGameState, tag: String, branch: String) -> int:
	return int(gs.countries.get(tag, {}).get("magic_branches", {}).get(branch, 0))


static func max_branch(gs: VGameState, tag: String) -> int:
	var m := 0
	for b in BRANCHES:
		m = maxi(m, branch_level(gs, tag, b))
	return m


## ¿Puede la nación investigar esta tecnología (requisitos mágicos)?
static func tech_allowed(gs: VGameState, tag: String, t: Dictionary) -> bool:
	var rf: String = t.get("requires_flag", "")
	if rf != "" and not gs.flags.get(rf, false):
		return false
	var b: String = t.get("magic_branch", "")
	if b != "" and branch_level(gs, tag, b) < int(t.get("min_level", 1)):
		return false
	return true


## Ramas de prototipo (data/victoria_mode/magic/prototype_branches.json) sobre country.magic_branches.
static func apply_prototype_branches(gs: VGameState, root: String) -> void:
	var d := VJson.load_dict(root + "magic/prototype_branches.json")
	for tag in d.get("branches", {}):
		if not gs.countries.has(tag):
			gs.data_errors.append("prototype_branches.json: país desconocido «%s»" % tag)
			continue
		var br: Dictionary = gs.countries[tag].get("magic_branches", {})
		for b in d["branches"][tag]:
			if not (b in BRANCHES):
				gs.data_errors.append("prototype_branches.json: rama desconocida «%s»" % b)
				continue
			br[b] = int(d["branches"][tag][b])
		gs.countries[tag]["magic_branches"] = br
	gs.magic_rules = d.get("rules", {})


# ------------------------------------------------------------------ despertar
static func activate(gs: VGameState) -> void:
	if is_active(gs):
		return
	gs.flags[FLAG] = true
	gs.flags["magic_unlocked"] = true
	_seed_deposits(gs)
	VScopedState.chronicle(gs, "world", "magic_awakening", "", "La magia regresa al mundo", "", true)
	VEventSystem.notify(gs, "magic_activated", {})


## Siembra determinista: probabilidad por terreno; potencial mágico y nivel del yacimiento por hash de provincia.
static func _seed_deposits(gs: VGameState) -> void:
	var r: Dictionary = gs.magic_rules
	var tw: Dictionary = r.get("terrain_weight", {})
	var base := float(r.get("deposit_chance", 0.02))
	for id in range(1, gs.first_sea_id):
		var p = gs.provinces[id]
		if p == null:
			continue
		var w := float(tw.get(p.get("terrain", "plains"), 1.0))
		var h := VEventSystem.roll01("magic|%d" % id)
		var pot := VEventSystem.roll01("pot|%d" % id) * w
		if pot > 0.35:
			p["magic"] = {"potential": snappedf(minf(1.0, pot), 0.01), "deposit": 0.0}
		if h < base * w:
			add_deposit(gs, id, 0.5 + VEventSystem.roll01("dep|%d" % id))
	gs.unit_index.erase("magic_by_country")


static func add_deposit(gs: VGameState, id: int, level: float) -> void:
	var p := gs.province(id)
	if p.is_empty():
		return
	var m: Dictionary = p.get("magic", {"potential": 0.5, "deposit": 0.0})
	m["deposit"] = float(m.get("deposit", 0.0)) + level
	m["potential"] = maxf(float(m.get("potential", 0.0)), 0.5)
	p["magic"] = m
	VScopedState.set_province_flag(gs, id, "ARCANE_DEPOSIT")
	gs.unit_index.erase("magic_by_country")


## Descubrimiento dirigido (decisión «estudio de líneas ley»): la provincia con más potencial sin yacimiento.
static func discover_in_country(gs: VGameState, tag: String, level: float) -> int:
	var best := -1
	var bv := -1.0
	for id in gs.countries.get(tag, {}).get("provinces", []):
		var p: Dictionary = gs.provinces[id]
		var m: Dictionary = p.get("magic", {})
		var v := float(m.get("potential", 0.0)) - (1.0 if float(m.get("deposit", 0.0)) > 0.0 else 0.0)
		v += VEventSystem.roll01("disc|%d" % int(id)) * 0.1
		if v > bv:
			bv = v
			best = int(id)
	if best > 0:
		add_deposit(gs, best, level)
		gs.log_event(tag, "Se descubre un yacimiento arcano en %s" % gs.provinces[best]["name"])
	return best


## Provincias con capa mágica de una nación (índice derivado, se invalida al sembrar o cambiar propietarios).
static func country_magic_provinces(gs: VGameState, tag: String) -> Array:
	var ix: Dictionary = gs.unit_index.get("magic_by_country", {})
	if ix.is_empty() or int(ix.get("_ver", -1)) != gs.access_version:
		ix = {"_ver": gs.access_version}
		for id in range(1, gs.first_sea_id):
			var p = gs.provinces[id]
			if p != null and p.has("magic") and p["owner"] != "":
				if not ix.has(p["owner"]):
					ix[p["owner"]] = []
				ix[p["owner"]].append(id)
				if float(p["magic"].get("deposit", 0.0)) > 0.0:
					var dk: String = p["owner"] + "#dep"
					if not ix.has(dk):
						ix[dk] = []
					ix[dk].append(id)
		if gs.unit_index.is_empty():
			VUnitIndex.rebuild(gs)
		gs.unit_index["magic_by_country"] = ix
	return ix.get(tag, [])


## Provincias con yacimiento arcano de una nación (candidatas de los eventos de provincia «magic»).
static func country_deposit_provinces(gs: VGameState, tag: String) -> Array:
	country_magic_provinces(gs, tag)
	return gs.unit_index["magic_by_country"].get(tag + "#dep", [])


# ------------------------------------------------------------------ mensual (cubo de la nación)
static func country_monthly(gs: VGameState, tag: String) -> void:
	if not is_active(gs):
		return
	var provs := country_magic_provinces(gs, tag)
	if provs.is_empty():
		return
	var r: Dictionary = gs.magic_rules
	var c: Dictionary = gs.countries[tag]
	var ps := gs.pops
	var good: String = r.get("deposit_good", "arcane_crystal")
	var out_per := float(r.get("deposit_output", 2.0)) * (1.0 + gs.mod(tag, "mana_extraction"))
	var price := VMarketSystem.price(gs, good) * VMarketSystem.fill_sell(gs, tag, good)
	var mage_t := int(ps.type_index.get(String(r.get("mage_type", "magi")), -1))
	var mage_rate := float(r.get("mage_rate", 0.0015)) * (1.0 + gs.mod(tag, "mage_emergence"))
	var min_lit := float(r.get("mage_min_literacy", 0.25))
	var mage_branch := max_branch(gs, tag) >= int(r.get("mage_min_branch", 1))
	var sources := {}
	for st in r.get("mage_sources", ["clergy", "clerks"]):
		sources[int(ps.type_index.get(st, -9))] = true
	var paid := 0.0
	for id in provs:
		var p: Dictionary = gs.provinces[id]
		var m: Dictionary = p["magic"]
		# 1) extracción del yacimiento → mercado; la renta va a los trabajadores de la provincia
		var dep := float(m.get("deposit", 0.0))
		if dep > 0.0 and p["controller"] == tag:
			var q := dep * out_per
			VMarketSystem.add_supply(gs, tag, good, q)
			var revenue := q * price
			var workers := []
			var wsize := 0
			for s in p["pop_slots"]:
				var t: int = ps.type_id[s]
				if t == ps.T_LABOURERS or t == ps.T_FARMERS:
					workers.append(s)
					wsize += ps.size[s]
			for s in workers:
				var share := revenue * float(ps.size[s]) / float(wsize)
				VBudgetSystem.credit_income(gs, tag, s, share)
				paid += share
		# 2) aparición de magos (rara): POPs alfabetizados de tipos fuente en provincias con potencial
		if mage_branch and mage_t >= 0 and float(m.get("potential", 0.0)) > 0.0:
			for s in p["pop_slots"].duplicate():
				if sources.has(ps.type_id[s]) and ps.literacy[s] >= min_lit and ps.size[s] > 400:
					var amount := int(float(ps.size[s]) * mage_rate * float(m["potential"]))
					if amount >= 10:
						VMobilitySystem._transfer(gs, s, p, ps.type_names[mage_t], amount)
						var cs: Dictionary = c.get("acc_mobility", {})
						cs["magi"] = int(cs.get("magi", 0)) + amount
	if paid > 0.0:
		VMoney.created(gs, paid, "magic_sales")


## Conversión dirigida por eventos/decisiones: {"from": tipo(s), "to": tipo, "share": fracción, "max": personas}.
static func convert_pops(gs: VGameState, tag: String, prov: int, v: Dictionary) -> void:
	var ps := gs.pops
	var froms := {}
	for f in (v["from"] if v["from"] is Array else [v["from"]]):
		froms[int(ps.type_index.get(f, -9))] = true
	var share := float(v.get("share", 0.01))
	var left := int(v.get("max", 5000))
	var provs: Array = [prov] if prov > 0 else gs.countries.get(tag, {}).get("provinces", [])
	for id in provs:
		var p: Dictionary = gs.provinces[id]
		for s in p["pop_slots"].duplicate():
			if left <= 0:
				return
			if froms.has(ps.type_id[s]):
				var amount := mini(left, int(float(ps.size[s]) * share))
				if amount >= 10:
					VMobilitySystem._transfer(gs, s, p, String(v["to"]), amount)
					left -= amount


## Activación directa (consola de depuración / pruebas): equivale al efecto «activate_magic».
static func debug_activate(gs: VGameState) -> void:
	activate(gs)
