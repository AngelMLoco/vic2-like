extends Control

signal province_selected(index: int)
signal army_selected(army_id: int)

var provinces: Array = []
var armies: Array = []
var country_colors: Dictionary = {}
var province_polygons: Array[PackedVector2Array] = []
var province_centers: Array[Vector2] = []
var army_positions := {}
var selected_index: int = -1
var selected_army_id: int = -1
var hovered_index: int = -1
var interactive: bool = true
var show_country_labels: bool = true
var show_province_names: bool = true
var compact_mode: bool = false
var player_country: String = ""
var _last_size := Vector2.ZERO

const SEA := Color("4f7480")
const BORDER := Color("342820")
const PAPER_LINE := Color(0.82, 0.86, 0.82, 0.12)

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
    resized.connect(_on_resized)
    queue_redraw()

func set_world(new_provinces: Array, colors: Dictionary) -> void:
    provinces = new_provinces
    country_colors = colors
    _last_size = Vector2.ZERO
    _ensure_geometry()
    queue_redraw()

func set_armies(new_armies: Array, new_player_country: String) -> void:
    armies = new_armies
    player_country = new_player_country
    queue_redraw()

func set_selected(index: int) -> void:
    selected_index = index
    queue_redraw()

func set_selected_army(army_id: int) -> void:
    selected_army_id = army_id
    queue_redraw()

func get_province_center(index: int) -> Vector2:
    _ensure_geometry()
    if index >= 0 and index < province_centers.size():
        return province_centers[index]
    return Vector2.ZERO

func _on_resized() -> void:
    _last_size = Vector2.ZERO
    _ensure_geometry()
    queue_redraw()

func _normalized_centers() -> Array[Vector2]:
    # Cinco masas terrestres inspiradas en el boceto del usuario.
    return [
        # Continente occidental
        Vector2(0.12,0.25), Vector2(0.22,0.20), Vector2(0.31,0.26), Vector2(0.16,0.37),
        Vector2(0.27,0.39), Vector2(0.10,0.49), Vector2(0.22,0.51), Vector2(0.31,0.48),
        # Isla septentrional / corona
        Vector2(0.43,0.16), Vector2(0.47,0.26), Vector2(0.41,0.29),
        # Continente oriental
        Vector2(0.66,0.20), Vector2(0.77,0.23), Vector2(0.85,0.31), Vector2(0.67,0.34),
        Vector2(0.78,0.39), Vector2(0.88,0.46), Vector2(0.69,0.49), Vector2(0.80,0.54),
        # Isla / istmo central alargado
        Vector2(0.43,0.49), Vector2(0.40,0.61), Vector2(0.38,0.73),
        # Gran masa austral
        Vector2(0.61,0.65), Vector2(0.72,0.65), Vector2(0.83,0.66), Vector2(0.57,0.77),
        Vector2(0.69,0.78), Vector2(0.80,0.78), Vector2(0.62,0.88), Vector2(0.74,0.88)
    ]

func _ensure_geometry() -> void:
    if size.x <= 4.0 or size.y <= 4.0:
        return
    if _last_size == size and province_polygons.size() == 30:
        return

    _last_size = size
    province_polygons.clear()
    province_centers.clear()

    var centers := _normalized_centers()
    var rx := size.x * (0.060 if not compact_mode else 0.058)
    var ry := size.y * (0.082 if not compact_mode else 0.078)

    for i in range(30):
        var center: Vector2 = centers[i] * size
        province_centers.append(center)
        var wobble := float((i * 41) % 11 - 5)
        var pts := PackedVector2Array([
            center + Vector2(-rx * 0.96, -ry * 0.22 + wobble),
            center + Vector2(-rx * 0.50, -ry * 0.92),
            center + Vector2( rx * 0.35, -ry * 0.96 + wobble * 0.2),
            center + Vector2( rx * 0.96, -ry * 0.24),
            center + Vector2( rx * 0.82,  ry * 0.52 + wobble * 0.15),
            center + Vector2( rx * 0.18,  ry * 0.94),
            center + Vector2(-rx * 0.58,  ry * 0.84 - wobble * 0.12),
            center + Vector2(-rx * 0.98,  ry * 0.28)
        ])
        province_polygons.append(pts)

func _draw_landmass(points: Array[Vector2], fill: Color) -> void:
    var poly := PackedVector2Array()
    for p in points:
        poly.append(p * size)
    draw_colored_polygon(poly, fill)
    draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.13,0.15,0.13,0.45), 3.0, true)

