extends Interactable
class_name WeldStation

@export var minigame_scene: PackedScene

@export_group("Параметры заказа")
@export var seam_length: float = 3600.0
@export var scroll_speed: float = 190.0
@export var wave_amplitude: float = 34.0
@export var lead_in: float = 2.0
@export var perfect_tol: float = 6.0
@export var good_tol: float = 14.0
@export var poor_tol: float = 28.0

var _active_ui: CanvasLayer = null
var _player: Player = null


func _ready() -> void:
	prompt_text = "Варить"
	

func is_available() -> bool:
	return enabled and _active_ui == null


func interact(player: Player) -> void:
	if not is_available() or minigame_scene == null:
		push_warning("WeldStation: не назначена minigame_scene")
		return
		
	_player = player
	_player.set_control_enabled(false)
	
	_active_ui = minigame_scene.instantiate()
	get_tree().current_scene.add_child(_active_ui)
	
	var game: Node2D = _active_ui.game
	game.seam_length = seam_length
	game.scroll_speed = scroll_speed
	game.wave_amplitude = wave_amplitude
	game.lead_in = lead_in
	game.perfect_tol = perfect_tol
	game.good_tol = good_tol
	game.poor_tol = poor_tol
	
	_active_ui.closed.connect(_on_minigame_closed, CONNECT_ONE_SHOT)
	_active_ui.start_weld(randi())
	

func _on_minigame_closed(result: Dictionary) -> void:
	print("Шов окончен: оценка %s, счет %.2f, лучшая серия %d, непровар %d" % [result.grade, result.score, result.max_combo, result.missed])
	_close()
	

func _close() -> void:
	if _active_ui != null:
		_active_ui.queue_free()
		_active_ui = null
	if _player != null:
		_player.set_control_enabled(true)
		_player = null
