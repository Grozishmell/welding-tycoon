extends Node2D

signal weld_finished(result: Dictionary)

const SAMPLE_STEP := 4.0

enum Q { MISS, POOR, GOOD, PERFECT }

# Параметры заказа
@export var seam_length: float = 3600.0
@export var scroll_speed: float =  190.0
@export var wave_amplitude: float = 34.0
@export var lead_in: float = 2.0
@export var tail: float = 0.8

@export_group("Допуски")
@export var perfect_tol: float = 6.0
@export var good_tol: float = 14.0
@export var poor_tol: float = 28.0

@export_group("Управление")
@export var use_mouse: bool = true
@export var keyboard_speed: float = 320.0
@export var control_smoothing: float = 16.0
@export var shake_amount: float = 0.0

@export_group("Геометрия")
@export var torch_x: float = 180.0
@export var center_y: float = 360.0
@export var plate_half_height: float = 220.0
@export var gap_half: float = 5.0

# Цвета
const C_PLATE := Color("#4a4f57")
const C_EDGE := Color("#2b2e33")
const C_GAP := Color("#141518")
const C_PERFECT := Color("#ffd166")
const C_GOOD := Color("#e8973c")
const C_POOR := Color("#8a6a4a")
const C_MISS := Color("#5c3b3b")
const C_ARC := Color("#dff3ff")
const C_MARKER := Color("#8ce99a")

var seam: PackedFloat32Array = PackedFloat32Array()
var quality: PackedByteArray = PackedByteArray()
var bead: PackedFloat32Array = PackedFloat32Array()

var scroll: float = 0.0
var torch_y: float = 0.0
var finished: bool = true

var combo: int = 0
var max_combo: int = 0

var _last_index: int = -1
var _shake: float = 0.0
var _hit_flash: float = 0.0
var _effective_tail: float = 0.8


func _ready() -> void:
	finished = true
	

