extends Node3D

@onready var collision: Area3D = $StaticBody3D/Area3D
@onready var particles: GPUParticles3D = $GPUParticles3D
@onready var block = $StaticBody3D/CollisionShape3D/BlockShape

var exploded: bool = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	collision.body_entered.connect(_explode);

func _explode(body: Node3D) -> void:
	if exploded:
		return
	exploded = true;
	particles.emitting= true;
	particles.restart()
	$StaticBody3D/CollisionShape3D.queue_free();
	await get_tree().create_timer(particles.lifetime).timeout
	queue_free()
