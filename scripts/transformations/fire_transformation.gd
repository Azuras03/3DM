class_name FireTransformation
extends PlayerTransformation

var fireball_scene: PackedScene = preload("res://scenes/projectiles/fireball.tscn")
var cooldown: float = 0.25
var current_cooldown: float = 0.0

func _init() -> void:
	transformation_name = "Feu"
	speed_multiplier = 1.15  # Vitesse augmentée de 15%
	jump_multiplier = 1.05   # Saut légèrement boosté
	gravity_multiplier = 1.0

func enter(_player: CharacterBody3D) -> void:
	print("🔥 Transformation équipée : Fleur de Feu !")

func exit(_player: CharacterBody3D) -> void:
	print("Transformation retirée.")

func use_special_ability(player: CharacterBody3D) -> void:
	if current_cooldown <= 0.0 and fireball_scene:
		var fireball := fireball_scene.instantiate() as Fireball
		# Positionne la boule devant les mains du joueur
		var facing_dir: Vector3 = -player.visuals.global_transform.basis.z
		var spawn_pos: Vector3 = player.global_position + Vector3(0, 0.6, 0) + facing_dir * 0.7
		fireball.move_direction = facing_dir
		player.get_parent().add_child(fireball)
		fireball.global_position = spawn_pos
		current_cooldown = cooldown

func physics_update(_player: CharacterBody3D, delta: float) -> void:
	if current_cooldown > 0.0:
		current_cooldown -= delta
