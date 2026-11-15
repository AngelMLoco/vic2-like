class_name VChronicle
extends RefCounted
## Crónica histórica: la historia de la partida contada como historia nacional, no como registro técnico.
##
## Fuentes:
##   · eventos y decisiones (VEventSystem.apply_option / VDecisionSystem.take): título y opción elegida, o el
##     texto narrativo del campo "chronicle" del evento/opción;
##   · historia emergente: ganchos on_action que ya existen (guerra declarada, capital ocupada, paz, reforma,
##     rebelión, esfera, gobierno, despertar…) con plantillas de content/<paquete>/chronicle.json.
## Cada entrada lleva categoría (politics, war, economy, diplomacy, society, magic) para los filtros de la UI.
## Texto con marcadores: {country} {target} {war} {province} {reform} {level} {tech} {year}.

const CATEGORIES := ["politics", "war", "economy", "diplomacy", "society", "magic"]
const CATEGORY_NAMES := {"politics": "Política", "war": "Guerra", "economy": "Economía", "diplomacy": "Diplomacia",
	"society": "Sociedad", "magic": "Magia"}
## espacio de nombres del evento (core.<x>.*) → categoría de crónica
const NS_CATEGORY := {"economy": "economy", "politics": "politics", "society": "society", "religion": "society",
	"war": "war", "diplomacy": "diplomacy", "migration": "society", "technology": "economy"}
const MAX_ENTRIES := 6000


static func load_templates(gs: VGameState, root: String) -> void:
	gs.chronicle_templates = {}
	for path in VContentPacks.each(gs, root, "chronicle.json"):
		var d := VJson.load_dict(path)
		for k in d.get("templates", {}):
			var t: Dictionary = d["templates"][k]
			if not (String(t.get("cat", "")) in CATEGORIES):
				gs.data_errors.append("%s/chronicle.json: categoría desconocida en «%s»" % [VContentPacks.pack_of(path), k])
			gs.chronicle_templates[k] = t


## Categoría de un evento: campo "category" explícito o su espacio de nombres.
static func category_of_event(e: Dictionary) -> String:
	var explicit: String = e.get("category", "")
	if explicit != "":
		return explicit
	var parts: PackedStringArray = String(e.get("id", "")).split(".")
	if parts.size() >= 2:
		if parts[0] == "magic":
			return "magic"
		if parts[0] == "core":
			return NS_CATEGORY.get(parts[1], "politics")
	return "politics"


static func format(gs: VGameState, text: String, ctx: Dictionary) -> String:
	if text.find("{") < 0:
		return text
	var tag: String = ctx.get("tag", "")
	var out := text.replace("{country}", gs.country_name(tag) if tag != "" else "el mundo")
	var tg: String = ctx.get("target", "")
	out = out.replace("{target}", gs.country_name(tg) if tg != "" else "sus enemigos")
	out = out.replace("{year}", str(gs.date.year))
	if out.find("{war}") >= 0:
		out = out.replace("{war}", String(ctx.get("war_name", "guerra")))
	if out.find("{province}") >= 0:
		var p := gs.province(int(ctx.get("prov", 0)))
		out = out.replace("{province}", String(p.get("name", "")))
	if out.find("{reform}") >= 0:
		var r: Dictionary = gs.reforms.get(String(ctx.get("reform", "")), {})
		out = out.replace("{reform}", String(r.get("name", "")).to_lower())
		var lvl := gs.reform_level(tag, String(ctx.get("reform", ""))) if tag != "" else 0
		var lv: Array = r.get("levels", [])
		out = out.replace("{level}", String(lv[lvl]["name"]).to_lower() if lvl >= 0 and lvl < lv.size() else "")
	if out.find("{tech}") >= 0:
		out = out.replace("{tech}", String(gs.technologies.get(String(ctx.get("tech", "")), {}).get("name", "")))
	return out


## Entrada narrativa directa (historia emergente o texto de un evento).
static func record(gs: VGameState, tag: String, cat: String, text: String, important: bool, id: String = "", title: String = "", option: String = "") -> void:
	var h: Array = VScopedState.es(gs)["history"]
	h.append({"date": gs.date.text(), "month": gs.month_index, "year": gs.date.year, "kind": "history" if id == "" else "event",
		"id": id, "tag": tag, "title": title if title != "" else text, "option": option, "important": important,
		"cat": cat, "text": text})
	while h.size() > MAX_ENTRIES:
		h.remove_at(0)
	var st: Dictionary = VScopedState.es(gs)["stats"]
	st["chronicle_" + cat] = int(st.get("chronicle_" + cat, 0)) + 1


## Historia emergente desde los ganchos on_action (llamado por VEventSystem.notify).
static func on_action(gs: VGameState, action: String, ctx: Dictionary) -> void:
	if gs.chronicle_templates.is_empty():
		return
	var key := action
	var tag: String = ctx.get("tag", "")
	match action:
		"war_declared":
			if ctx.has("from"):
				return  # una sola entrada por guerra (la del agresor), visible para ambos
		"province_occupied":
			if tag == "" or int(gs.countries.get(tag, {}).get("capital", -1)) != int(ctx.get("prov", 0)):
				return
			key = "capital_occupied"
		"war_ended":
			if not ctx.get("primary", false):
				return
			key = "war_ended_" + String(ctx.get("result", "white_peace"))
		"technology_researched":
			if String(gs.technologies.get(String(ctx.get("tech", "")), {}).get("category", "")) != "magic":
				return
			key = "magic_technology"
	var t: Dictionary = gs.chronicle_templates.get(key, {})
	if t.is_empty():
		return
	record(gs, tag, String(t.get("cat", "politics")), format(gs, String(t.get("text", "")), ctx), bool(t.get("important", false)))
	if action == "war_declared" and ctx.get("target", "") != "":
		# la víctima también lo recuerda en su historia
		record(gs, String(ctx["target"]), "war", format(gs, String(t.get("text_target", t.get("text", ""))), ctx), false)


## Entradas de una nación (y las mundiales importantes) filtradas por categoría ("" = todas), más recientes primero.
static func entries_for(gs: VGameState, tag: String, cat: String = "", limit: int = 40) -> Array:
	var h: Array = VScopedState.es(gs)["history"]
	var out := []
	for i in range(h.size() - 1, -1, -1):
		var e: Dictionary = h[i]
		var et: String = e.get("tag", "")
		if et != tag and not (et == "" and e.get("important", false)):
			continue
		if cat != "" and String(e.get("cat", "politics")) != cat:
			continue
		out.append(e)
		if out.size() >= limit:
			break
	return out


## «Año 143 — La magia regresó al mundo.»
static func line(e: Dictionary) -> String:
	var year := int(e.get("year", 0))
	var body: String = e.get("text", "")
	if body == "":
		body = String(e.get("title", ""))
		if String(e.get("option", "")) != "":
			body += ": " + String(e["option"])
	return ("Año %d — %s" % [year, body]) if year > 0 else body
