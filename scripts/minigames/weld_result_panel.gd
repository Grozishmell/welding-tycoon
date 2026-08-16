extends Control

signal continue_pressed

enum Q { MISS, POOR, GOOD, PERFECT }

const C_PERFECT := Color("#ffd166")
const C_GOOD := Color("#e8973c")
const C_POOR := Color("#8a6a4a")
const C_MISS := Color("#5c3b3b")
const C_BG := Color("#1b1d21")
const C_BORDER := Color("#3a3f46")
const C_TEXT := Color("#e6e9ed")
const C_MUTED := Color("#9aa1ab")

## Защита от случайного закрытия кнопкой, которую игрок еще держал с мини-игры
const INPUT_LOCK := 0.45

var _result: Dictionary = {}
var _age: float = 0.0


func _ready() -> void:
	visible = false
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_STOP
	

func show_result(result: Dictionary) -> void:
	_result = result
	_age = 0.0
	visible = true
	set_process(true)
	queue_redraw()
	

func _process(delta: float) -> void:
	_age += delta
	if _age > INPUT_LOCK:
		set_process(false)
		queue_redraw()
		

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _age <= INPUT_LOCK:
		return
		
	var accept := false
	if event is InputEventKey and event.pressed and not event.echo:
		accept = true
	elif event is InputEventMouseButton and event.pressed:
		accept = true
	
	if accept:
		get_viewport().set_input_as_handled()
		visible = false
		continue_pressed.emit()
		

# Отрисовка

func _q_color(q: int) -> Color:
	match q:
		Q.PERFECT: return C_PERFECT
		Q.GOOD: return C_GOOD
		Q.POOR: return C_POOR
		_: return C_MISS
		

func _grade_color(grade: String) -> Color:
	match grade:
		"S": return Color("#ffd166")
		"A": return Color("#8ce99a")
		"B": return Color("#74c0fc")
		"C": return Color("#ffa94d")
		_: return Color("#ff6b6b")
		

func _draw() -> void:
	if _result.is_empty():
		return
		
	var font := ThemeDB.fallback_font
	var vp := size
	
	# Затемнение фона
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.75))
	
	var panel_size := Vector2(700.0, 430.0)
	var panel := Rect2((vp - panel_size) * 0.5, panel_size)
	draw_rect(panel, C_BG)
	draw_rect(panel, C_BORDER, false, 2.0)
	
	var o := panel.position
	
	draw_string(font, o + Vector2(36.0, 54.0), "ШОВ ЗАВЕРШЁН", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_MUTED)
	
	# Оценка и процент
	var grade: String = _result.get("grade", "?")
	draw_string(font, o + Vector2(36.0, 132.0), grade, HORIZONTAL_ALIGNMENT_LEFT, -1, 76, _grade_color(grade))
	
	var pct := roundi(float(_result.get("score", 0.0)) * 100.0)
	draw_string(font, o + Vector2(140.0, 132.0), "%d%%" % pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, C_TEXT)
	
	draw_string(font, o + Vector2(140.0, 160.0), "качество провара", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_MUTED)
	
	# Карта шва
	draw_string(font, o + Vector2(36.0, 200.0), "КАРТА ШВА", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_MUTED)
	
	var bar := Rect2(o + Vector2(36.0, 212.0), Vector2(panel_size.x - 72.0, 46.0))
	draw_rect(bar, C_MISS)
	
	var map: PackedByteArray = _result.get("map", PackedByteArray())
	if map.size() > 0:
		var step := bar.size.x / float(map.size())
		for i in map.size():
			draw_rect(Rect2(
				bar.position.x + float(i) * step, bar.position.y, step + 1.0, bar.size.y
			), _q_color(map[i]))
			
	draw_rect(bar, C_BORDER, false, 2.0)
	
	# Легенда со статистикой
	var total := maxf(1.0, float(_result.get("total", 1)))
	var rows := [
		["Отличный провар", _result.get("perfect", 0), C_PERFECT],
		["Приемлемо", _result.get("good", 0), C_GOOD],
		["Слабый провар", _result.get("poor", 0), C_POOR],
		["Непровар", _result.get("missed", 0), C_MISS]
	]
	
	var y := 296.0
	for row in rows:
		var label: String = row[0]
		var count: int = row[1]
		var color: Color = row[2]
		
		draw_rect(Rect2(o + Vector2(36.0, y - 11.0), Vector2(14.0, 14.0)), color)
		draw_string(font, o + Vector2(60.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, C_TEXT)
		draw_string(font, o + Vector2(300.0, y), "%.0f%%" % (float(count) / total * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 100, 17, C_MUTED)
		y += 26.0
		
	# Лучшая серия - главная цель для перепрохождения
	draw_string(font, o + Vector2(panel_size.x - 250.0, 296.0), "ЛУЧШАЯ СЕРИЯ", HORIZONTAL_ALIGNMENT_RIGHT, 214.0, 15, C_MUTED)
	draw_string(font, o + Vector2(panel_size.x -250.0, 338.0), "%d" % _result.get("max_combo", 0), HORIZONTAL_ALIGNMENT_RIGHT, 214.0, 34, C_PERFECT)
		
	if _age > INPUT_LOCK:
		draw_string(font, o + Vector2(0.0, panel_size.y -22.0), "Нажмите любую клавишу", HORIZONTAL_ALIGNMENT_CENTER, panel_size.x, 16, C_MUTED)
