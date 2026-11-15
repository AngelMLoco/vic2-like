class_name VTimeController
extends Node
## Reloj del juego: pausa y velocidades 1–5 al estilo Victoria II.
## Emite day_passed / month_passed; la simulación se ejecuta por ticks diarios.

signal day_passed
signal month_passed
signal state_changed(paused: bool, speed: int)

## Segundos reales por día de juego para cada velocidad (5 = tan rápido como permita el cuadro).
const SECONDS_PER_DAY := [0.0, 1.0, 0.5, 0.22, 0.09, 0.0]
const MAX_DAYS_PER_FRAME := 2

var date: VDate
var paused: bool = true
var speed: int = 2
var _acc: float = 0.0


func setup(game_date: VDate) -> void:
	date = game_date


func toggle_pause() -> void:
	set_paused(not paused)


func set_paused(value: bool) -> void:
	paused = value
	_acc = 0.0
	state_changed.emit(paused, speed)


func set_speed(value: int) -> void:
	speed = clampi(value, 1, 5)
	state_changed.emit(paused, speed)


func faster() -> void:
	set_speed(speed + 1)


func slower() -> void:
	set_speed(speed - 1)


func _process(delta: float) -> void:
	if paused or date == null:
		return
	var spd: float = SECONDS_PER_DAY[speed]
	if spd <= 0.0:
		for i in MAX_DAYS_PER_FRAME:
			_tick()
		return
	_acc += delta
	var n := 0
	while _acc >= spd and n < MAX_DAYS_PER_FRAME:
		_acc -= spd
		n += 1
		_tick()
	if n >= MAX_DAYS_PER_FRAME:
		_acc = 0.0


func _tick() -> void:
	var new_month := date.advance_day()
	day_passed.emit()
	if new_month:
		month_passed.emit()
