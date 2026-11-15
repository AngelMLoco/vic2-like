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
## · Magos: tipo de POP de datos (pop_types.json). Su número tiende a la capacidad que la sociedad sostiene
##   (VMageModel: objetivo, promoción, empleo, degradación y fuga de cerebros).

const BRANCHES := ["technology", "economy", "military", "politics"]
const BRANCH_NAMES := {"technology": "tecnología", "economy": "economía", "military": "ejército", "politics": "política"}
const FLAG := "GLOBAL_MAGIC_ACTIVATED"


static func is_active(gs: VGameState) -> bool:
	return gs.flags.get(FLAG, false)


## Nivel de una rama. country.magic_branches admite dos formas por rama (M5):
##   "military": 2                                   (solo capacidad: número de rutas)
##   "military": {"level": 2, "paths": ["..."]}      (capacidad + escuelas/sendas concretas)
## El nivel NO es la escuela: las escuelas finales se definirán en el lore (magic/magic_schools.json).
static func branch_level(gs: VGameState, tag: String, branch: String) -> int:
	var v = gs.countries.get(tag, {}).get("magic_branches", {}).get(branch, 0)
	if v is Dictionary:
		return int(v.get("level", 0))
	return int(v)


## Sendas/escuelas declaradas en una rama (vacío si la rama solo tiene nivel).
static func branch_paths(gs: VGameState, tag: String, branch: String) -> Array:
	var v = gs.countries.get(tag, {}).get("magic_branches", {}).get(branch, 0)
	if v is Dictionary:
		return v.get("paths", [])
	return []


## Suma de niveles de todas las ramas (amplitud mágica de la nación).
static func branch_total(gs: VGameState, tag: String) -> int:
	var n := 0
	for b in BRANCHES:
		n += branch_level(gs, tag, b)
	return n


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


## Reglas (magic/magic_rules.json) y ramas por nación de los paquetes de contenido (magic_branches.json; en
## el paquete prototype son perfiles PROTOTYPE) sobre el campo existente country.magic_branches.
static func apply_prototype_branches(gs: VGameState, root: String) -> void:
	gs.magic_rules = VJson.load_dict(root + "magic/magic_rules.json").get("rules", {})
	for path in VContentPacks.each(gs, root, "magic_branches.json"):
		var d := VJson.load_dict(path)
		var where: String = VContentPacks.pack_of(path) + "/magic_branches.json"
		for tag in d.get("branches", {}):
			if not gs.countries.has(tag):
				gs.data_errors.append("%s: país desconocido «%s»" % [where, tag])
				continue
			var br: Dictionary = gs.countries[tag].get("magic_branches", {})
			for b in d["branches"][tag]:
				if not (b in BRANCHES):
					gs.data_errors.append("%s: rama desconocida «%s»" % [where, b])
					continue
				var v = d["branches"][tag][b]
				if v is Dictionary:
					if not v.has("level"):
						gs.data_errors.append("%s: %s.%s sin «level»" % [where, tag, b])
					br[b] = {"level": int(v.get("level", 0)), "paths": v.get("paths", [])}
				else:
					br[b] = int(v)
			gs.countries[tag]["magic_branches"] = br
	_validate_paths(gs, root)


## Escuelas/sendas (magic/magic_schools.json): si hay escuelas definidas, las sendas declaradas deben existir y
## pertenecer a su rama. Sin escuelas (estado actual, PROTOTYPE) las sendas son etiquetas libres.
static func _validate_paths(gs: VGameState, root: String) -> void:
	var schools := {}
	for sc in VJson.load_dict(root + "magic/magic_schools.json").get("schools", []):
		schools[String(sc.get("id", ""))] = String(sc.get("branch", ""))
	if schools.is_empty():
		return
	for tag in gs.countries:
		for b in gs.countries[tag].get("magic_branches", {}):
			for path in branch_paths(gs, tag, b):
				if not schools.has(path):
					gs.data_errors.append("magic_branches %s.%s: escuela desconocida «%s»" % [tag, b, path])
				elif schools[path] != b:
					gs.data_errors.append("magic_branches %s.%s: la escuela «%s» pertenece a la rama «%s»" % [tag, b, path, schools[path]])


# ------------------------------------------------------------------ despertar
static func activate(gs: VGameState) -> void:
	if is_active(gs):
		return
	gs.flags[FLAG] = true
	gs.flags["magic_unlocked"] = true
	_seed_deposits(gs)
	VChronicle.record(gs, "", "magic", "La magia regresó al mundo.", true, "", "La magia regresa al mundo")
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
	if not provs.is_empty():
		_deposits(gs, tag, provs)
	VMageModel.country_monthly(gs, tag, provs)


## Yacimientos → cristal al mercado; la renta va a los trabajadores de la provincia.
static func _deposits(gs: VGameState, tag: String, provs: Array) -> void:
	var r: Dictionary = gs.magic_rules
	var ps := gs.pops
	var good: String = r.get("deposit_good", "arcane_crystal")
	var out_per := float(r.get("deposit_output", 2.0)) * (1.0 + gs.mod(tag, "mana_extraction"))
	var price := VMarketSystem.price(gs, good) * VMarketSystem.fill_sell(gs, tag, good)
	var paid := 0.0
	for id in provs:
		var p: Dictionary = gs.provinces[id]
		var dep := float(p["magic"].get("deposit", 0.0))
		if dep <= 0.0 or p["controller"] != tag:
			continue
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
