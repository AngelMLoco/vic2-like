class_name VMapCamera
extends Camera2D
## Cámara del mapa: zoom suave con la rueda (hacia el cursor), paneo arrastrando
## (botón izquierdo, central o derecho), WASD/flechas, desplazamiento por bordes,
## centrado animado en provincias/países y límites de zoom y de mapa.

signal clicked(world_pos: Vector2)
signal right_clicked(world_pos: Vector2)
signal hovered(world_pos: Vector2)
signal view_changed

const DRAG_THRESHOLD := 6.0
const ZOOM_STEP := 1.18
const EDGE_MARGIN := 6.0

var map_size := Vector2(5632, 2624)
var min_zoom: float = 0.3
var max_zoom: float = 8.0
var target_zoom: float = 1.0
var _zoom_anchor_screen := Vector2.ZERO
var _zoom_anchor_world := Vector2.ZERO
var _anchored := false
var _dragging := false
var _drag_button := 0
var _press_pos := Vector2.ZERO
var _moved := false
var _goto_target := Vector2.ZERO
var _goto_active := false
var input_enabled := true


func setup(size: Vector2) -> void:
	map_size = size
	position_smoothing_enabled = false
	_update_min_zoom()
	target_zoom = max(min_zoom * 1.6, 0.55)
	zoom = Vector2.ONE * target_zoom
	position = map_size * Vector2(0.52, 0.32)
	get_viewport().size_changed.connect(_update_min_zoom)


func _update_min_zoom() -> void:
	var vs := get_viewport_rect().size
	min_zoom = max(vs.x / map_size.x, vs.y / map_size.y) * 1.001
	target_zoom = clamp(target_zoom, min_zoom, max_zoom)


func current_zoom() -> float:
	return zoom.x


func center_on(world_pos: Vector2, new_zoom: float = -1.0) -> void:
	_goto_target = world_pos
	_goto_active = true
	_anchored = false
	if new_zoom > 0.0:
		target_zoom = clamp(new_zoom, min_zoom, max_zoom)


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if mb.pressed:
				_dragging = true
				_drag_button = mb.button_index
				_press_pos = mb.position
				_moved = false
				_goto_active = false
			elif _dragging and mb.button_index == _drag_button:
				_dragging = false
				if not _moved:
					var wp := screen_to_world(mb.position)
					if mb.button_index == MOUSE_BUTTON_LEFT:
						clicked.emit(wp)
					elif mb.button_index == MOUSE_BUTTON_RIGHT:
						right_clicked.emit(wp)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			if not _moved and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_moved = true
			if _moved:
				position -= mm.relative / zoom.x
				_anchored = false
				_clamp()
				view_changed.emit()
		hovered.emit(screen_to_world(mm.position))


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	_zoom_anchor_screen = screen_pos
	_zoom_anchor_world = screen_to_world(screen_pos)
	_anchored = true
	_goto_active = false
	target_zoom = clamp(target_zoom * factor, min_zoom, max_zoom)


func _process(delta: float) -> void:
	var changed := false
	var speed_mult := float(App.settings.get("camera_speed", 1.0))
	# zoom suave
	if abs(zoom.x - target_zoom) > 0.0005:
		var z: float = lerp(zoom.x, target_zoom, clamp(delta * 12.0, 0.0, 1.0))
		if abs(z - target_zoom) < 0.0008:
			z = target_zoom
		zoom = Vector2(z, z)
		if _anchored:
			# mantener bajo el cursor el punto del mundo que estaba bajo él
			var vs := get_viewport_rect().size
			position = _zoom_anchor_world - (_zoom_anchor_screen - vs * 0.5) / z
		changed = true
	elif _anchored:
		_anchored = false
	# teclado
	var dir := Vector2.ZERO
	if input_enabled and not _focus_is_text():
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir.y += 1
	# bordes de pantalla
	if input_enabled and App.settings.get("edge_scroll", true) and not _dragging and DisplayServer.window_is_focused():
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if Rect2(Vector2.ZERO, vs).has_point(mp):
			if mp.x <= EDGE_MARGIN:
				dir.x -= 1
			elif mp.x >= vs.x - EDGE_MARGIN:
				dir.x += 1
			if mp.y <= EDGE_MARGIN:
				dir.y -= 1
			elif mp.y >= vs.y - EDGE_MARGIN:
				dir.y += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * 900.0 * speed_mult * delta / zoom.x
		_goto_active = false
		_anchored = false
		changed = true
	if _goto_active:
		position = position.lerp(_goto_target, clamp(delta * 7.0, 0.0, 1.0))
		if position.distance_to(_goto_target) < 0.5 / zoom.x:
			position = _goto_target
			_goto_active = false
		changed = true
	if changed:
		_clamp()
		view_changed.emit()


func _focus_is_text() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _clamp() -> void:
	var half := get_viewport_rect().size * 0.5 / zoom.x
	position.x = clamp(position.x, half.x, max(half.x, map_size.x - half.x))
	position.y = clamp(position.y, half.y, max(half.y, map_size.y - half.y))


## Rectángulo visible en coordenadas del mundo.
func visible_rect() -> Rect2:
	var half := get_viewport_rect().size * 0.5 / zoom.x
	return Rect2(position - half, half * 2.0)
