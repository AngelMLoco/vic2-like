class_name VDate
extends RefCounted
## Fecha del calendario de juego (año, mes, día). Calendario de 12 meses tipo gregoriano sin bisiestos.

const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const MONTH_NAMES := ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
	"septiembre", "octubre", "noviembre", "diciembre"]

var year: int = 136
var month: int = 1
var day: int = 1


static func make(y: int, m: int, d: int) -> VDate:
	var dt := VDate.new()
	dt.year = y
	dt.month = m
	dt.day = d
	return dt


static func from_dict(d: Dictionary) -> VDate:
	return make(int(d.get("year", 136)), int(d.get("month", 1)), int(d.get("day", 1)))


func to_dict() -> Dictionary:
	return {"year": year, "month": month, "day": day}


## Avanza un día. Devuelve true si comienza un mes nuevo.
func advance_day() -> bool:
	day += 1
	if day > MONTH_DAYS[month - 1]:
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
		return true
	return false


## Número absoluto de días desde el año 0 (para comparar fechas y calcular duraciones).
func ordinal() -> int:
	var total := year * 365
	for m in range(month - 1):
		total += MONTH_DAYS[m]
	return total + day - 1


func text() -> String:
	return "%d de %s de %d" % [day, MONTH_NAMES[month - 1], year]


func short_text() -> String:
	return "%d %s %d" % [day, MONTH_NAMES[month - 1].substr(0, 3), year]
