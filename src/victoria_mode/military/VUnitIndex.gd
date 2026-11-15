class_name VUnitIndex
extends RefCounted
## Índices persistentes de unidades (derivados: NO se guardan; se reconstruyen al cargar o al primer uso).
##
##   armies_by_province : provincia → [ejércitos desembarcados en ella]
##   armies_by_country  : nación → [ejércitos regulares (no rebeldes), embarcados o no]
##   fleets_by_country  : nación → [flotas]
##   fleets_by_location : provincia/zona → [flotas]
##   sieging            : ejércitos que pueden asediar (en provincia de otro controlador, o rebeldes)
##   damaged            : ejércitos con alguna brigada por debajo de su fuerza (refuerzo)
##
## Se actualizan de forma incremental en cada evento (crear, destruir, mover, embarcar, desembarcar,
## alzarse en rebeldía). Ningún sistema debe recorrer gs.armies / gs.fleets para buscar por provincia
## o por nación: usa armies_in(), country_armies(), fleets_at(), country_fleets().
##
## Las listas devueltas por armies_in()/fleets_at() son las del índice: no modificarlas y copiarlas
## (duplicate) si durante el recorrido se van a crear, mover o destruir unidades.
##
## Versión de acceso (gs.access_version): se incrementa cuando cambia quién puede entrar dónde
## (guerra declarada, participante añadido o retirado, paz, alianza, acceso militar, cambio de
## propiedad). Las cachés de rutas y de relaciones de guerra la comparan para invalidarse.

const EMPTY := []


static func _idx(gs: VGameState) -> Dictionary:
	if gs.unit_index.is_empty():
		rebuild(gs)
	return gs.unit_index


static func rebuild(gs: VGameState) -> void:
	var ix := {"ap": {}, "ac": {}, "fc": {}, "fl": {}, "sg": {}, "dmg": {}}
	gs.unit_index = ix
	for aid in gs.armies:
		var a: Dictionary = gs.armies[aid]
		_add_army(ix, a)
		_siege_check(gs, ix, a)
		for bid in a["brigades"]:
			if int(gs.brigades.get(bid, {}).get("strength", gs.unit_manpower)) < gs.unit_manpower:
				ix["dmg"][int(aid)] = true
				break
	for fid in gs.fleets:
		_add_fleet(ix, gs.fleets[fid])


static func _push(d: Dictionary, k, v) -> void:
	if not d.has(k):
		d[k] = [v]
	else:
		d[k].append(v)


## Quita por identidad (is_same): == compara diccionarios por valor y sería lento.
static func _pull(d: Dictionary, k, v) -> void:
	if not d.has(k):
		return
	var arr: Array = d[k]
	for i in arr.size():
		if is_same(arr[i], v):
			arr.remove_at(i)
			break
	if arr.is_empty():
		d.erase(k)


static func _has_same(arr: Array, v) -> bool:
	for x in arr:
		if is_same(x, v):
			return true
	return false


static func _add_army(ix: Dictionary, a: Dictionary) -> void:
	if int(a["embarked"]) == 0:
		_push(ix["ap"], int(a["province"]), a)
	if int(a.get("rebel_faction", 0)) == 0:
		_push(ix["ac"], a["country"], a)


static func _add_fleet(ix: Dictionary, f: Dictionary) -> void:
	_push(ix["fc"], f["country"], f)
	_push(ix["fl"], int(f["location"]), f)


# ----------------------------------------------------------------- eventos
static func army_created(gs: VGameState, a: Dictionary) -> void:
	if gs.unit_index.is_empty():
		rebuild(gs)  # la reconstrucción ya incluye la unidad recién registrada
		return
	_add_army(gs.unit_index, a)
	_siege_check(gs, gs.unit_index, a)


static func army_destroyed(gs: VGameState, a: Dictionary) -> void:
	var ix := _idx(gs)
	_pull(ix["ap"], int(a["province"]), a)
	_pull(ix["ac"], a["country"], a)
	ix["sg"].erase(int(a["id"]))
	ix["dmg"].erase(int(a["id"]))


## ¿Puede asediar donde está? (provincia con otro controlador, o rebelde). Se reevalúa al llegar.
static func _siege_check(gs: VGameState, ix: Dictionary, a: Dictionary) -> void:
	var p := gs.province(int(a["province"]))
	if int(a["embarked"]) == 0 and not p.is_empty() and (int(a.get("rebel_faction", 0)) > 0 or p["controller"] != a["country"]):
		ix["sg"][int(a["id"])] = true
	else:
		ix["sg"].erase(int(a["id"]))


static func sieging_armies(gs: VGameState) -> Dictionary:
	return _idx(gs)["sg"]


static func mark_damaged(gs: VGameState, army_id: int) -> void:
	if army_id > 0:
		_idx(gs)["dmg"][army_id] = true


static func damaged_armies(gs: VGameState) -> Dictionary:
	return _idx(gs)["dmg"]


