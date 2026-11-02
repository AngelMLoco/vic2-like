extends Control

signal province_selected(index: int)

var provinces: Array = []
var country_colors: Dictionary = {}
var province_polygons: Array[PackedVector2Array] = []
var selected_index: int = -1
var hovered_index: int = -1
var interactive: bool = true
var show_country_labels: bool = true
var show_province_names: bool = true
var compact_mode: bool = false
var _last_size := Vector2.ZERO

const SEA := Color("496b78")
const SEA_DARK := Color("294852")
const INK := Color("2a211b")
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

func set_selected(index: int) -> void:
    selected_index = index
    queue_redraw()

func _on_resized() -> void:
    _last_size = Vector2.ZERO
    _ensure_geometry()
    queue_redraw()

func _ensure_geometry() -> void:
    if size.x <= 4.0 or size.y <= 4.0:
        return
    if _last_size == size and province_polygons.size() == 30:
        return
    _last_size = size
    province_polygons.clear()

    var centers := [
        Vector2(0.16,0.17), Vector2(0.29,0.14), Vector2(0.43,0.15), Vector2(0.57,0.16), Vector2(0.71,0.17), Vector2(0.83,0.21),
        Vector2(0.12,0.32), Vector2(0.26,0.31), Vector2(0.40,0.31), Vector2(0.55,0.32), Vector2(0.70,0.33), Vector2(0.84,0.35),
        Vector2(0.10,0.48), Vector2(0.24,0.47), Vector2(0.39,0.47), Vector2(0.54,0.48), Vector2(0.69,0.49), Vector2(0.85,0.50),
        Vector2(0.13,0.64), Vector2(0.28,0.63), Vector2(0.43,0.63), Vector2(0.58,0.64), Vector2(0.73,0.64), Vector2(0.86,0.65),
        Vector2(0.20,0.79), Vector2(0.34,0.79), Vector2(0.49,0.80), Vector2(0.63,0.79), Vector2(0.76,0.78), Vector2(0.88,0.77)
    ]

    var rx := size.x * (0.068 if not compact_mode else 0.065)
    var ry := size.y * (0.105 if not compact_mode else 0.10)

    for i in range(30):
        var center: Vector2 = centers[i] * size
        var wobble := float((i * 37) % 9 - 4)
        var pts := PackedVector2Array([
            center + Vector2(-rx * 0.90, -ry * 0.28 + wobble),
            center + Vector2(-rx * 0.48, -ry * 0.88),
            center + Vector2( rx * 0.36, -ry * 0.94 + wobble * 0.3),
            center + Vector2( rx * 0.92, -ry * 0.30),
            center + Vector2( rx * 0.78,  ry * 0.48 + wobble * 0.2),
            center + Vector2( rx * 0.18,  ry * 0.92),
            center + Vector2(-rx * 0.56,  ry * 0.82 - wobble * 0.2),
            center + Vector2(-rx * 0.98,  ry * 0.25)
        ])
        province_polygons.append(pts)

func _draw() -> void:
    _ensure_geometry()
    draw_rect(Rect2(Vector2.ZERO, size), SEA)

    # Carta náutica: bandas y rejilla muy sutiles.
    for y in range(0, int(size.y), maxi(28, int(size.y / 18.0))):
        draw_line(Vector2(0,y), Vector2(size.x,y), PAPER_LINE, 1.0)
    for x in range(0, int(size.x), maxi(36, int(size.x / 22.0))):
        draw_line(Vector2(x,0), Vector2(x,size.y), PAPER_LINE, 1.0)

    # Sombras costeras.
    for poly in province_polygons:
        var shadow := PackedVector2Array()
        for p in poly:
            shadow.append(p + Vector2(3,4))
        draw_colored_polygon(shadow, Color(0.08,0.12,0.12,0.35))

    for i in range(mini(province_polygons.size(), provinces.size())):
        var p: Dictionary = provinces[i]
        var owner := String(p.get("owner", ""))
        var fill: Color = country_colors.get(owner, Color("777777"))
        fill = fill.darkened(0.10)

        if i == selected_index:
            fill = fill.lightened(0.24)
        elif i == hovered_index:
            fill = fill.lightened(0.12)

        draw_colored_polygon(province_polygons[i], fill)
        draw_polyline(province_polygons[i] + PackedVector2Array([province_polygons[i][0]]), BORDER, 1.6 if not compact_mode else 1.0, true)

        if not compact_mode:
            _draw_terrain_symbol(i, String(p.get("resource", "")))
            if show_province_names and size.x > 700:
                var center := _poly_center(province_polygons[i])
                var name := String(p.get("name", ""))
                draw_string(get_theme_default_font(), center + Vector2(-34, 33), name, HORIZONTAL_ALIGNMENT_CENTER, 68, 12, Color(0.12,0.10,0.08,0.72))

    if show_country_labels and not compact_mode:
        var sums := {}
        var counts := {}
        for i in range(mini(province_polygons.size(), provinces.size())):
            var owner := String(provinces[i].get("owner", ""))
            sums[owner] = sums.get(owner, Vector2.ZERO) + _poly_center(province_polygons[i])
            counts[owner] = int(counts.get(owner, 0)) + 1

        for owner in sums:
            var pos: Vector2 = sums[owner] / float(counts[owner])
            var label := String(owner)
            draw_string(get_theme_default_font(), pos + Vector2(-70, 4), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 25, Color("2c211a"))

    if selected_index >= 0 and selected_index < provinces.size() and not compact_mode:
        var selected_center := _poly_center(province_polygons[selected_index])
        draw_circle(selected_center, 7.0, Color("f0d789"))
        draw_circle(selected_center, 4.0, Color("6e1d23"))

func _draw_terrain_symbol(index: int, resource: String) -> void:
    var c := _poly_center(province_polygons[index]) + Vector2(0, 12)
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
        var hit := _hit_test(event.position)
        if hit >= 0:
            selected_index = hit
            province_selected.emit(hit)
            queue_redraw()

func _hit_test(point: Vector2) -> int:
    _ensure_geometry()
    for i in range(province_polygons.size()):
        if Geometry2D.is_point_in_polygon(point, province_polygons[i]):
            return i
    return -1

func _poly_center(poly: PackedVector2Array) -> Vector2:
    var total := Vector2.ZERO
    for p in poly:
        total += p
    return total / float(maxi(1, poly.size()))
