class_name VSaveSystem
extends RefCounted
## Guardado de la Segunda versión (separado de los saves del prototipo: user://chronicles_save.json).
##
## Formato: JSON con cabecera { save_version, mode, name, country_tag, ... } y bloques de estado.
## Al cargar se reconstruye el mundo desde los datos y se superpone el estado guardado.
## Si save_version no coincide y no hay migración, la carga se rechaza limpiamente.

const SAVE_DIR := "user://victoria_mode/saves/"
## v3 (milestone 3): diplomacia, influencia, ejércitos, flotas, guerras, CB y rebeldes.
## v4 (M3.2): POPs en formato columnar (VPopStore.to_save); las provincias ya no guardan POPs.
const SAVE_VERSION := 4
const MODE_ID := "victoria_mode"

## v2 (milestone 2): economía, política y tecnología. Las partidas v1 se rechazan con un mensaje.
const COUNTRY_FIELDS := ["prestige", "treasury", "literacy", "infamy", "war_exhaustion", "relations", "allies",
	"wars", "sphere_leader", "influence", "military", "budget", "capital", "technologies",
	"reforms", "government", "ruling_party", "civilized", "magic_branches",
	"acc", "budget_last", "debt", "debt_foreign", "bank", "stockpile", "pay_ratio", "admin_efficiency", "tax_efficiency",
	"monthly_income", "monthly_expense", "monthly_balance", "income_daily", "expense_daily", "projects",
	"artisan_profit", "artisan_best", "inventions", "research", "research_progress", "research_points",
	"research_points_monthly", "research_points_daily", "parties", "ruling_party_index", "next_election_month",
	"last_election", "upper_house", "movements", "reform_cooldown", "voter_ideology", "acc_mobility",
	"acc_mobility_last", "_tier_demand",
	"diplo_points", "military_access", "guarantees", "truces", "overlord", "subjects", "wars", "influence",
	"gp_grace", "leadership", "casualties", "_casualties_seen", "disarmed_until", "reparations", "ship_queue",
	"blockade_ratio", "status", "rank"]
const PROVINCE_FIELDS := ["owner", "controller", "cores", "occupation", "fort", "naval_base", "infrastructure",
	"life_rating", "rgo", "culture", "religion", "rgo_data", "avg_life", "unemployment", "rgo_free",
	"occupation_by", "blockaded_by", "rebel_faction"]


static func list_saves() -> Array:
	var out := []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path := SAVE_DIR + f
		var header := _read_header(path)
		if header.is_empty():
			continue
		header["path"] = path
		out.append(header)
	out.sort_custom(func(a, b): return str(a.get("saved_at", "")) > str(b.get("saved_at", "")))
	return out


static func _read_header(path: String) -> Dictionary:
	var data = VJson.load_any(path)
	if not (data is Dictionary) or data.get("mode", "") != MODE_ID:
		return {}
	var h: Dictionary = data.get("header", {})
	h["save_version"] = data.get("save_version", 0)
	return h


