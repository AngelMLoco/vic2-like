class_name VMinimap
extends Control
## Minimapa: imagen reducida del mapmode activo con el rectángulo de vista.
## Clic o arrastre reposiciona la cámara.

signal navigate(world_pos: Vector2)

const W := 336

var gs: VGameState
var map_size := Vector2.ONE
var _ids := PackedInt32Array()
var _h: int = 1
var _img: Image
var _tex: ImageTexture
var _view := Rect2()
var _dragging := false


func setup(state: VGameState, id_image: Image) -> void:
	gs = state
	map_size = Vector2(gs.map_width, gs.map_height)
	_h = int(round(W * map_size.y / map_size.x))
	custom_minimum_size = Vector2(W, _h)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ids.resize(W * _h)
	for y in _h:
		var sy := int((y + 0.5) * map_size.y / _h)
		for x in W:
			var sx := int((x + 0.5) * map_size.x / W)
			var c := id_image.get_pixel(sx, sy)
			_ids[y * W + x] = int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256
	_img = Image.create(W, _h, false, Image.FORMAT_RGB8)
	_tex = ImageTexture.create_from_image(_img)


func recolor(colors: PackedColorArray) -> void:
	var sea := Color("22384a")
	for i in _ids.size():
		var id := _ids[i]
		var c: Color = sea
		if id > 0 and id < gs.first_sea_id:
			c = colors[id]
		elif id >= gs.first_sea_id and id < colors.size() and colors[id].a > 0.5:
			c = sea.lerp(colors[id], 0.5)
		_img.set_pixel(i % W, i / W, c)
	_tex.update(_img)
	queue_redraw()


func set_view(world_rect: Rect2) -> void:
	_view = world_rect
	queue_redraw()


func _draw() -> void:
	if _tex:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	var s := size / map_size
	var r := Rect2(_view.position * s, _view.size * s)
	draw_rect(r, Color(1, 0.9, 0.6, 0.12), true)
	draw_rect(r, Color(1, 0.9, 0.6, 0.95), false, 1.5)
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.GOLD, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_emit(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_emit(event.position)
		accept_event()


func _emit(local: Vector2) -> void:
	navigate.emit(Vector2(clamp(local.x / size.x, 0.0, 1.0), clamp(local.y / size.y, 0.0, 1.0)) * map_size)
