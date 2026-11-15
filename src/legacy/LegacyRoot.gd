extends Node
## Envoltorio del Modo A (prototipo actual). No modifica su lógica:
## solo instancia la escena original y añade un acceso para volver al menú principal.

const LEGACY_SCENE := preload("res://src/legacy/LegacyMain.tscn")


func _ready() -> void:
	add_child(LEGACY_SCENE.instantiate())
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var b := Button.new()
	b.text = "« Menú principal"
	b.tooltip_text = "Volver al menú principal (Ctrl+M)"
	b.theme = UiTheme.get_theme()
	b.add_theme_font_size_override("font_size", 12)
	b.anchor_left = 0.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = 6
	b.offset_top = -30
	b.offset_bottom = -6
	b.offset_right = 140
	b.pressed.connect(App.goto_main_menu)
	layer.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M and event.ctrl_pressed:
		App.goto_main_menu()
