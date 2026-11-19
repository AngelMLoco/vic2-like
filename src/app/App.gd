extends Node
## Autoload "App": enrutador de escenas y opciones globales.
##
## Mantiene separados los dos modos de juego:
##   - Modo A "Prototipo actual" (src/legacy/), congelado como referencia.
##   - Modo B "Segunda versión" (src/victoria_mode/), reconstrucción estilo Victoria II.

const SCENE_MAIN_MENU := "res://src/app/MainMenu.tscn"
const SCENE_LEGACY := "res://src/legacy/LegacyRoot.tscn"
const SCENE_VICTORIA := "res://src/victoria_mode/VictoriaGame.tscn"
const SETTINGS_PATH := "user://settings.cfg"

## Partida de la Segunda versión que debe cargarse al abrir el modo (ruta de save o "").
var pending_victoria_save: String = ""
## M6: escenario elegido en el selector (vacío = el de por defecto). El escenario elige el mundo.
var pending_victoria_scenario: String = ""

var settings := {
	"ui_scale": 1.0,
	"edge_scroll": true,
	"fullscreen": false,
	"camera_speed": 1.0,
}


func _ready() -> void:
	_load_settings()
	_apply_settings()


func goto_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)


func start_legacy() -> void:
	get_tree().change_scene_to_file(SCENE_LEGACY)


func start_victoria(save_path: String = "", scenario_id: String = "") -> void:
	pending_victoria_save = save_path
	pending_victoria_scenario = scenario_id
	get_tree().change_scene_to_file(SCENE_VICTORIA)


func quit_game() -> void:
	get_tree().quit()


func set_setting(key: String, value) -> void:
	settings[key] = value
	_apply_settings()
	_save_settings()


func _apply_settings() -> void:
	var win := get_window()
	if win:
		win.content_scale_factor = float(settings.get("ui_scale", 1.0))
	if settings.get("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key in settings.keys():
		settings[key] = cfg.get_value("general", key, settings[key])


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings.keys():
		cfg.set_value("general", key, settings[key])
	cfg.save(SETTINGS_PATH)
