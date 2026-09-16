class_name Fireball
extends CharacterBody3D

@export var speed: float = 16.0
@export var bounce_velocity: float = 6.0
@export var lifetime: float = 3.0
@export var gravity: float = 25.0

var move_direction: Vector3 = Vector3.FORWARD
var has_collided: bool = false
@onready var fire_particles = $GPUParticles3D
@onready var burst: GPUParticles3D = fire_particles.duplicate()

func die() -> void:
	if has_collided:
		return
	has_collided = true;
	set_physics_process(false) # Coupe la gravité et les collisions immédiatement
	explode()
	# 1. On fige le déplacement et on coupe la collision
	velocity = Vector3.ZERO
	$CollisionShape3D.set_deferred("disabled", true)
	fire_particles.emitting = false;
	# 2. On cache la sphère orange et la lumière
	$MeshInstance3D.hide()
	$OmniLight3D.hide()
	await get_tree().create_timer(fire_particles.lifetime).timeout
	queue_free()

func explode() -> void:
	get_parent().add_child(burst)
	burst.global_position = global_position
	burst.explosiveness = 1.0  # Toutes les particules d'un coup
	burst.one_shot = true      # Un seul cycle d'explosion
	burst.amount = 20
	burst.restart()

func _ready() -> void:
	velocity.x = move_direction.x * speed
	velocity.z = move_direction.z * speed
	velocity.y = 1.0 # Petite impulsion initiale vers le haut

func _physics_process(delta: float) -> void:
	handleDieCases(delta)
	handleGravity(delta)
	move_and_slide()

func handleDieCases(delta:float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		die()
		return
	# Destruction si on percute un mur
	if is_on_wall():
		die()
		return

func handleGravity(delta: float) -> void:
	# Gravité
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Rebond sur le sol façon Mario
	if is_on_floor():
		velocity.y = bounce_velocity