func _draw() -> void:
    _ensure_geometry()
    draw_rect(Rect2(Vector2.ZERO, size), SEA)

    for y in range(0, int(size.y), maxi(28, int(size.y / 18.0))):
        draw_line(Vector2(0,y), Vector2(size.x,y), PAPER_LINE, 1.0)
    for x in range(0, int(size.x), maxi(36, int(size.x / 22.0))):
        draw_line(Vector2(x,0), Vector2(x,size.y), PAPER_LINE, 1.0)

    # Siluetas generales del boceto: occidente, isla norte, oriente, isla central y sur.
    _draw_landmass([
        Vector2(0.035,0.31),Vector2(0.11,0.18),Vector2(0.25,0.15),Vector2(0.34,0.23),
        Vector2(0.32,0.34),Vector2(0.38,0.40),Vector2(0.29,0.52),Vector2(0.18,0.58),
        Vector2(0.08,0.54),Vector2(0.03,0.45)
    ], Color("756f55"))
    _draw_landmass([
        Vector2(0.38,0.10),Vector2(0.46,0.07),Vector2(0.51,0.13),Vector2(0.50,0.31),
        Vector2(0.44,0.34),Vector2(0.38,0.27)
    ], Color("756f55"))
    _draw_landmass([
        Vector2(0.59,0.12),Vector2(0.70,0.08),Vector2(0.82,0.15),Vector2(0.91,0.29),
        Vector2(0.94,0.46),Vector2(0.86,0.60),Vector2(0.72,0.60),Vector2(0.63,0.50),
        Vector2(0.67,0.38),Vector2(0.59,0.30)
    ], Color("756f55"))
    _draw_landmass([
        Vector2(0.38,0.42),Vector2(0.45,0.40),Vector2(0.47,0.51),Vector2(0.44,0.67),
        Vector2(0.41,0.82),Vector2(0.34,0.81),Vector2(0.35,0.63)
    ], Color("756f55"))
    _draw_landmass([
        Vector2(0.51,0.64),Vector2(0.65,0.57),Vector2(0.82,0.58),Vector2(0.91,0.68),
        Vector2(0.87,0.83),Vector2(0.75,0.94),Vector2(0.60,0.96),Vector2(0.51,0.86)
    ], Color("756f55"))

    for poly in province_polygons:
        var shadow := PackedVector2Array()
        for p in poly:
            shadow.append(p + Vector2(2,3))
        draw_colored_polygon(shadow, Color(0.08,0.12,0.12,0.28))

    for i in range(mini(province_polygons.size(), provinces.size())):
        var p: Dictionary = provinces[i]
        var owner := String(p.get("owner", ""))
        var fill: Color = country_colors.get(owner, Color("777777")).darkened(0.08)

        if String(p.get("occupied_by", "")) != "":
            fill = fill.darkened(0.25)

        if i == selected_index:
            fill = fill.lightened(0.24)
        elif i == hovered_index:
            fill = fill.lightened(0.12)

        draw_colored_polygon(province_polygons[i], fill)
        draw_polyline(province_polygons[i] + PackedVector2Array([province_polygons[i][0]]), BORDER, 1.7 if not compact_mode else 1.0, true)

        var occupation: float = float(p.get("occupation", 0.0))
        if occupation > 0.0 and occupation < 1.0 and not compact_mode:
            var center := province_centers[i]
            draw_arc(center, 15.0, -PI/2.0, -PI/2.0 + TAU * occupation, 20, Color("f1d78b"), 4.0)

        if not compact_mode:
            _draw_terrain_symbol(i, String(p.get("resource", "")))
            if show_province_names and size.x > 700:
                var center := province_centers[i]
                draw_string(get_theme_default_font(), center + Vector2(-34, 33), String(p.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, 68, 12, Color(0.12,0.10,0.08,0.75))

    if show_country_labels and not compact_mode:
        var sums := {}
        var counts := {}
        for i in range(mini(province_centers.size(), provinces.size())):
            var owner := String(provinces[i].get("owner", ""))
            sums[owner] = sums.get(owner, Vector2.ZERO) + province_centers[i]
            counts[owner] = int(counts.get(owner, 0)) + 1
        for owner in sums:
            var pos: Vector2 = sums[owner] / float(counts[owner])
            draw_string(get_theme_default_font(), pos + Vector2(-70, 4), String(owner), HORIZONTAL_ALIGNMENT_CENTER, 140, 24, Color("2c211a"))

    army_positions.clear()
    if not compact_mode:
        var per_province := {}
        for army_data in armies:
            var army: Dictionary = army_data
            if int(army.get("soldiers", 0)) <= 0:
                continue
            var province_index := int(army.get("province", -1))
            if province_index < 0 or province_index >= province_centers.size():
                continue
            var count := int(per_province.get(province_index, 0))
            per_province[province_index] = count + 1
            var pos := province_centers[province_index] + Vector2(-22 + count * 24, -22)
            var army_id := int(army.get("id", -1))
            army_positions[army_id] = pos
            _draw_army_counter(army, pos)

    if selected_index >= 0 and selected_index < provinces.size() and not compact_mode:
        draw_circle(province_centers[selected_index], 7.0, Color("f0d789"))
        draw_circle(province_centers[selected_index], 4.0, Color("6e1d23"))

func _draw_army_counter(army: Dictionary, pos: Vector2) -> void:
    var country := String(army.get("country", ""))
    var own := country == player_country
    var selected := int(army.get("id", -1)) == selected_army_id
    var bg := Color("25323c") if own else Color("4a2927")
    if selected:
        bg = Color("876226")
    draw_rect(Rect2(pos - Vector2(19,13), Vector2(38,26)), bg, true)
    draw_rect(Rect2(pos - Vector2(19,13), Vector2(38,26)), Color("e2c887") if selected else Color("d2c39a"), false, 2.0)
    var brigades := maxi(1, int(ceil(float(army.get("soldiers", 0)) / 3000.0)))
    draw_string(get_theme_default_font(), pos + Vector2(-17,5), "%dK" % int(round(float(army.get("soldiers",0))/1000.0)), HORIZONTAL_ALIGNMENT_LEFT, 34, 11, Color.WHITE)
    draw_string(get_theme_default_font(), pos + Vector2(7,-5), str(brigades), HORIZONTAL_ALIGNMENT_LEFT, 10, 9, Color("f6d68b"))

func _draw_terrain_symbol(index: int, resource: String) -> void:
    var c := province_centers[index] + Vector2(0, 12)
    var color := Color(0.10,0.13,0.10,0.42)
    match resource:
        "madera":
            draw_line(c + Vector2(0,-13), c + Vector2(0,8), color, 2.0)
            draw_colored_polygon(PackedVector2Array([c+Vector2(-9,0),c+Vector2(0,-17),c+Vector2(9,0)]), color)
        "hierro", "carbón":
            draw_polyline(PackedVector2Array([c+Vector2(-12,7),c+Vector2(-3,-9),c+Vector2(4,2),c+Vector2(10,-12),c+Vector2(15,7)]), color, 2.0)
        "cristal arcano":
            draw_colored_polygon(PackedVector2Array([c+Vector2(0,-13),c+Vector2(8,0),c+Vector2(0,13),c+Vector2(-8,0)]), Color(0.35,0.19,0.48,0.38))
        "grano":
            for dx in [-6.0,0.0,6.0]:
                draw_line(c+Vector2(dx,8), c+Vector2(dx,-8), color, 1.5)
                draw_line(c+Vector2(dx,-2), c+Vector2(dx+4,-6), color, 1.2)

func _gui_input(event: InputEvent) -> void:
    if not interactive:
        return

    if event is InputEventMouseMotion:
        var new_hover := _hit_test(event.position)
        if new_hover != hovered_index:
            hovered_index = new_hover
            queue_redraw()

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var army_hit := _army_hit_test(event.position)
        if army_hit >= 0:
            selected_army_id = army_hit
            army_selected.emit(army_hit)
            queue_redraw()
            return

        var hit := _hit_test(event.position)
        if hit >= 0:
            selected_index = hit
            province_selected.emit(hit)
            queue_redraw()

func _army_hit_test(point: Vector2) -> int:
    for army_id in army_positions:
        var pos: Vector2 = army_positions[army_id]
        if Rect2(pos - Vector2(22,16), Vector2(44,32)).has_point(point):
            return int(army_id)
    return -1

func _hit_test(point: Vector2) -> int:
    _ensure_geometry()
    for i in range(province_polygons.size()):
        if Geometry2D.is_point_in_polygon(point, province_polygons[i]):
            return i
    return -1
