class_name FireFlowerItem
extends Area3D

@export var rotation_speed: float = 2.5
@export var bob_speed: float = 3.0
@export var bob_height: float = 0.25

var base_y: float = 0.0
var time_passed: float = 0.0

func _ready() -> void:
	base_y = position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	time_passed += delta
	# Flottement et rotation de l'item sur lui-même
	rotate_y(rotation_speed * delta)
	position.y = base_y + sin(time_passed * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_transformation"):
		body.set_transformation(FireTransformation.new())
		queue_free()
