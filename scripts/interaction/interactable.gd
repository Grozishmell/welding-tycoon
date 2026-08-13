extends StaticBody3D
class_name Interactable

signal interacted(player: Player)

@export var prompt_text: String = "Взаимодействовать"
@export var enabled: bool = true


func is_available() -> bool:
	return enabled
	

func interact(player: Player) -> void:
	if not is_available():
		return
	interacted.emit(player)
