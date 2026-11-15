class_name VMapUnits
extends Node2D
## Contadores de ejércitos y flotas sobre el mapa, dibujados por lotes en un único nodo (no un nodo
## por unidad). Tamaño constante en pantalla. A zoom lejano los ejércitos de una misma nación en la
## misma zona se agrupan en un contador. También muestra batallas, rutas de los seleccionados y
## permite saber qué contador hay bajo el cursor.

const W := 46.0
const H := 18.0

var gs: VGameState
var zoom: float = 1.0
var selected_armies: Array = []
var selected_fleet: int = 0
var focus_tag: String = ""
var _hits: Array = []  # [Rect2 (mundo), kind, id]
var font: Font


func setup(state: VGameState) -> void:
	gs = state
	font = ThemeDB.fallback_font
	z_index = 5


func refresh(z: float) -> void:
	zoom = z
	queue_redraw()


func _draw() -> void:
	_hits.clear()
	if gs == null:
		return
	var s := 1.0 / maxf(0.05, zoom)
	var grouped := zoom < 0.55
	# a zoom lejano solo se ven las unidades relevantes para el jugador (propias, enemigas, rebeldes)
	var me := gs.player_tag
	var relevant := {}
	var filter := grouped and me != ""
	# ejércitos agrupados por provincia (o región a zoom lejano)
	var groups := {}
	for aid in gs.armies:
		var a: Dictionary = gs.armies[aid]
		if int(a["embarked"]) > 0:
			continue
		if filter and not (int(aid) in selected_armies) and not _relevant(a["country"], int(a.get("rebel_faction", 0)) > 0, me, relevant):
			continue
		var prov := int(a["province"])
		var key := "%s|%d" % [_owner_key(a), prov if not grouped else int(gs.provinces[prov]["state"]) * 100000]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(a)
	# rutas de los ejércitos seleccionados
	for aid in selected_armies:
		var a: Dictionary = gs.armies.get(int(aid), {})
		if a.is_empty() or a["path"].is_empty():
			continue
		var pts := PackedVector2Array([gs.provinces[int(a["province"])]["center"]])
		for p in a["path"]:
			pts.append(gs.provinces[int(p)]["center"])
		draw_polyline(pts, Color(1, 0.9, 0.4, 0.9), 2.0 * s, true)
		draw_circle(pts[-1], 3.0 * s, Color(1, 0.9, 0.4))
	var f_sel: Dictionary = gs.fleets.get(selected_fleet, {})
	if not f_sel.is_empty() and not f_sel["path"].is_empty():
		var fp := PackedVector2Array([gs.provinces[int(f_sel["location"])]["center"]])
		for p in f_sel["path"]:
			fp.append(gs.provinces[int(p)]["center"])
		draw_polyline(fp, Color(0.5, 0.8, 1.0, 0.9), 2.0 * s, true)
	# batallas
	for bid in gs.battles:
		var bt: Dictionary = gs.battles[bid]
		var c: Vector2 = gs.provinces[int(bt["province"])]["center"]
		draw_circle(c + Vector2(0, -14 * s), 7.0 * s, Color(0.8, 0.1, 0.1, 0.9))
		draw_string(font, c + Vector2(-4 * s, -10 * s), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), Color.WHITE)
	var stack := {}
	for key in groups:
		var arr: Array = groups[key]
		var a0: Dictionary = arr[0]
		var prov := int(a0["province"])
		var center: Vector2 = gs.provinces[prov]["center"]
		var n := int(stack.get(prov, 0))
		stack[prov] = n + 1
		var pos := center + Vector2(0, (H + 2) * s * n)
		var men := 0
		var org := 0.0
		var nb := 0
		for a in arr:
			men += VArmySystem.army_strength(gs, a)
			org += VArmySystem.army_organisation(gs, a) * a["brigades"].size()
			nb += a["brigades"].size()
		org = org / maxf(1.0, float(nb))
		var is_sel := false
		for a in arr:
			if int(a["id"]) in selected_armies:
				is_sel = true
		var label: String = a0["name"] if arr.size() == 1 else "%d ejércitos" % arr.size()
		_counter(pos, s, a0, label, men, org, is_sel, arr.size() == 1 and not grouped)
		var rect := Rect2(pos - Vector2(W, H) * 0.5 * s, Vector2(W, H) * s)
		for a in arr:
			_hits.append([rect, "army", int(a["id"])])
	# flotas
	for fid in gs.fleets:
		var f: Dictionary = gs.fleets[fid]
		if filter and int(fid) != selected_fleet and not _relevant(f["country"], false, me, relevant):
			continue
		var loc := int(f["location"])
		var center2: Vector2 = gs.provinces[loc]["center"]
		var docked: bool = gs.is_land(loc)
		var pos2 := center2 + (Vector2(18, 10) * s if docked else Vector2.ZERO)
		var col := gs.country_color(f["country"])
		var r := Rect2(pos2 - Vector2(18, 8) * s, Vector2(36, 16) * s)
		draw_rect(r, Color(0.08, 0.12, 0.2, 0.95))
		draw_rect(Rect2(r.position, Vector2(6 * s, r.size.y)), col)
		draw_rect(r, Color(1, 0.9, 0.4) if int(fid) == selected_fleet else Color(0.6, 0.75, 0.9), false, 1.5 * s)
		var txt := "%d" % f["ships"].size()
		if not f["transported_armies"].is_empty():
			txt += "+T"
		draw_string(font, r.position + Vector2(8 * s, 12 * s), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * s), Color(0.85, 0.92, 1.0))
		_hits.append([r, "fleet", int(fid)])


