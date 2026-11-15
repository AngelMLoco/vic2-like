class_name VEventSystem
extends RefCounted
## Motor de eventos data-driven (data/victoria_mode/events/*.json).
##
## Ciclo de vida de un evento:
##   carga → validación (ids, opciones, condiciones, efectos, follow-ups) → compilación → índice
##   (cadencia, ámbito, nación concreta, on_action) → planificador (cubos diarios de naciones; global el día 1)
##   → filtros baratos (nación, bandera requerida, once/cooldown, presupuesto mensual) → trigger compilado
##   → tirada MTTH/chance determinista → disparo: efectos inmediatos, crónica, y
##     · jugador: cola de ventanas (major/normal); notification se resuelve sola; hidden no se muestra
##     · IA: VEventAI elige opción (pesos + condiciones, determinista)
##   → efectos de la opción → follow-ups programados.
##
## Rendimiento: nunca se recorre el mundo entero ni los POPs. Cada día solo se evalúan las naciones de su cubo
## (≈1/28) contra los eventos de su cadencia; los eventos de una nación concreta solo se comprueban para ella;
## los de provincia solo sobre conjuntos candidatos (capital, provincias mágicas, ocupadas, costeras…).
## Los ganchos on_action (guerra declarada, batalla, reforma…) solo evalúan los eventos de ese gancho.

const BUCKETS := 28
const MONTH_BUDGET := 2  # eventos «normal» por nación y mes (major, notification y hidden no cuentan)
const QUEUE_MAX := 30
## follow_up: nunca se programa solo; ocurre únicamente como follow-up o con «trigger_event»
const CADENCES := ["daily", "monthly", "quarterly", "yearly", "on_action", "follow_up"]
const TYPES := ["major", "normal", "notification", "hidden"]
const SCOPES := ["global", "country", "state", "province"]
const PROVINCE_CANDIDATES := ["capital", "owned", "magic", "occupied", "coastal"]
const TARGETS := ["", "lowest_relation_neighbor", "highest_relation_neighbor", "strongest_neighbor", "weakest_neighbor",
	"sphere_leader", "war_enemy", "random_neighbor", "from"]
const ON_ACTIONS := ["war_declared", "war_ended", "battle_won", "battle_lost", "province_occupied", "government_changed",
	"reform_passed", "election_finished", "technology_researched", "invention_discovered", "country_enters_sphere",
	"country_leaves_sphere", "rebellion_started", "rebellion_won", "factory_closed", "factory_built", "magic_activated",
	"decision_taken", "mage_brain_drain"]


# ------------------------------------------------------------------ carga
static func load_definitions(gs: VGameState, root: String) -> void:
	var errors: Array = gs.data_errors
	gs.art_manifest = {}
	for apath in VContentPacks.each(gs, root, "art_manifest.json"):
		for a in VJson.load_array(apath, "categories"):
			if gs.art_manifest.has(a.get("art_key", "")):
				errors.append("%s: art_key duplicado «%s»" % [apath.get_file(), a.get("art_key", "")])
			gs.art_manifest[a.get("art_key", "")] = a
	gs.event_modifiers = {}
	for mpath in VContentPacks.each(gs, root, "modifiers.json"):
		for m in VJson.load_array(mpath, "modifiers"):
			if gs.event_modifiers.has(m["id"]):
				errors.append("%s: modificador duplicado «%s»" % [mpath.get_file(), m["id"]])
			gs.event_modifiers[m["id"]] = m
	var raw := []
	for path in VContentPacks.files(gs, root, "events/"):
		var f: String = VContentPacks.pack_of(path) + "/" + path.get_file()
		for ev in VJson.load_array(path, "events"):
			ev["_file"] = f
			raw.append(ev)
	gs.event_defs = {}
	for ev in raw:
		var id: String = ev.get("id", "")
		if id == "":
			errors.append("%s: evento sin id" % ev["_file"])
			continue
		if gs.event_defs.has(id):
			errors.append("%s: id de evento duplicado «%s»" % [ev["_file"], id])
			continue
		gs.event_defs[id] = _compile_event(gs, ev, errors)
	# follow-ups y trigger_event deben apuntar a eventos existentes
	for id in gs.event_defs:
		var e: Dictionary = gs.event_defs[id]
		for o in e["options"]:
			var fu: Dictionary = o.get("follow_up", {})
			if not fu.is_empty() and not gs.event_defs.has(fu.get("id", "")):
				errors.append("evento %s: follow-up a un evento inexistente «%s»" % [id, fu.get("id", "")])
	_build_index(gs)


