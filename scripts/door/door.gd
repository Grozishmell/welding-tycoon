@tool
extends Node3D

# Размеры
@export_group("Dimensions")
@export var width: float = 1.1:
	set(v):
		width = maxf(v, 0.1)
		_update_geometry()
@export var height: float = 2.1:
	set(v):
		height = maxf(v, 0.1)
		_update_geometry()
@export var thickness: float = 0.06:
	set(v):
		thickness = maxf(v, 0.01)
		_update_geometry()
@export_range(0.5, 4.0, 0.1) var trigger_depth: float = 2.6:
	set(v):
		trigger_depth = v
		_update_geometry()

# Поведение
@export_group("Behaviour")
@export var open_angle: float = 100.0
@export var duration: float = 0.45
@export var auto_close: bool = true
@export var player_group: StringName = &"player"

@onready var hinge: Node3D = $Hinge

var _tween: Tween
var _inside: int = 0


func _ready() -> void:
	_update_geometry()
	
	
func _update_geometry() -> void:
	if not is_node_ready():
		return
		
	var mesh_node := $Hinge/Leaf/MeshInstance3D as MeshInstance3D
	var leaf_col := $Hinge/Leaf/CollisionShape3D as CollisionShape3D
	var area_col := $DetectionArea/CollisionShape3D as CollisionShape3D
	
	var leaf_size := Vector3(width, height, thickness)
	var leaf_offset := Vector3(width * 0.5, height * 0.5, 0.0)
	
	# Меш створки
	var bm := mesh_node.mesh as BoxMesh
	if bm == null:
		bm = BoxMesh.new()
		bm.resource_local_to_scene = true
		mesh_node.mesh = bm
	bm.size = leaf_size
	mesh_node.position = leaf_offset
	
	# Коллизия створки
	var bs := leaf_col.shape as BoxShape3D
	if bs == null:
		bs = BoxShape3D.new()
		bs.resource_local_to_scene = true
		leaf_col.shape = bs
	bs.size = leaf_size
	leaf_col.position = leaf_offset
	
	# Зона детекции
	var az := area_col.shape as BoxShape3D
	if az == null:
		az = BoxShape3D.new()
		az.resource_local_to_scene = true
		area_col.shape = az
	az.size = Vector3(width + 1.3, height + 0.1, trigger_depth)
	area_col.position = Vector3(width * 0.5, height * 0.5 + 0.05, 0.0)


# Логика открытия
func _on_detection_area_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint() or not body.is_in_group(player_group):
		return
	_inside += 1
	if _inside > 1:
		return
	# С какой стороны подошли
	var side := signf(to_local(body.global_position).z)
	if is_zero_approx(side):
		side = 1.0
	_rotate_to(side * open_angle)
	
	
func _on_detection_area_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint() or not body.is_in_group(player_group):
		return
	_inside = maxi(_inside - 1, 0)
	if _inside == 0 and auto_close:
		_rotate_to(0.0)


func _rotate_to(deg: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(hinge, ^"rotation_degrees:y", deg, duration)
