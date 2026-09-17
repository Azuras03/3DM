extends Node3D

@onready var collision: Area3D = $StaticBody3D/CollisionsDetector/Area3D
@onready var topCollision: Area3D = $StaticBody3D/CollisionsDetector/Area3D2
@onready var particles: GPUParticles3D = $GPUParticles3D
@onready var block = $StaticBody3D/CollisionShape3D/BlockShape

var exploded: bool = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	collision.body_entered.connect(_explode);
	topCollision.body_entered.connect(explodeTop);

func explodeTop(body: Node3D) -> void:
	print(body.canBreakBlocks);
	if body is Player and body.canBreakBlocks:
		_explode(body)
		body.velocity.y = 20.0

func _explode(_body: Node3D) -> void:
	if exploded:
		return
	exploded = true;
	particles.emitting= true;
	particles.restart()
	$StaticBody3D/CollisionsDetector.queue_free();
	$StaticBody3D.queue_free();
	await get_tree().create_timer(particles.lifetime).timeout
	queue_free()