static func _compile_event(gs: VGameState, ev: Dictionary, errors: Array) -> Dictionary:
	var id: String = ev["id"]
	var where := "evento %s" % id
	var e := {"id": id, "title": ev.get("title", id), "desc": ev.get("desc", ""), "art": ev.get("art", ""),
		"scope": ev.get("scope", "country"), "type": ev.get("type", "normal"), "cadence": ev.get("cadence", "monthly"),
		"on_action": ev.get("on_action", ""), "requires_flag": ev.get("requires_flag", ""), "not_flag": ev.get("not_flag", ""),
		"once": bool(ev.get("once", false)), "cooldown": int(ev.get("cooldown", 0)), "chance": float(ev.get("chance", -1.0)),
		"candidates": ev.get("province_candidates", "capital"), "target": ev.get("target", ""), "important": bool(ev.get("important", ev.get("type", "") == "major")),
		"tags": {}, "options": [], "category": ev.get("category", ""), "chronicle": String(ev.get("chronicle", ""))}
	e["category"] = VChronicle.category_of_event(e)
	if not (e["category"] in VChronicle.CATEGORIES):
		errors.append("%s: categoría desconocida «%s»" % [where, e["category"]])
	if e["art"] != "" and not gs.art_manifest.is_empty() and not gs.art_manifest.has(e["art"]):
		errors.append("%s: art_key «%s» no está en el manifiesto de arte" % [where, e["art"]])
	if not (e["scope"] in SCOPES):
		errors.append("%s: ámbito desconocido «%s»" % [where, e["scope"]])
	if not (e["type"] in TYPES):
		errors.append("%s: tipo desconocido «%s»" % [where, e["type"]])
	if not (e["cadence"] in CADENCES):
		errors.append("%s: cadencia desconocida «%s»" % [where, e["cadence"]])
	if e["cadence"] == "on_action" and not (e["on_action"] in ON_ACTIONS):
		errors.append("%s: on_action desconocido «%s»" % [where, e["on_action"]])
	if e["scope"] == "province" and not (e["candidates"] in PROVINCE_CANDIDATES):
		errors.append("%s: candidatos de provincia desconocidos «%s»" % [where, e["candidates"]])
	if not (e["target"] in TARGETS):
		errors.append("%s: selector de objetivo desconocido «%s»" % [where, e["target"]])
	for t in (ev.get("tags", []) as Array):
		if not gs.countries.has(t):
			errors.append("%s: país desconocido «%s»" % [where, t])
		e["tags"][t] = true
	e["trigger"] = VEventConditions.compile(gs, ev.get("trigger", {}), errors, where + ".trigger")
	var mt: Dictionary = ev.get("mtth", {})
	e["mtth"] = float(mt.get("months", 0.0))
	var mods := []
	for m in mt.get("modifiers", []):
		var cond: Dictionary = m.duplicate()
		var factor := float(cond.get("factor", 1.0))
		cond.erase("factor")
		mods.append([factor, VEventConditions.compile(gs, cond, errors, where + ".mtth")])
	e["mtth_mods"] = mods
	e["immediate"] = VEventEffects.validate(gs, ev.get("immediate", {}), errors, where + ".immediate")
	var opts: Array = ev.get("options", [])
	if opts.is_empty():
		errors.append("%s: el evento no tiene opciones" % where)
	for i in opts.size():
		var o: Dictionary = opts[i]
		var ow := "%s.opción %d" % [where, i + 1]
		var aiw = o.get("ai_weight", 10)
		var ai_mods := []
		var ai_base := 10.0
		if aiw is Dictionary:
			ai_base = float(aiw.get("base", 10))
			for m in aiw.get("modifiers", []):
				var cond2: Dictionary = m.duplicate()
				var f2 := float(cond2.get("factor", 1.0))
				cond2.erase("factor")
				ai_mods.append([f2, VEventConditions.compile(gs, cond2, errors, ow + ".ai_weight")])
		else:
			ai_base = float(aiw)
		e["options"].append({"name": o.get("name", "?"), "trigger": VEventConditions.compile(gs, o.get("trigger", {}), errors, ow + ".trigger"),
			"effects": VEventEffects.validate(gs, o.get("effects", {}), errors, ow), "ai_base": ai_base, "ai_mods": ai_mods,
			"follow_up": o.get("follow_up", {}), "chronicle": String(o.get("chronicle", ""))})
	return e


