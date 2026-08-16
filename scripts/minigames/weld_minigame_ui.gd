extends CanvasLayer
class_name WeldMinigameUI

signal closed(result: Dictionary)

@onready var game: Node2D = $Game
@onready var result_panel: Control = $ResultPanel

var _last_result: Dictionary = {}


func _ready() -> void:
	game.weld_finished.connect(_on_weld_finished)
	result_panel.continue_pressed.connect(_on_continue_pressed)
	
	
func start_weld(seam_seed: int) -> void:
	_last_result = {}
	result_panel.visible = false
	game.start(seam_seed)
	

func _on_weld_finished(result: Dictionary) -> void:
	_last_result = result
	result_panel.show_result(result)
	

func _on_continue_pressed() -> void:
	closed.emit(_last_result)
