extends Interactable
class_name ElevatorButton

@export var level: LevelEntry

@export_group("Тряска кабины")
@export var shake_strength: float = 0.035
@export var shake_speed: float = 26.0

@export var cabin_light_path: NodePath

var _shaking: bool = false
var _shake_time: float = 0.0
var _player: Player = null
var _head_rest: Vector3 = Vector3.ZERO


func _ready() -> void:
	prompt_text = level.display_name if level != null else "Кнопка"
	set_process(false)
	

func is_available() -> bool:
	return enabled and level != null and level.unlocked and not SceneManager.is_busy


func interact(player: Player) -> void:
	if not is_available():
		return
		
	_player = player
	_player.set_control_enabled(false)
	_head_rest = _player.head.position
	
	_shaking = true
	_shake_time = 0.0
	set_process(true)
	
	_flicker_cabin_light()
	await get_tree().create_timer(0.75).timeout
	SceneManager.travel_to(level)
	SceneManager.transition_finished.connect(_on_arrived, CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	if not _shaking or _player == null:
		return
		
	_shake_time += delta
	var v := sin(_shake_time * shake_speed) * 0.6 + sin(_shake_time * shake_speed * 2.7) * 0.4
	var h := sin(_shake_time * shake_speed * 1.3 + 1.1) * 0.5
	
	_player.head.position = _head_rest + Vector3(
		h * shake_strength * 0.4, v * shake_strength, 0.0
	)


func _on_arrived(_level_id: String) -> void:
	_shaking = false
	set_process(false)
	
	_player = null
	

func _flicker_cabin_light() -> void:
	if cabin_light_path.is_empty():
		return
	var light := get_node_or_null(cabin_light_path)
	if light == null:
		push_warning("ElevatorButton: лампа не найдена по пути %s" % cabin_light_path)
		return
		
	var base: float = light.light_energy
	var tw := create_tween()
	tw.tween_property(light, "light_energy", base * 0.05, 0.04)
	tw.tween_property(light, "light_energy", base * 0.7, 0.10)
	tw.tween_property(light, "light_energy", base * 0.1, 0.06)
	tw.tween_property(light, "light_energy", base * 1.3, 0.15)
	tw.tween_property(light, "light_energy", base * 0.35, 0.09)
	tw.tween_property(light, "light_energy", base, 0.30)
