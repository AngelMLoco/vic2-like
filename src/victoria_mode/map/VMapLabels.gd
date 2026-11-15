class_name VMapLabels
extends Node2D
## Etiquetas del mapa en coordenadas del mundo, por nivel de zoom:
##   lejano → PAÍSES (orientadas según la forma del territorio)
##   medio  → ESTADOS + capitales y ciudades importantes
##   cercano→ PROVINCIAS + zonas marítimas
## Se dibujan una vez por capa (draw cache de Godot) y solo se rehacen al cambiar fronteras.

const FAR_MAX := 0.62
const CLOSE_MIN := 2.0

var gs: VGameState
var country_layer: LabelLayer
var state_layer: LabelLayer
var province_layer: LabelLayer
var _level: int = -1


class LabelLayer:
	extends Node2D
	var items: Array = []  # {text, pos, size, angle, color, outline}
	var markers: Array = []  # {pos, radius, color, star}
	var font: Font

	func _draw() -> void:
		for m in markers:
			if m.get("star", false):
				_draw_star(m["pos"], m["radius"], m["color"])
			else:
				draw_circle(m["pos"], m["radius"] + 0.6, Color(0, 0, 0, 0.8))
				draw_circle(m["pos"], m["radius"], m["color"])
		for it in items:
			var size: int = it["size"]
			var text: String = it["text"]
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			draw_set_transform(it["pos"], it.get("angle", 0.0), Vector2.ONE)
			var origin := Vector2(-w * 0.5, size * 0.35)
			var outline: int = it.get("outline", max(2, size / 6))
			draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, it.get("outline_color", Color(0, 0, 0, 0.75)))
			draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, it["color"])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_star(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0
			var rr := r if i % 2 == 0 else r * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		var outline := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0
			var rr := (r + 0.9) if i % 2 == 0 else (r + 0.9) * 0.45
			outline.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(outline, Color(0, 0, 0, 0.85))
		draw_colored_polygon(pts, col)


func setup(state: VGameState) -> void:
	gs = state
	var font := ThemeDB.fallback_font
	country_layer = LabelLayer.new()
	state_layer = LabelLayer.new()
	province_layer = LabelLayer.new()
	for l in [province_layer, state_layer, country_layer]:
		l.font = font
		add_child(l)
	rebuild()


func rebuild() -> void:
	_build_countries()
	_build_states()
	_build_provinces()
	for l in [country_layer, state_layer, province_layer]:
		l.queue_redraw()


func update_zoom(z: float) -> void:
	var level := 0 if z < FAR_MAX else (1 if z < CLOSE_MIN else 2)
	# fundidos suaves entre niveles
	country_layer.modulate.a = clamp((FAR_MAX * 1.35 - z) / (FAR_MAX * 0.5), 0.0, 1.0)
	state_layer.modulate.a = clamp(min((z - FAR_MAX * 0.85) / 0.15, (CLOSE_MIN - z) / 0.25), 0.0, 1.0)
	province_layer.modulate.a = clamp((z - CLOSE_MIN) / 0.25, 0.0, 1.0)
	country_layer.visible = country_layer.modulate.a > 0.01
	state_layer.visible = state_layer.modulate.a > 0.01
	province_layer.visible = province_layer.modulate.a > 0.01
	_level = level


static func short_name(full: String) -> String:
	var idx := full.rfind(" de ")
	var s := full
	if idx >= 0:
		s = full.substr(idx + 4)
		for art in ["los ", "las ", "la ", "el "]:
			if s.begins_with(art):
				s = s.substr(art.length())
	return s


# ------------------------------------------------------------------ países
func _build_countries() -> void:
	country_layer.items.clear()
	for tag in gs.country_order:
		var c: Dictionary = gs.countries[tag]
		if c["provinces"].is_empty():
			continue
		var clusters := _clusters(c["provinces"])
		var biggest := 0.0
		for cl in clusters:
			biggest = max(biggest, cl["area"])
		for cl in clusters:
			if cl["area"] < biggest * 0.25 and cl["area"] < 9000.0:
				continue
			_add_shape_label(country_layer, cl["ids"], short_name(c["name"]).to_upper(), c["color_obj"].lightened(0.55), 9, 150, 0.95)


func _clusters(ids: Array) -> Array:
	var set_ids := {}
	for id in ids:
		set_ids[id] = true
	var seen := {}
	var out := []
	for id in ids:
		if seen.has(id):
			continue
		var stack := [id]
		seen[id] = true
		var members := []
		var area := 0.0
		while not stack.is_empty():
			var u: int = stack.pop_back()
			members.append(u)
			area += float(gs.provinces[u]["area_px"])
			for n in gs.provinces[u]["neighbors"]:
				if set_ids.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		out.append({"ids": members, "area": area})
	return out


## Etiqueta orientada por el eje principal del conjunto de provincias (PCA ponderado por área).
func _add_shape_label(layer: LabelLayer, ids: Array, text: String, color: Color, min_size: int, max_size: int, fill: float) -> void:
	var total := 0.0
	var mean := Vector2.ZERO
	for id in ids:
		var a := float(gs.provinces[id]["area_px"])
		total += a
		mean += gs.provinces[id]["center"] * a
	if total <= 0.0:
		return
	mean /= total
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for id in ids:
		var a := float(gs.provinces[id]["area_px"])
		var d: Vector2 = gs.provinces[id]["center"] - mean
		sxx += d.x * d.x * a
		syy += d.y * d.y * a
		sxy += d.x * d.y * a
	sxx /= total
	syy /= total
	sxy /= total
	var angle := 0.5 * atan2(2.0 * sxy, sxx - syy)
	var tr := sxx + syy
	var det := sxx * syy - sxy * sxy
	var disc: float = sqrt(max(0.0, tr * tr * 0.25 - det))
	var l1 := tr * 0.5 + disc
	var l2: float = max(0.0, tr * 0.5 - disc)
	var major: float = max(sqrt(l1) * 3.2, sqrt(total) * 0.9)
	if l1 < l2 * 1.6 or ids.size() < 3:
		angle = 0.0
		major = sqrt(total) * 1.1
	angle = clamp(angle, -0.7, 0.7)
	# anclar a la provincia más cercana al centroide (evita etiquetas en el mar)
	var anchor := mean
	var best := INF
	for id in ids:
		var d2: float = gs.provinces[id]["center"].distance_squared_to(mean)
		if d2 < best:
			best = d2
			anchor = gs.provinces[id]["center"]
	var pos := mean if gs.provinces.size() > 0 and _point_owned(mean, ids) else anchor
	var size := int(clamp(major * fill / max(3.0, float(text.length()) * 0.62), min_size, max_size))
	layer.items.append({"text": text, "pos": pos, "size": size, "angle": angle, "color": color})


func _point_owned(pt: Vector2, ids: Array) -> bool:
	# aproximación barata: el punto está dentro de la caja de alguna provincia del grupo
	for id in ids:
		var r: Rect2 = gs.provinces[id]["bbox"]
		if r.size.x > 2.0 and r.size.y > 2.0 and r.grow(-1.0).has_point(pt):
			return true
	return false


# ------------------------------------------------------------------ estados
func _build_states() -> void:
	state_layer.items.clear()
	state_layer.markers.clear()
	for key in gs.state_instances:
		var si: Dictionary = gs.state_instances[key]
		var st: Dictionary = gs.states[si["state"]]
		var area := 0.0
		for id in si["provinces"]:
			area += float(gs.provinces[id]["area_px"])
		if area < 120.0:
			continue
		var col := Color(0.97, 0.94, 0.86) if si["owner"] != "" else Color(0.85, 0.82, 0.74)
		_add_shape_label(state_layer, si["provinces"], st["name"], col, 5, 15, 0.6)
	# capitales y ciudades importantes
	var ranked := []
	for id in range(1, gs.first_sea_id):
		ranked.append(id)
	ranked.sort_custom(func(a, b): return int(gs.provinces[a]["population"]) > int(gs.provinces[b]["population"]))
	for i in min(220, ranked.size()):
		var id: int = ranked[i]
		state_layer.markers.append({"pos": gs.provinces[id]["center"], "radius": 1.6, "color": Color(0.95, 0.92, 0.85)})
	for tag in gs.country_order:
		var cap := int(gs.countries[tag]["capital"])
		if cap > 0 and not gs.countries[tag]["provinces"].is_empty():
			state_layer.markers.append({"pos": gs.provinces[cap]["center"], "radius": 4.0, "color": Color(1.0, 0.84, 0.3), "star": true})


# --------------------------------------------------------------- provincias
func _build_provinces() -> void:
	province_layer.items.clear()
	province_layer.markers.clear()
	for id in range(1, gs.max_id + 1):
		var p: Dictionary = gs.provinces[id]
		var pname: String = p["name"]
		if pname == "":
			continue
		var r: Rect2 = p["bbox"]
		var span: float = min(r.size.x * 1.15, sqrt(float(p["area_px"])) * 1.6)
		var size := int(clamp(span / max(3.0, float(pname.length()) * 0.95), 2, 6))
		if p["kind"] != "land":
			if p["kind"] == "lake":
				continue
			size = int(clamp(sqrt(float(p["area_px"])) / max(4.0, float(pname.length()) * 0.9), 3, 9))
			province_layer.items.append({"text": pname, "pos": p["center"], "size": size, "angle": 0.0,
				"color": Color(0.72, 0.84, 0.95, 0.9), "outline": 1, "outline_color": Color(0.05, 0.1, 0.15, 0.7)})
			continue
		province_layer.items.append({"text": pname, "pos": p["center"], "size": size, "angle": 0.0,
			"color": Color(1, 0.98, 0.92), "outline": 1})
		if int(p.get("naval_base", 0)) > 0:
			province_layer.markers.append({"pos": p["center"] + Vector2(0, size * 0.9 + 1.5), "radius": 1.3, "color": Color(0.35, 0.6, 1.0)})
		if int(p.get("fort", 0)) > 0:
			province_layer.markers.append({"pos": p["center"] + Vector2(-2.5, size * 0.9 + 1.5), "radius": 1.3, "color": Color(0.85, 0.35, 0.25)})