## Índices: cadencia → eventos genéricos de nación; nación → sus eventos propios; on_action → eventos.
static func _build_index(gs: VGameState) -> void:
	var ix := {"country": {}, "country_tag": {}, "province": {}, "global": {}, "on_action": {}}
	for cad in CADENCES:
		ix["country"][cad] = []
		ix["province"][cad] = []
		ix["global"][cad] = []
	for id in gs.event_defs:
		var e: Dictionary = gs.event_defs[id]
		if e["cadence"] == "follow_up":
			continue
		if e["cadence"] == "on_action":
			if not ix["on_action"].has(e["on_action"]):
				ix["on_action"][e["on_action"]] = []
			ix["on_action"][e["on_action"]].append(e)
			continue
		match e["scope"]:
			"global":
				ix["global"][e["cadence"]].append(e)
			"province", "state":
				ix["province"][e["cadence"]].append(e)
			_:
				if e["tags"].is_empty():
					ix["country"][e["cadence"]].append(e)
				else:
					for t in e["tags"]:
						if not ix["country_tag"].has(t):
							ix["country_tag"][t] = []
						ix["country_tag"][t].append(e)
	gs.event_index = ix


# ------------------------------------------------------------------ planificador
## Diario: follow-ups vencidos, eventos diarios y el cubo de naciones del día (eventos mensuales,
## trimestrales y anuales escalonados), decisiones de la IA y la capa mágica de esas naciones.
static func daily(gs: VGameState) -> void:
	if gs.event_index.is_empty() or gs.flags.get("events_disabled", false):
		return
	var t0 := VProfiler.begin()
	_process_scheduled(gs)
	for e in gs.event_index["global"]["daily"]:
		_consider(gs, e, {})
	var d := gs.date.day
	if d >= 1 and d <= BUCKETS:
		var order: Array = gs.country_order
		for i in range(d - 1, order.size(), BUCKETS):
			var tag: String = order[i]
			if gs.countries[tag]["provinces"].is_empty():
				continue
			_country_checks(gs, tag, i)
			var td := VProfiler.begin()
			VDecisionSystem.ai_country(gs, tag, i)
			VProfiler.end(gs, "decisions", td)
			var tm := VProfiler.begin()
			VMagicSystem.country_monthly(gs, tag)
			VMagicPolicy.ai_country(gs, tag, i)
			VProfiler.end(gs, "magic", tm)
	VProfiler.end(gs, "event_scheduler", t0)


## Mensual (cierre de mes): eventos globales, caducidad de modificadores y presupuestos.
static func monthly(gs: VGameState) -> void:
	if gs.event_index.is_empty() or gs.flags.get("events_disabled", false):
		return
	var t0 := VProfiler.begin()
	VScopedState.expire(gs)
	var tm := VProfiler.begin()
	VMageModel.world_monthly(gs)
	VProfiler.end(gs, "magic", tm)
	var gi: Dictionary = gs.event_index["global"]
	for e in gi["monthly"]:
		_consider(gs, e, {})
	if gs.month_index % 3 == 0:
		for e in gi["quarterly"]:
			_consider(gs, e, {})
	if gs.month_index % 12 == 0:
		for e in gi["yearly"]:
			_consider(gs, e, {})
	VScopedState.es(gs)["budget"] = {}
	VProfiler.end(gs, "event_scheduler", t0)


static func _country_checks(gs: VGameState, tag: String, idx: int) -> void:
	var cads := ["monthly"]
	if (gs.month_index + idx) % 3 == 0:
		cads.append("quarterly")
	if (gs.month_index + idx) % 12 == 0:
		cads.append("yearly")
	var ix: Dictionary = gs.event_index
	for cad in cads:
		for e in ix["country"][cad]:
			_consider(gs, e, {"tag": tag})
		for e in ix["province"][cad]:
			_consider_provinces(gs, e, tag)
	for e in ix["country_tag"].get(tag, []):
		if e["cadence"] in cads or e["cadence"] == "daily":
			_consider(gs, e, {"tag": tag})


