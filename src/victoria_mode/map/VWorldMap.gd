class_name VWorldMap
extends Node2D
## Renderizado del mapamundi: un único sprite con el mapa de IDs y un shader que
## colorea cada provincia a partir de texturas de consulta (LUT). Cambiar de mapmode o de
## propietario solo reescribe LUTs pequeñas (256 x N); la geometría nunca se modifica.

## M6: el mapa de IDs sale del mundo activo (gs.world_root + map/provinces.png).
const LUT_W := 256

var gs: VGameState
var sprite: Sprite2D
var material_map: ShaderMaterial
var id_image: Image
var mode: String = "political"
var focus_tag: String = ""
var colors := PackedColorArray()

var _lut_h: int = 1
var _color_img: Image
var _info_img: Image
var _overlay_img: Image
var _color_tex: ImageTexture
var _info_tex: ImageTexture
var _overlay_tex: ImageTexture
var _time: float = 0.0


func setup(state: VGameState) -> void:
	gs = state
	id_image = load_id_image(gs.world_root + "map/provinces.png")
	var tex := ImageTexture.create_from_image(id_image)
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material_map = ShaderMaterial.new()
	material_map.shader = load("res://src/victoria_mode/map/world_map.gdshader")
	sprite.material = material_map
	add_child(sprite)
	# M6: mundos con wrap_x (world.json) dibujan copias a izquierda y derecha; el picking ya usa posmod
	if gs.wrap_x:
		for dx in [-gs.map_width, gs.map_width]:
			var copy := Sprite2D.new()
			copy.texture = tex
			copy.centered = false
			copy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			copy.material = material_map
			copy.position = Vector2(dx, 0)
			add_child(copy)
	_lut_h = int(ceil(float(gs.max_id + 1) / LUT_W))
	_color_img = Image.create(LUT_W, _lut_h, false, Image.FORMAT_RGBA8)
	_info_img = Image.create(LUT_W, _lut_h, false, Image.FORMAT_RGBA8)
	_overlay_img = Image.create(LUT_W, _lut_h, false, Image.FORMAT_RGBA8)
	_color_tex = ImageTexture.create_from_image(_color_img)
	_info_tex = ImageTexture.create_from_image(_info_img)
	_overlay_tex = ImageTexture.create_from_image(_overlay_img)
	material_map.set_shader_parameter("id_map", tex)
	material_map.set_shader_parameter("color_lut", _color_tex)
	material_map.set_shader_parameter("info_lut", _info_tex)
	material_map.set_shader_parameter("overlay_lut", _overlay_tex)
	material_map.set_shader_parameter("map_size", Vector2(gs.map_width, gs.map_height))
	material_map.set_shader_parameter("first_sea_id", gs.first_sea_id)
	refresh_all()


## El PNG de IDs se importa con "keep" (se exporta sin conversión) y se lee como Image,
## para poder hacer picking por píxel en CPU y crear la textura sin pérdidas.
static func load_id_image(path: String = "") -> Image:
	if path == "":
		path = VWorlds.default_map_texture()
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		push_error("VWorldMap: no se pudo leer %s" % path)
		img = Image.create(16, 16, false, Image.FORMAT_RGB8)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img


func map_size() -> Vector2:
	return Vector2(gs.map_width, gs.map_height)


func _process(delta: float) -> void:
	_time += delta
	material_map.set_shader_parameter("time_s", _time)


# ------------------------------------------------------------ actualización
func refresh_all() -> void:
	refresh_info()
	refresh_colors()
	refresh_overlay()


func set_mode(new_mode: String, focus: String = "") -> void:
	mode = new_mode
	focus_tag = focus
	refresh_colors()


func refresh_colors() -> void:
	colors = VMapModes.compute(gs, mode, focus_tag)
	for id in range(1, gs.max_id + 1):
		_color_img.set_pixel(id % LUT_W, id / LUT_W, colors[id])
	_color_tex.update(_color_img)


## Propietario y estado por provincia (para fronteras nacionales y estatales).
func refresh_info() -> void:
	for id in range(1, gs.max_id + 1):
		var p: Dictionary = gs.provinces[id]
		var own := gs.country_index(p["owner"]) if id < gs.first_sea_id else 0
		var st := int(p["state"]) if id < gs.first_sea_id else 0
		_info_img.set_pixel(id % LUT_W, id / LUT_W, Color8(own & 255, own >> 8, st & 255, st >> 8))
	_info_tex.update(_info_img)


## Rayado de ocupación: provincias cuyo controlador no es el propietario.
func refresh_overlay() -> void:
	for id in range(1, gs.max_id + 1):
		var c := Color(0, 0, 0, 0)
		if id < gs.first_sea_id:
			var p: Dictionary = gs.provinces[id]
			if p["controller"] != p["owner"]:
				c = gs.country_color(p["controller"]) if p["controller"] != "" else Color(0.2, 0.2, 0.2)
				c.a = 1.0
		_overlay_img.set_pixel(id % LUT_W, id / LUT_W, c)
	_overlay_tex.update(_overlay_img)


func set_border_alphas(province_alpha: float, state_alpha: float) -> void:
	material_map.set_shader_parameter("province_border_alpha", province_alpha)
	material_map.set_shader_parameter("state_border_alpha", state_alpha)


func set_selected(id: int, owner_tag: String = "") -> void:
	material_map.set_shader_parameter("selected_id", id)
	material_map.set_shader_parameter("selected_owner", gs.country_index(owner_tag) if owner_tag != "" else -1)


func set_hover(id: int) -> void:
	material_map.set_shader_parameter("hover_id", id)


# ------------------------------------------------------------------ picking
func province_at(world_pos: Vector2) -> int:
	var local := to_local(world_pos)
	var x := int(floor(local.x))
	var y := int(floor(local.y))
	if y < 0 or y >= gs.map_height:
		return 0
	x = posmod(x, gs.map_width)
	var c := id_image.get_pixel(x, y)
	return int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256