## Mueve un ejército (también para teletransportes de fin de guerra o pruebas).
static func move_army(gs: VGameState, a: Dictionary, to_id: int) -> void:
	var from := int(a["province"])
	if from == to_id:
		return
	a["province"] = to_id
	if int(a["embarked"]) == 0:
		var ix := _idx(gs)
		_pull(ix["ap"], from, a)
		_push(ix["ap"], to_id, a)
		_siege_check(gs, ix, a)


static func army_embarked(gs: VGameState, a: Dictionary, fleet_id: int) -> void:
	if int(a["embarked"]) == 0:
		_pull(_idx(gs)["ap"], int(a["province"]), a)
	a["embarked"] = fleet_id
	_idx(gs)["sg"].erase(int(a["id"]))


static func army_unloaded(gs: VGameState, a: Dictionary, province_id: int) -> void:
	if int(a["embarked"]) == 0:
		move_army(gs, a, province_id)
		return
	a["embarked"] = 0
	a["province"] = province_id
	_push(_idx(gs)["ap"], province_id, a)
	_siege_check(gs, gs.unit_index, a)


## Un ejército pasa a una facción rebelde (sale del índice por nación).
static func army_set_rebel(gs: VGameState, a: Dictionary, faction_id: int) -> void:
	if int(a.get("rebel_faction", 0)) == 0 and faction_id > 0:
		_pull(_idx(gs)["ac"], a["country"], a)
	a["rebel_faction"] = faction_id
	_siege_check(gs, gs.unit_index, a)


static func fleet_created(gs: VGameState, f: Dictionary) -> void:
	if gs.unit_index.is_empty():
		rebuild(gs)  # la reconstrucción ya incluye la unidad recién registrada
		return
	_add_fleet(gs.unit_index, f)


static func fleet_destroyed(gs: VGameState, f: Dictionary) -> void:
	var ix := _idx(gs)
	_pull(ix["fc"], f["country"], f)
	_pull(ix["fl"], int(f["location"]), f)


static func move_fleet(gs: VGameState, f: Dictionary, to_id: int) -> void:
	var from := int(f["location"])
	if from == to_id:
		return
	var ix := _idx(gs)
	_pull(ix["fl"], from, f)
	_push(ix["fl"], to_id, f)
	f["location"] = to_id


# ---------------------------------------------------------------- consultas
static func armies_in(gs: VGameState, province_id: int) -> Array:
	return _idx(gs)["ap"].get(province_id, EMPTY)


static func country_armies(gs: VGameState, tag: String) -> Array:
	return _idx(gs)["ac"].get(tag, EMPTY)


static func fleets_at(gs: VGameState, location: int) -> Array:
	return _idx(gs)["fl"].get(location, EMPTY)


static func country_fleets(gs: VGameState, tag: String) -> Array:
	return _idx(gs)["fc"].get(tag, EMPTY)


## Brigadas con bandera 'tag' desembarcadas en la provincia (para el límite de suministro).
static func brigades_in(gs: VGameState, tag: String, province_id: int) -> int:
	var n := 0
	for a in armies_in(gs, province_id):
		if a["country"] == tag:
			n += a["brigades"].size()
	return n


## Comprobación de coherencia (pruebas): el índice coincide con una reconstrucción desde cero.
static func verify(gs: VGameState) -> String:
	var live := _idx(gs)
	var saved := gs.unit_index
	rebuild(gs)
	var fresh := gs.unit_index
	gs.unit_index = saved
	for key in ["sg", "dmg"]:
		for k in fresh[key]:
			if not live[key].has(k):
				return "%s: falta el ejército %d" % [key, int(k)]
	for key in ["ap", "ac", "fc", "fl"]:
		var a: Dictionary = live[key]
		var b: Dictionary = fresh[key]
		if a.size() != b.size():
			return "%s: %d claves en el índice, %d reales" % [key, a.size(), b.size()]
		for k in a:
			for u in a[k]:
				if not b.has(k) or not _has_same(b[k], u):
					return "%s[%s]: sobra la unidad %d (provincia %s, embarcada %s, existe %s, rebelde %s)" % [key, str(k), int(u["id"]), str(u.get("province", u.get("location"))), str(u.get("embarked", "-")), str(gs.armies.has(int(u["id"])) or gs.fleets.has(int(u["id"]))), str(u.get("rebel_faction", "-"))]
		for k in b:
			if not a.has(k) or a[k].size() != b[k].size():
				return "%s[%s]: %d en el índice, %d reales" % [key, str(k), a.get(k, []).size(), b[k].size()]
			for u in b[k]:
				if not _has_same(a[k], u):
					return "%s[%s]: falta la unidad %d" % [key, str(k), int(u["id"])]
	return ""


# ----------------------------------------------------------- versión de acceso
static func bump_access(gs: VGameState) -> void:
	gs.access_version += 1
