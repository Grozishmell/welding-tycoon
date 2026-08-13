extends Node2D

signal weld_finished(result: Dictionary)

const SAMPLE_STEP := 4.0

enum Q { EMPTY, PERFECT, GOOD, POOR, BURN }

# Параметры заказа
@export var seam_length: float = 3600.0
@export var scroll_speed: float = 190.0
@export var wave_amplitude: float = 34.0
@export var perfect_tol: float = 6.0
@export var good_tol: float = 14.0
@export var poor_tol: float = 28.0

# Нагрев
@export var heat_gain: float = 52.0
@export var heat_loss: float = 95.0
@export var burn_threshold: float = 100.0

# Управление
@export var use_mouse: bool = true
@export var keyboard_speed: float = 320.0
@export var control_smoothing: float = 16.0
@export var shake_amount: float = 0.0

# Геометрия
@export var torch_x: float = 260.0
@export var center_y: float = 320.0
@export var plate_half_height: float = 220.0
@export var gap_half: float = 5.0

# Цвета
const C_PLATE := Color("#4a4f57")
const C_EDGE := Color("#2b2e33")
const C_GAP := Color("#141518")
const C_PERFECT := Color("#ffd166")
const C_GOOD := Color("#c98b31")
const C_POOR := Color("#7a6047")
const C_BURN := Color("#000000")
const C_ARC := Color("#dff3ff")

var seam: PackedFloat32Array = PackedFloat32Array()
var quality: PackedByteArray = PackedByteArray()
var bead: PackedFloat32Array = PackedFloat32Array()

var scroll: float = 0.0
var torch_y: float = 0.0
var heat: float = 0.0
var welding: bool = false
var finished: bool = true
var _last_index: int = 0
var _shake: float = 0.0


func _ready() -> void:
	finished = true
	

