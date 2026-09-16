class_name PlayerTransformation
extends Resource

@export var transformation_name: String = "Normal"
@export var speed_multiplier: float = 1.0
@export var jump_multiplier: float = 1.0
@export var gravity_multiplier: float = 1.0

# Appelé quand la transformation est équipée
func enter(_player: CharacterBody3D) -> void:
	pass

# Appelé quand la transformation est retirée
func exit(_player: CharacterBody3D) -> void:
	pass

# Appelé lors de l'appui sur la touche d'action spéciale (ex: Bouton B)
func use_special_ability(_player: CharacterBody3D) -> void:
	pass

# Appelé chaque frame physique pour des comportements continus
func physics_update(_player: CharacterBody3D, _delta: float) -> void:
	pass