## Filtros baratos → trigger → tirada → disparo.
static func _consider(gs: VGameState, e: Dictionary, ctx: Dictionary, roll_mode: String = "") -> bool:
	VProfiler.count(gs, "events_considered")
	if not _prefilter(gs, e, ctx):
		return false
	if e["target"] != "" and not ctx.has("target"):
		var t := select_target(gs, e["target"], ctx)
		if t == "":
			return false
		ctx["target"] = t
	var tt := Time.get_ticks_usec()
	VProfiler.count(gs, "trigger_checks")
	var ok := VEventConditions.check(gs, e["trigger"], ctx)
	VProfiler.add(gs, "event_trigger_checks", (Time.get_ticks_usec() - tt) / 1000.0)
	if not ok:
		return false
	if roll_mode != "force" and not _roll(gs, e, ctx):
		return false
	fire(gs, e, ctx)
	return true


static func _prefilter(gs: VGameState, e: Dictionary, ctx: Dictionary) -> bool:
	var tag: String = ctx.get("tag", "")
	if not e["tags"].is_empty() and not e["tags"].has(tag):
		return false
	if e["requires_flag"] != "" and not gs.flags.get(e["requires_flag"], false):
		return false
	if e["not_flag"] != "" and gs.flags.get(e["not_flag"], false):
		return false
	var es := VScopedState.es(gs)
	var key := _key(e, ctx)
	if es["fired"].has(key):
		if e["once"]:
			return false
		if e["cooldown"] > 0 and gs.month_index - int(es["fired"][key]) < e["cooldown"]:
			return false
	if e["type"] == "normal" and tag != "":
		if int(es["budget"].get(tag, 0)) >= MONTH_BUDGET:
			return false
	return true


static func _key(e: Dictionary, ctx: Dictionary) -> String:
	match e["scope"]:
		"global":
			return e["id"]
		"province", "state":
			return "%s|%d" % [e["id"], int(ctx.get("prov", 0))]
	return "%s|%s" % [e["id"], ctx.get("tag", "")]


## Probabilidad por comprobación: MTTH (meses, con modificadores) según la cadencia, o «chance».
## Sin ninguno de los dos, el evento ocurre en cuanto se cumple el trigger. Tirada determinista.
static func _roll(gs: VGameState, e: Dictionary, ctx: Dictionary) -> bool:
	var p := 1.0
	if float(e["mtth"]) > 0.0:
		var m := float(e["mtth"])
		for mod in e["mtth_mods"]:
			if VEventConditions.check(gs, mod[1], ctx):
				m *= float(mod[0])
		var period: float = {"daily": 1.0 / 30.0, "monthly": 1.0, "quarterly": 3.0, "yearly": 12.0}.get(e["cadence"], 1.0)
		p = 1.0 - pow(0.5, period / maxf(0.1, m))
	elif float(e["chance"]) >= 0.0:
		p = float(e["chance"])
	if p >= 1.0:
		return true
	return roll01("%s|%s|%d|%d" % [e["id"], ctx.get("tag", ""), int(ctx.get("prov", 0)), gs.date.ordinal()]) < p


## Número determinista en [0, 1) a partir de una clave: hash de la cadena mezclado con rand_from_seed
## (el hash de cadenas parecidas da valores parecidos; sin mezclar, las tiradas quedarían sesgadas).
static func roll01(key: String) -> float:
	var r: PackedInt64Array = rand_from_seed(key.hash())
	return float(r[0] % 1000000) / 1000000.0


static func _consider_provinces(gs: VGameState, e: Dictionary, tag: String) -> void:
	for id in province_candidates(gs, e["candidates"], tag):
		if _consider(gs, e, {"tag": tag, "prov": int(id)}):
			return  # como mucho una provincia por evento y comprobación


static func province_candidates(gs: VGameState, kind: String, tag: String) -> Array:
	var c: Dictionary = gs.countries[tag]
	match kind:
		"capital":
			var cap := int(c.get("capital", -1))
			return [cap] if cap > 0 else []
		"magic":
			return VMagicSystem.country_deposit_provinces(gs, tag)
		"occupied", "coastal", "owned":
			var out := []
			for id in c["provinces"]:
				var p: Dictionary = gs.provinces[id]
				if kind == "owned" or (kind == "occupied" and p["controller"] != tag) or (kind == "coastal" and p.get("coastal", false)):
					out.append(id)
			return out
	return []


