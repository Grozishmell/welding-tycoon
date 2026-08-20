extends Node

signal transition_started(level_id: String)
signal transition_finished(level_id: String)

var is_busy: bool = false

var _layer: CanvasLayer
var _fade: ColorRect
var _path: String = ""
var _spawn: String = "Default"
var _level_id: String = ""
var _min_black_until: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)
	
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	set_process(false)
	

func travel_to(entry: LevelEntry) -> void:
	if is_busy or entry == null or entry.scene_path.is_empty():
		push_warning("SceneManager: некуда ехать")
		return
	
	is_busy = true
	_path = entry.scene_path
	_spawn = entry.spawn_point
	_level_id = entry.id
	transition_started.emit(_level_id)
	
	await _fade_to(1.0, 0.6)
	
	# Минимальная длительность 'поездки'
	_min_black_until = _now() + entry.travel_time
	
	var err := ResourceLoader.load_threaded_request(_path)
	if err != OK:
		push_error("SceneManager: не удалось начать загрузку %s" % _path)
		await _abort()
		return
		
	set_process(true)
	

func _process(_delta: float) -> void:
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_path, progress)
	
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			if _now() < _min_black_until:
				return
			set_process(false)
			_swap()
		_:
			set_process(false)
			push_error("SceneManager: загрузка провалилась - %s" % _path)
			await _abort()
			

func _swap() -> void:
	var packed: PackedScene = ResourceLoader.load_threaded_get(_path)
	get_tree().change_scene_to_packed(packed)
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	_place_player()
	await _fade_to(0.0, 0.7)
	
	is_busy = false
	transition_finished.emit(_level_id)
	

func _place_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		push_warning("SceneManager: в сцене нет узла в группе 'player'")
		return
	
	var player: Node3D = players[0]
	
	for sp in get_tree().get_nodes_in_group("spawn_points"):
		if sp.name == _spawn:
			player.global_position = sp.global_position
			player.rotation.y = sp.global_rotation.y
			return
			
	push_warning("SceneManager: точка спавна '%s' не найдена" % _spawn)


func _abort() -> void:
	await _fade_to(0.0, 0.4)
	is_busy = false
	

func _fade_to(target: float, duration: float) -> void:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_fade, "color:a", target, duration)
	await tw.finished


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
