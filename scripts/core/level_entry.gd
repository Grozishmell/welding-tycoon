extends Resource
class_name LevelEntry

@export var id: String = "parking"
@export var display_name: String = "Подземный паркинг"

@export_file("*.tscn") var scene_path: String = ""

@export var spawn_point: String = "Default"

@export var unlocked: bool = true

@export var travel_time: float = 2.2
