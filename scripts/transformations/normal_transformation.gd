class_name NormalTransformation
extends PlayerTransformation

func _init() -> void:
	transformation_name = "Normal"
	speed_multiplier = 1.0
	jump_multiplier = 1.0
	gravity_multiplier = 1.0

func enter(_player: CharacterBody3D) -> void:
	# Réinitialisation des effets visuels si besoin
	pass