static func save_game(gs: VGameState, save_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var safe := save_name.strip_edges().replace("/", "_").replace("\\", "_").replace(":", "_")
	if safe == "":
		safe = "partida"
	var path := SAVE_DIR + safe + ".json"
	var countries := {}
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		var d := {}
		for k in COUNTRY_FIELDS:
			if c.has(k):
				d[k] = c[k]
		countries[tag] = d
	var provinces := {}
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		var d := {}
		for k in PROVINCE_FIELDS:
			if p.has(k):
				d[k] = p[k]
		provinces[str(id)] = d
	var factories := {}
	for key in gs.state_instances:
		var f: Array = gs.state_instances[key]["factories"]
		if not f.is_empty():
			factories[key] = f
	var market := {}
	for k in gs.market:
		if not str(k).begins_with("_"):
			market[k] = gs.market[k]
	var data := {
		"save_version": SAVE_VERSION,
		"mode": MODE_ID,
		"header": {
			"name": safe,
			"country_tag": gs.player_tag,
			"country_name": gs.country_name(gs.player_tag),
			"date_text": gs.date.text(),
			"saved_at": Time.get_datetime_string_from_system(),
		},
		"date": gs.date.to_dict(),
		"player_tag": gs.player_tag,
		"flags": gs.flags,
		"pops": gs.pops.to_save(),
		"countries": countries,
		"provinces": provinces,
		"state_factories": factories,
		"market": market,
		"month_index": gs.month_index,
		"log": gs.log_entries,
		"military": {
			"armies": _public(gs.armies), "brigades": _public(gs.brigades), "leaders": gs.leaders, "fleets": _public(gs.fleets),
			"wars": _public(gs.wars), "battles": gs.battles, "casus_belli": gs.casus_belli, "justifications": gs.justifications,
			"rebel_factions": gs.rebel_factions, "next_ids": gs.next_ids,
		},
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("VSaveSystem: no se pudo escribir %s" % path)
		return ""
	file.store_string(JSON.stringify(data))
	file.close()
	return path


## Devuelve un VGameState con la partida aplicada, o null con mensaje en error_out[0].
## Copia sin las claves «_…» (cachés derivadas) de un diccionario id → entidad (hasta 2 niveles).
static func _public(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var e = d[k]
		if e is Dictionary:
			var c := {}
			for kk in e:
				if str(kk).begins_with("_"):
					continue
				var v = e[kk]
				if v is Array and not v.is_empty() and v[0] is Dictionary:
					var arr := []
					for item in v:
						var ci := {}
						for k3 in item:
							if not str(k3).begins_with("_"):
								ci[k3] = item[k3]
						arr.append(ci)
					v = arr
				c[kk] = v
			out[k] = c
		else:
			out[k] = e
	return out


static func load_game(path: String, error_out: Array = []) -> VGameState:
	var data = VJson.load_any(path)
	if not (data is Dictionary) or data.get("mode", "") != MODE_ID:
		error_out.append("El archivo no es una partida de la Segunda versión.")
		return null
	data = _migrate(data)
	if int(data.get("save_version", 0)) != SAVE_VERSION:
		error_out.append("Versión de guardado %d incompatible (se esperaba %d)." % [int(data.get("save_version", 0)), SAVE_VERSION])
		return null
	var gs := VDataLoader.new_game()
	gs.date = VDate.from_dict(data["date"])
	gs.player_tag = data.get("player_tag", "")
	gs.flags = data.get("flags", {})
	gs.month_index = int(data.get("month_index", 0))
	gs.log_entries = data.get("log", [])
	var mil: Dictionary = data.get("military", {})
	gs.armies = _int_keys(mil.get("armies", {}))
	gs.unit_index = {}  # derivado: se reconstruye al primer uso
	gs.path_cache = {}
	gs.war_cache = {}
	gs.access_version += 1
	gs.brigades = _int_keys(mil.get("brigades", {}))
	gs.leaders = _int_keys(mil.get("leaders", {}))
	gs.fleets = _int_keys(mil.get("fleets", {}))
	gs.wars = _int_keys(mil.get("wars", {}))
	gs.battles = _int_keys(mil.get("battles", {}))
	gs.rebel_factions = _int_keys(mil.get("rebel_factions", {}))
	gs.casus_belli = mil.get("casus_belli", [])
	gs.justifications = mil.get("justifications", [])
	gs.next_ids = mil.get("next_ids", {})
	_fix_military_numbers(gs)
	var market: Dictionary = data.get("market", {})
	for k in market:
		gs.market[k] = market[k]
	var countries: Dictionary = data.get("countries", {})
	for tag in countries:
		if not gs.countries.has(tag):
			continue
		for k in countries[tag]:
			gs.countries[tag][k] = countries[tag][k]
		gs.countries[tag]["capital"] = int(gs.countries[tag]["capital"])
	var provinces: Dictionary = data.get("provinces", {})
	for key in provinces:
		var p := gs.province(int(key))
		if p.is_empty():
			continue
		for k in provinces[key]:
			p[k] = provinces[key][k]
		_fix_pop_numbers(p)
	gs.pops.from_save(gs, data.get("pops", {}))
	gs.rebuild_territory()
	for key in gs.state_instances:
		gs.state_instances[key]["factories"] = []
	var sf: Dictionary = data.get("state_factories", {})
	for key in sf:
		if gs.state_instances.has(key):
			for f in sf[key]:
				f["id"] = int(f["id"])
				f["level"] = int(f["level"])
				f["loss_months"] = int(f.get("loss_months", 0))
			gs.state_instances[key]["factories"] = sf[key]
	for id in range(1, gs.first_sea_id):
		VPopulationSystem.recalc_province(gs, id)
	for tag in gs.countries:
		var c: Dictionary = gs.countries[tag]
		c["ruling_party_index"] = int(c.get("ruling_party_index", 0))
		c["next_election_month"] = int(c.get("next_election_month", -1))
		c["reform_cooldown"] = int(c.get("reform_cooldown", 0))
		for r in c.get("reforms", {}):
			c["reforms"][r] = int(c["reforms"][r])
		VModifiers.recompute(gs, tag)
	VProductionSystem.derive_rates(gs)
	for tag in gs.countries:
		var c2: Dictionary = gs.countries[tag]
		var w_ids := []
		for w in c2.get("wars", []):
			w_ids.append(int(w))
		c2["wars"] = w_ids
		for k in c2.get("truces", {}).keys():
			c2["truces"][k] = int(c2["truces"][k])
	VArmySystem.update_counts(gs)
	VNavySystem.update_counts(gs)
	VPopulationSystem.refresh_country_caches(gs)
	VRankingSystem.recalculate(gs)
	return gs


## JSON convierte enteros en float: restaurar campos enteros de POPs.
static func _fix_pop_numbers(p: Dictionary) -> void:
	p["rebel_faction"] = int(p.get("rebel_faction", 0))
	p["fort"] = int(p.get("fort", 0))
	p["naval_base"] = int(p.get("naval_base", 0))
	p["infrastructure"] = int(p.get("infrastructure", 0))
	p["life_rating"] = int(p.get("life_rating", 0))


## Punto de extensión para migraciones entre versiones de formato.
static func _migrate(data: Dictionary) -> Dictionary:
	# Ejemplo futuro: if data.save_version == 1: ...convertir... data.save_version = 2
	return data


## JSON convierte las claves enteras en texto: restaurarlas.
static func _int_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = d[k]
	return out


static func _ints(arr: Array) -> Array:
	var out := []
	for v in arr:
		out.append(int(v))
	return out


## Restaura tipos enteros en las entidades militares (JSON los devuelve como float).
static func _fix_military_numbers(gs: VGameState) -> void:
	for id in gs.armies:
		var a: Dictionary = gs.armies[id]
		for k in ["id", "province", "leader", "battle", "embarked", "rebel_faction", "ai_target", "dig_in"]:
			a[k] = int(a.get(k, 0))
		a["brigades"] = _ints(a.get("brigades", []))
		a["path"] = _ints(a.get("path", []))
	for id in gs.brigades:
		var b: Dictionary = gs.brigades[id]
		for k in ["id", "strength", "source_pop_id", "source_province_id", "army"]:
			b[k] = int(b.get(k, 0))
	for id in gs.leaders:
		var l: Dictionary = gs.leaders[id]
		for k in ["id", "army", "fleet"]:
			l[k] = int(l.get(k, 0))
	for id in gs.fleets:
		var f: Dictionary = gs.fleets[id]
		for k in ["id", "location", "admiral", "battle"]:
			f[k] = int(f.get(k, 0))
		f["path"] = _ints(f.get("path", []))
		f["transported_armies"] = _ints(f.get("transported_armies", []))
		for sh in f.get("ships", []):
			sh["id"] = int(sh["id"])
	for id in gs.wars:
		var w: Dictionary = gs.wars[id]
		for k in ["id", "start_month", "start_ordinal"]:
			w[k] = int(w.get(k, 0))
		for g in w.get("war_goals", []):
			g["id"] = int(g.get("id", 0))
			g["state_id"] = int(g.get("state_id", 0))
	for id in gs.battles:
		var bt: Dictionary = gs.battles[id]
		for k in ["id", "province", "war", "day", "att_rebel", "def_rebel"]:
			bt[k] = int(bt.get(k, 0))
		bt["attackers"] = _ints(bt.get("attackers", []))
		bt["defenders"] = _ints(bt.get("defenders", []))
	for cb in gs.casus_belli:
		for k in ["id", "state_id", "expires"]:
			cb[k] = int(cb.get(k, 0))
	for j in gs.justifications:
		for k in ["id", "state_id", "months"]:
			j[k] = int(j.get(k, 0))
	for id in gs.rebel_factions:
		var f2: Dictionary = gs.rebel_factions[id]
		f2["id"] = int(f2["id"])
		f2["supporting_pops"] = _ints(f2.get("supporting_pops", []))
		f2["armies"] = _ints(f2.get("armies", []))
		f2["controlled_provinces"] = _ints(f2.get("controlled_provinces", []))
	for k in gs.next_ids.keys():
		gs.next_ids[k] = int(gs.next_ids[k])
	for id in range(1, gs.first_sea_id):
		var p: Dictionary = gs.provinces[id]
		p["rebel_faction"] = int(p.get("rebel_faction", 0))