func _relevant(tag: String, rebel: bool, me: String, cache: Dictionary) -> bool:
	if rebel or tag == me:
		return true
	if not cache.has(tag):
		cache[tag] = VWarSystem.at_war_with(gs, me, tag) or VWarSystem.shared_war(gs, me, tag)
	return cache[tag]


func _owner_key(a: Dictionary) -> String:
	return ("R%d" % int(a["rebel_faction"])) if int(a.get("rebel_faction", 0)) > 0 else a["country"]


func _counter(pos: Vector2, s: float, a: Dictionary, label: String, men: int, org: float, selected: bool, show_name: bool) -> void:
	var rebel := int(a.get("rebel_faction", 0)) > 0
	var col := gs.country_color(a["country"]) if not rebel else Color("1a1a1a")
	var hostile := focus_tag != "" and (rebel or VWarSystem.at_war_with(gs, focus_tag, a["country"]))
	var r := Rect2(pos - Vector2(W, H) * 0.5 * s, Vector2(W, H) * s)
	draw_rect(r, Color(0.1, 0.09, 0.07, 0.95))
	# «bandera»
	var flag: Dictionary = gs.countries.get(a["country"], {}).get("flag", {})
	var fc: Array = flag.get("colors", [])
	var c1: Color = Color(fc[0]) if fc.size() > 0 and not rebel else col
	var c2: Color = Color(fc[1]) if fc.size() > 1 and not rebel else Color(0.5, 0, 0)
	draw_rect(Rect2(r.position, Vector2(10 * s, r.size.y * 0.5)), c1)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(10 * s, r.size.y * 0.5)), c2)
	# organización
	draw_rect(Rect2(r.position + Vector2(10 * s, r.size.y - 3 * s), Vector2((r.size.x - 10 * s) * clampf(org, 0.0, 1.0), 3 * s)), Color(0.4, 0.85, 0.4))
	var border := Color(1, 0.9, 0.4) if selected else (Color(0.95, 0.3, 0.25) if hostile else Color(0.75, 0.65, 0.45))
	draw_rect(r, border, false, (2.0 if selected else 1.2) * s)
	draw_string(font, r.position + Vector2(12 * s, 11 * s), _fmt_men(men), HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * s), Color(1, 0.97, 0.88))
	if show_name and zoom > 1.2:
		draw_string(font, r.position + Vector2(0, -2 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), Color(1, 0.95, 0.8))
	if a.get("retreating", false):
		draw_string(font, r.position + Vector2(r.size.x + 2 * s, 11 * s), "«", HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * s), Color(1, 0.5, 0.4))


static func _fmt_men(men: int) -> String:
	if men >= 1000:
		return "%.1fk" % (float(men) / 1000.0)
	return str(men)


## Unidad bajo un punto del mundo: {"kind": "army"/"fleet", "id": n} o {}.
func unit_at(world_pos: Vector2) -> Dictionary:
	for i in range(_hits.size() - 1, -1, -1):
		var h: Array = _hits[i]
		if (h[0] as Rect2).has_point(world_pos):
			return {"kind": h[1], "id": h[2]}
	return {}


## Ejércitos (de 'tag') dentro de un rectángulo del mundo (selección por arrastre).
func armies_in_rect(rect: Rect2, tag: String) -> Array:
	var out := []
	for h in _hits:
		if h[1] == "army" and rect.intersects(h[0]):
			var a: Dictionary = gs.armies.get(int(h[2]), {})
			if not a.is_empty() and a["country"] == tag and int(a.get("rebel_faction", 0)) == 0 and not (int(h[2]) in out):
				out.append(int(h[2]))
	return out