## Selectores de objetivo (nación) para eventos diplomáticos.
static func select_target(gs: VGameState, kind: String, ctx: Dictionary) -> String:
	var tag: String = ctx.get("tag", "")
	if tag == "":
		return ""
	match kind:
		"from":
			return ctx.get("from", "")
		"sphere_leader":
			return gs.countries[tag].get("sphere_leader", "")
		"war_enemy":
			for wid in gs.countries[tag].get("wars", []):
				var w: Dictionary = gs.wars.get(int(wid), {})
				var en := VWarSystem.enemies_in_war(gs, w, tag)
				if not en.is_empty():
					return en[0]
			return ""
	var best := ""
	var bv := -INF
	var ns: Array = VDiplomacySystem.neighbor_countries(gs, tag)
	for n in ns:
		if gs.countries[n]["provinces"].is_empty():
			continue
		var v := 0.0
		match kind:
			"lowest_relation_neighbor":
				v = -float(gs.relation(tag, n))
			"highest_relation_neighbor":
				v = float(gs.relation(tag, n))
			"strongest_neighbor":
				v = float(gs.countries[n].get("military_score", 0.0))
			"weakest_neighbor":
				v = -float(gs.countries[n].get("military_score", 0.0))
			"random_neighbor":
				v = roll01("%s|%s|%d" % [tag, n, gs.month_index])
		if v > bv:
			bv = v
			best = n
	return best


# ------------------------------------------------------------------ disparo
static func fire(gs: VGameState, e: Dictionary, ctx: Dictionary) -> void:
	var t0 := VProfiler.begin()
	var es := VScopedState.es(gs)
	es["fired"][_key(e, ctx)] = gs.month_index
	var tag: String = ctx.get("tag", "")
	if tag != "" and e["type"] == "normal":
		es["budget"][tag] = int(es["budget"].get(tag, 0)) + 1
	VProfiler.count(gs, "events_fired")
	_stat(gs, "fired")
	ctx["source"] = e["id"]
	if not e["immediate"].is_empty():
		VEventEffects.apply(gs, e["immediate"], ctx)
	var player := gs.player_tag
	var for_player: bool = player != "" and (tag == player or (e["scope"] == "global" and e["type"] == "major"))
	# M5: métricas diferenciadas (jugador / IA visible / IA oculta / espacio de nombres / categoría)
	_stat(gs, "type_" + String(e["type"]))
	_stat(gs, "ns_" + String(e["id"]).get_slice(".", 0))
	_stat(gs, "cat_" + String(e["category"]))
	if for_player:
		if e["type"] == "notification":
			_stat(gs, "player_notification")
		elif e["type"] == "hidden":
			_stat(gs, "player_hidden")
	elif e["type"] == "hidden":
		_stat(gs, "ai_hidden")
	else:
		_stat(gs, "ai_visible")
	if for_player and e["type"] in ["major", "normal"]:
		_stat(gs, "player_major" if e["type"] == "major" else "player_normal")
		if e["scope"] == "global":
			# acontecimiento mundial: sus efectos ya se aplicaron; la ventana informa y aplica la opción elegida
			ctx["tag"] = player
		es["queue"].append({"id": e["id"], "ctx": _safe_ctx(ctx), "date": gs.date.text()})
		while es["queue"].size() > QUEUE_MAX:
			var old: Dictionary = es["queue"].pop_front()
			_resolve_ai(gs, gs.event_defs.get(old["id"], {}), old["ctx"])
		VProfiler.end(gs, "event_effects", t0)
		return
	if e["type"] == "notification" and for_player:
		gs.log_event(player, "%s" % e["title"])
	if tag == "" or tag != player or e["type"] in ["notification", "hidden"]:
		_resolve_ai(gs, e, ctx)
	VProfiler.end(gs, "event_effects", t0)


static func _resolve_ai(gs: VGameState, e: Dictionary, ctx: Dictionary) -> void:
	if e.is_empty():
		return
	var ta := VProfiler.begin()
	var idx := VEventAI.choose(gs, e, ctx)
	VProfiler.end(gs, "event_ai", ta)
	VProfiler.count(gs, "ai_choices")
	_stat(gs, "ai")
	apply_option(gs, e, idx, ctx)