func start(seam_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seam_seed
	
	var count := int(seam_length / SAMPLE_STEP) + 1
	seam.resize(count)
	quality.resize(count)
	bead.resize(count)
	
	# Стак - сумма трех синусоид. Дает органичную кривую без резких углов:
	# игрок должен успевать читать линию наперед, а не реагировать на рывки.
	var layers: Array[Vector3] = []
	for i in 3:
		layers.append(Vector3(
			wave_amplitude / float(i + 1) * rng.randf_range(0.6, 1.2), # амплитуда
			rng.randf_range(0.004, 0.009) * float(i + 1), # частота
			rng.randf_range(0.0, TAU) # фаза
		))
		
	for i in count:
		var x := float(i) * SAMPLE_STEP
		var y := 0.0
		for l in layers:
			y += l.x * sin(l.y * x + l.z)
		seam[i] = y
		quality[i] = Q.MISS
		bead[i] = 0.0
		
	# Шов всегда по центру экрана, независимо от разрешения
	center_y = get_viewport_rect().size.y * 0.5
	
	# Отрицательный scroll = разгон. Стык виден справа, но еще не дошел.
	scroll = -lead_in * scroll_speed
	torch_y = seam[0]
	combo = 0
	max_combo = 0
	_last_index = -1
	_hit_flash = 0.0
	finished = false
	_effective_tail = maxf(tail, torch_x / scroll_speed + 0.3)
	
	
func _process(delta: float) -> void:
	if finished:
		return
		
	scroll += scroll_speed * delta
	_update_torch(delta)
	_apply_weld()
	
	_hit_flash = maxf(_hit_flash - delta * 4.0, 0.0)
	
	if scroll >= seam_length + _effective_tail * scroll_speed:
		_finish()
		queue_redraw()
		return
		
	queue_redraw()
	

func _update_torch(delta: float) -> void:
	var target := torch_y
	
	if use_mouse:
		target = get_local_mouse_position().y - center_y
	else:
		target += Input.get_axis("torch_up", "torch_down") * keyboard_speed * delta
		
	# Сглаживание, независимое от FPS. Чем ниже control_smoothing,
	# тем инертнее горелка.
	var t := 1.0 - exp(-control_smoothing * delta)
	torch_y = lerp(torch_y, target, t)
		
	if shake_amount > 0.0:
		_shake += delta * 14.0
		torch_y += sin(_shake) * shake_amount * 0.6 + randf_range(-1.0, 1.0) * shake_amount * 0.4
			
	torch_y = clampf(torch_y, -plate_half_height, plate_half_height)
			
	
func _apply_weld() -> void:
	if scroll < 0.0:
		return
			
	var idx := clampi(int(scroll / SAMPLE_STEP), 0, seam.size() - 1)
	var from := maxi(_last_index + 1, 0)
	if from > idx:
		return
			
	# Проходим все семплы, проехавшие с прошлого кадра. Без этого
	# на просадках FPS в шве появлялись бы дыры.
	for i in range(from, idx + 1):
		var d := absf(torch_y - seam[i])
		var q := Q.MISS
			
		if d <= perfect_tol:
			q = Q.PERFECT
		elif d <= good_tol:
			q = Q.GOOD
		elif d <= poor_tol:
			q = Q.POOR
			
		quality[i] = q
		bead[i] = torch_y
			
		if q == Q.PERFECT or q == Q.GOOD:
			combo += 1
			max_combo = maxi(max_combo, combo)
		else:
			if combo > 12:
				_hit_flash = 1.0 # сбили длинную серию - подсветить
			combo = 0
		
	_last_index = idx


func _finish() -> void:
	finished = true
	
	var counts := {Q.MISS: 0, Q.POOR: 0, Q.GOOD: 0, Q.PERFECT: 0}
	for q in quality:
		counts[q] += 1
		
	var total := float(quality.size())
	var raw := (
		float(counts[Q.PERFECT]) * 1.0
		+ float(counts[Q.GOOD]) * 0.6
		+ float(counts[Q.POOR]) * 0.2
	) / total
	var score := clampf(raw, 0.0, 1.0)
	
	weld_finished.emit({
		"score": score,
		"grade": _grade(score),
		"perfect": counts[Q.PERFECT],
		"good": counts[Q.GOOD],
		"poor": counts[Q.POOR],
		"missed": counts[Q.MISS],
		"max_combo": max_combo,
		"total": int(total),
		"map": quality.duplicate()
	})
	

func _grade(score: float) -> String:
	if score >= 0.94: return "S"
	if score >= 0.82: return "A"
	if score >= 0.66: return "B"
	if score >= 0.45: return "C"
	return "D"
	

# Отрисовка
func _screen_x(i: int) -> float:
	return torch_x + (float(i) * SAMPLE_STEP - scroll)
	

func _draw() -> void:
	if seam.is_empty():
		return
		
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.07, 0.09, 0.82))
		
	var w := vp.x
	var i0 := clampi(int((scroll - torch_x) / SAMPLE_STEP) - 2, 0, seam.size() - 1)
	var i1 := clampi(int((scroll + (w - torch_x)) / SAMPLE_STEP) + 2, 0, seam.size() - 1)
	
	if i1 <= i0:
		_draw_torch()
		_draw_hud()
		return
	
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in range(i0, i1 + 1):
		var x := _screen_x(i)
		var y := center_y + seam[i]
		top.append(Vector2(x, y - gap_half))
		bot.append(Vector2(x, y + gap_half))
		
	# Зазор между листами
	var gap := PackedVector2Array()
	gap.append_array(top)
	for j in range(bot.size() - 1, -1, -1):
		gap.append(bot[j])
	draw_colored_polygon(gap, C_GAP)
	
	# Верхний лист
	var poly_top := top.duplicate()
	poly_top.append(Vector2(top[top.size() - 1].x, center_y - plate_half_height - 400.0))
	poly_top.append(Vector2(top[0].x, center_y - plate_half_height - 400.0))
	draw_colored_polygon(poly_top, C_PLATE)
	
	# Нижний лист
	var poly_bot := bot.duplicate()
	poly_bot.append(Vector2(bot[bot.size() - 1].x, center_y + plate_half_height + 400.0))
	poly_bot.append(Vector2(bot[0].x, center_y + plate_half_height + 400.0))
	draw_colored_polygon(poly_bot, C_PLATE)
	
	draw_polyline(top, C_EDGE, 2.0, true)
	draw_polyline(bot, C_EDGE, 2.0, true)
	
	# Метка начала шва - до нее можно спокойно целиться
	if scroll < SAMPLE_STEP * 4.0:
		var mx := _screen_x(0)
		draw_line(Vector2(mx, center_y - plate_half_height), Vector2(mx, center_y + plate_half_height), C_MARKER, 3.0)
	
	# Метка конца шва
	if scroll > seam_length - SAMPLE_STEP * 4.0:
		var ex := _screen_x(seam.size() - 1)
		draw_line(Vector2(ex, center_y - plate_half_height),
		Vector2(ex, center_y + plate_half_height), C_MARKER, 3.0)
		
	# Уже проваренный шов
	var b0 := clampi(i0, 0, seam.size() - 1)
	var b1 := clampi(i1, 0, seam.size() - 1)
	var done_to := clampi(_last_index, -1, seam.size() - 1)
	for i in range(b0, mini(b1, done_to) + 1):
		var pos := Vector2(_screen_x(i), center_y + bead[i])
		match quality[i]:
			Q.PERFECT: draw_circle(pos, 6.0, C_PERFECT)
			Q.GOOD: draw_circle(pos, 5.0, C_GOOD)
			Q.POOR: draw_circle(pos, 4.0, C_POOR)
			Q.MISS: draw_circle(pos, 4.0, C_MISS)
			
	_draw_torch()
	_draw_hud()