func start(seam_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seam_seed
	
	var count := int(seam_length / SAMPLE_STEP) + 1
	seam.resize(count)
	quality.resize(count)
	bead.resize(count)
	
	var layers: Array[Vector3] = []
	for i in 3:
		layers.append(Vector3(
			wave_amplitude / float(i + 1) * rng.randf_range(0.6, 1.2),
			rng.randf_range(0.004, 0.009) * float(i + 1),
			rng.randf_range(0.0, TAU) 
		))
		
	for i in count:
		var x := float(i) * SAMPLE_STEP
		var y := 0.0
		for l in layers:
			y += l.x * sin(l.y * x + l.z)
		seam[i] = y
		quality[i] = Q.EMPTY
		bead[i] = 0.0
		
	center_y = get_viewport_rect().size.y * 0.5
	
	scroll = 0.0
	heat = 0.0
	torch_y = seam[0]
	_last_index = 0
	finished = false
	queue_redraw()
	

func _process(delta: float) -> void:
	if finished:
		return
	
	scroll += scroll_speed * delta
	welding = Input.is_action_pressed("weld")
	
	_update_torch(delta)
	_update_heat(delta)
	_apply_weld()
	
	if scroll >= seam_length:
		_finish()
		
	queue_redraw()
	

func _update_torch(delta: float) -> void:
	var target := torch_y
	
	if use_mouse:
		target = get_local_mouse_position().y - center_y
	else:
		target += Input.get_axis("torch_up", "torch_down") * keyboard_speed * delta
		
	var t := 1.0 - exp(-control_smoothing * delta)
	torch_y = lerp(torch_y, target, t)
		
	if shake_amount > 0.0:
		_shake += delta * 14.0
		torch_y += sin(_shake) * shake_amount * 0.6 + randf_range(-1.0, 1.0) * shake_amount * 0.4
			
	torch_y = clampf(torch_y, -plate_half_height, plate_half_height)
			
	
func _update_heat(delta: float) -> void:
	if welding:
		heat = minf(heat + heat_gain * delta, burn_threshold * 1.4)
	else:
		heat = maxf(heat - heat_loss * delta, 0.0)
		

func _apply_weld() -> void:
	var idx := clampi(int(scroll / SAMPLE_STEP), 0, seam.size() - 1)
	
	if not welding:
		_last_index = idx
		return
		
	var burning := heat >= burn_threshold
	
	for i in range(_last_index, idx + 1):
		var d := absf(torch_y - seam[i])
		var q := Q.EMPTY
		
		if burning:
			q = Q.BURN
		elif d <= perfect_tol:
			q = Q.PERFECT
		elif d <= good_tol:
			q = Q.GOOD
		elif d <= poor_tol:
			q = Q.POOR
		else:
			continue
		
		quality[i] = q
		bead[i] = torch_y
		
	_last_index = idx


func _finish() -> void:
	finished = true
	
	var counts := {Q.EMPTY: 0, Q.PERFECT: 0, Q.GOOD: 0, Q.POOR: 0, Q.BURN: 0}
	for q in quality:
		counts[q] += 1
		
	var total := float(quality.size())
	var raw := (
		float(counts[Q.PERFECT]) * 1.0
		+ float(counts[Q.GOOD]) * 0.6
		+ float(counts[Q.POOR]) * 0.15
		- float(counts[Q.BURN]) * 1.2
	) / total
	var score := clampf(raw, 0.0, 1.0)
	
	var result := {
		"score": score,
		"grade": _grade(score),
		"perfect": counts[Q.PERFECT],
		"good": counts[Q.GOOD],
		"poor": counts[Q.POOR],
		"burns": counts[Q.BURN],
		"missed": counts[Q.EMPTY],
		"total": int(total),
	}
	weld_finished.emit(result)
	

func _grade(score: float) -> String:
	if score >= 0.92: return "S"
	if score >= 0.80: return "A"
	if score >= 0.65: return "B"
	if score >= 0.45: return "C"
	return "D"
	

# Отрисовка

func _sample_pos(i: int) -> Vector2:
	return Vector2(torch_x + (float(i) * SAMPLE_STEP - scroll), center_y + seam[i])
	

func _draw() -> void:
	if seam.is_empty():
		return
		
	var w := get_viewport_rect().size.x
	var i0 := clampi(int((scroll - torch_x) / SAMPLE_STEP) -1, 0, seam.size() - 1)
	var i1 := clampi(int((scroll + (w - torch_x)) / SAMPLE_STEP) + 1, 0, seam.size() - 1)
	if i1 <= i0:
		return
		
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in range(i0, i1 + 1):
		var p := _sample_pos(i)
		top.append(p + Vector2(0.0, -gap_half))
		bot.append(p + Vector2(0.0, gap_half))
		
	var gap := PackedVector2Array()
	gap.append_array(top)
	for j in range(bot.size() - 1, -1, -1):
		gap.append(bot[j])
	draw_colored_polygon(gap, C_GAP)
		
	var poly_top := top.duplicate()
	poly_top.append(Vector2(top[top.size() - 1].x, center_y - plate_half_height - 400.0))
	poly_top.append(Vector2(top[0].x, center_y - plate_half_height - 400.0))
	draw_colored_polygon(poly_top, C_PLATE)
		
	var poly_bot := bot.duplicate()
	poly_bot.append(Vector2(bot[bot.size() - 1].x, center_y + plate_half_height + 400.0))
	poly_bot.append(Vector2(bot[0].x, center_y + plate_half_height + 400.0))
	draw_colored_polygon(poly_bot, C_PLATE)
		
	draw_polyline(top, C_EDGE, 2.0, true)
	draw_polyline(bot, C_EDGE, 2.0, true)
		
	for i in range(i0, i1 + 1):
		var q := quality[i]
		if q == Q.EMPTY:
			continue
		var pos := Vector2(torch_x + (float(i) * SAMPLE_STEP - scroll), center_y + bead[i])
		match q:
			Q.PERFECT: draw_circle(pos, 6.0, C_PERFECT)
			Q.GOOD: draw_circle(pos, 5.0, C_GOOD)
			Q.POOR: draw_circle(pos, 4.0, C_POOR)
			Q.BURN: draw_circle(pos, 8.0, C_BURN)
				
	var tip := Vector2(torch_x, center_y + torch_y)
	if welding:
		var glow := C_ARC
		glow.a = 0.22
		draw_circle(tip, 26.0, glow)
		draw_circle(tip, 9.0, C_ARC)
	draw_line(tip + Vector2(14.0, -46.0), tip, Color("#c8ccd2"), 6.0)
	draw_circle(tip, 3.0, Color("#ffffff"))
		
	var bar := Rect2(24.0, 24.0, 220.0, 14.0)
	draw_rect(bar, Color(0, 0, 0, 0.45))
	var fill := heat / burn_threshold
	var col := Color("#5bc9eb").lerp(Color("#e03131"), clampf(fill, 0.0, 1.0))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fill, 0.0, 1.0), bar.size.y)), col)