## Aplica la opción elegida (jugador o IA): efectos, crónica y follow-up.
static func apply_option(gs: VGameState, e: Dictionary, idx: int, ctx: Dictionary) -> void:
	if idx < 0 or idx >= e["options"].size():
		return
	var o: Dictionary = e["options"][idx]
	ctx["source"] = e["id"]
	VEventEffects.apply(gs, o["effects"], ctx)
	var tag: String = ctx.get("tag", "")
	if e["important"] or tag == gs.player_tag or e["chronicle"] != "" or o["chronicle"] != "":
		var text: String = o["chronicle"] if o["chronicle"] != "" else e["chronicle"]
		VScopedState.chronicle(gs, "event", e["id"], tag, e["title"], o["name"], e["important"], "", VChronicle.format(gs, text, ctx))
	var fu: Dictionary = o["follow_up"]
	if not fu.is_empty():
		schedule(gs, fu["id"], ctx, int(fu.get("days", int(fu.get("months", 1)) * 30)))


## Elección del jugador sobre el evento i de la cola.
static func choose(gs: VGameState, queue_index: int, option: int) -> void:
	var q: Array = VScopedState.es(gs)["queue"]
	if queue_index < 0 or queue_index >= q.size():
		return
	var item: Dictionary = q[queue_index]
	q.remove_at(queue_index)
	var e: Dictionary = gs.event_defs.get(item["id"], {})
	if e.is_empty():
		return
	var ctx: Dictionary = item["ctx"].duplicate()
	if e["scope"] == "global":
		ctx["tag"] = ""
	apply_option(gs, e, option, ctx)


static func option_available(gs: VGameState, e: Dictionary, idx: int, ctx: Dictionary) -> bool:
	return VEventConditions.check(gs, e["options"][idx]["trigger"], ctx)


static func _safe_ctx(ctx: Dictionary) -> Dictionary:
	var out := {}
	for k in ["tag", "prov", "target", "from"]:
		if ctx.has(k):
			out[k] = ctx[k]
	return out


# ------------------------------------------------------------------ follow-ups y on_action
## Programa un evento (follow-up o trigger_event) dentro de 'days' días con el mismo contexto.
static func schedule(gs: VGameState, id: String, ctx: Dictionary, days: int) -> void:
	VScopedState.es(gs)["scheduled"].append({"id": id, "due": gs.date.ordinal() + maxi(0, days), "ctx": _safe_ctx(ctx)})


static func _process_scheduled(gs: VGameState) -> void:
	var sch: Array = VScopedState.es(gs)["scheduled"]
	if sch.is_empty():
		return
	var today := gs.date.ordinal()
	var due := []
	for i in range(sch.size() - 1, -1, -1):
		if int(sch[i]["due"]) <= today:
			due.append(sch[i])
			sch.remove_at(i)
	due.reverse()
	for item in due:
		var e: Dictionary = gs.event_defs.get(item["id"], {})
		if e.is_empty():
			continue
		var ctx: Dictionary = item["ctx"].duplicate()
		# un follow-up ocurre si su trigger se cumple (sin tirada MTTH ni presupuesto)
		if VEventConditions.check(gs, e["trigger"], ctx):
			fire(gs, e, ctx)


## Gancho ligero para los sistemas: solo evalúa los eventos declarados para esa acción.
static func notify(gs: VGameState, action: String, ctx: Dictionary) -> void:
	if gs.event_index.is_empty() or gs.flags.get("events_disabled", false):
		return
	var tc := VProfiler.begin()
	VChronicle.on_action(gs, action, ctx)
	VProfiler.end(gs, "chronicle", tc)
	var lst: Array = gs.event_index["on_action"].get(action, [])
	VProfiler.count(gs, "on_actions")
	if lst.is_empty():
		return
	for e in lst:
		_consider(gs, e, ctx.duplicate())


static func _stat(gs: VGameState, k: String) -> void:
	var st: Dictionary = VScopedState.es(gs)["stats"]
	st[k] = int(st.get(k, 0)) + 1


# ------------------------------------------------------------------ depuración / pruebas
## Dispara un evento ignorando trigger y tirada (pruebas y consola de depuración).
static func debug_fire(gs: VGameState, id: String, tag: String = "", prov: int = 0, target: String = "") -> bool:
	var e: Dictionary = gs.event_defs.get(id, {})
	if e.is_empty():
		push_error("VEventSystem.debug_fire: evento desconocido «%s»" % id)
		return false
	var ctx := {"tag": tag}
	if prov > 0:
		ctx["prov"] = prov
	if target != "":
		ctx["target"] = target
	elif e["target"] != "":
		ctx["target"] = select_target(gs, e["target"], ctx)
	fire(gs, e, ctx)
	return true


static func pending(gs: VGameState) -> Array:
	return VScopedState.es(gs)["queue"]