func _draw_torch() -> void:
	if scroll >= seam_length:
		return
	
	var tip := Vector2(torch_x, center_y + torch_y)
	
	# Дуга горит всегда - свечение тем ярче, чем точнее попадание
	var accuracy := 0.0
	if scroll >= 0.0:
		var idx := clampi(int(scroll / SAMPLE_STEP), 0, seam.size() - 1)
		var d := absf(torch_y - seam[idx])
		accuracy = clampf(1.0 -d / poor_tol, 0.0, 1.0)
	
	var glow := C_ARC
	glow.a = 0.10 + 0.20 * accuracy
	draw_circle(tip, 22.0 + 10.0 * accuracy, glow)
	draw_circle(tip, 7.0 + 3.0 * accuracy, C_ARC)
	
	draw_line(tip + Vector2(14.0, -46.0), tip, Color("#c8ccd2"), 6.0)
	draw_circle(tip, 3.0, Color.WHITE)
	

func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	
	# Прогресс шва
	var prog := Rect2(24.0, 24.0, 220.0, 8.0)
	draw_rect(prog, Color(0, 0, 0, 0.45))
	var done := clampf(scroll / seam_length, 0.0, 1.0)
	draw_rect(Rect2(prog.position, Vector2(prog.size.x * done, prog.size.y)), Color("#9aa1ab"))
	
	# Комбо
	if combo > 12:
		draw_string(font, Vector2(24.0, 68.0), "%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, C_PERFECT)
		draw_string(font, Vector2(24.0, 90.0), "подряд", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#9aa1ab"))
	elif _hit_flash > 0.0:
		var c := C_MISS
		c.a = _hit_flash
		draw_string(font, Vector2(24.0, 68.0), "серия сбита", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, c)
		
	# Подсказка на разгоне
	if scroll < 0.0:
		var w := get_viewport_rect().size.x
		draw_string(font, Vector2(0.0, center_y - plate_half_height -30.0), "ведите горелку по стыку", HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color("#9aa1ab"))
