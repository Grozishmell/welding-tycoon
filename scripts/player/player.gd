extends CharacterBody3D
class_name Player

@export_group("Движение")
@export var walk_speed: float = 3.4
@export var sprint_speed: float = 5.6
@export var acceleration: float = 14.0
@export var jump_velocity: float = 4.2

@export_group("Камера")
@export var mouse_sensitivity: float = 0.0022
@export var pitch_limit_deg: float = 89.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var prompt: Label = $HUD/Prompt
@onready var crosshair: Label = $HUD/Crosshair

var input_enabled: bool = true
var _focused: Interactable = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	prompt.text = ""
	

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
		
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		var limit := deg_to_rad(pitch_limit_deg)
		head.rotation.x = clampf(head.rotation.x, -limit, limit)
		
	if event.is_action_pressed("interact") and _focused != null:
		_focused.interact(self)
		get_viewport().set_input_as_handled()
		
	if event.is_action_pressed("ui_cancel"):
		#  Освободить мышь
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
		
	if input_enabled:
		_handle_movement(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		
	move_and_slide()
	_update_focus()
	

func _handle_movement(delta: float) -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target := direction * speed
	
	velocity.x = lerp(velocity.x, target.x, 1.0 - exp(-acceleration * delta))
	velocity.z = lerp(velocity.z, target.z, 1.0 - exp(-acceleration * delta))
	

func _update_focus() -> void:
	var hit: Interactable = null
	
	if input_enabled and interact_ray.is_colliding():
		var collider := interact_ray.get_collider()
		if collider is Interactable and collider.is_available():
			hit = collider
			
	if hit == _focused:
		return
		
	_focused = hit
	if _focused != null:
		prompt.text = "[E] %s" % _focused.prompt_text
		crosshair.modulate = Color("#ffd166")
	else:
		prompt.text = ""
		crosshair.modulate = Color.WHITE
		

func set_control_enabled(enabled: bool) -> void:
	input_enabled = enabled
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_CONFINED
	if not enabled:
		_focused = null
		prompt.text = ""
		crosshair.visible = false
	else:
		crosshair.visible = true
