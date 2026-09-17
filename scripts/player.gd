class_name Player
extends CharacterBody3D

@export_group("Déplacements Manette")
@export var walk_speed: float = 7.0             # Vitesse de marche normale
@export var run_speed: float = 10.0             # Vitesse maximale en maintenant X (Xbox)
@export var run_acceleration: float = 2.5       # Vitesse de montée en régime
@export var acceleration: float = 50.0
@export var friction: float = 100.0
@export var air_control: float = 70.0

@export_group("Caméra (Joystick Droit)")
@export var camera_sensitivity: float = 2.5     # Sensibilité de rotation de la caméra

@export_group("Saut (Physique Mario)")
@export var jump_height: float = 3.2
@export var min_jump_height: float = 1.0
@export var jump_time_to_peak: float = 0.28
@export var jump_time_to_descent: float = 0.38
@export var max_fall_speed: float = 30.0
@export var fall_respawn_y: float = -10.0

@export_group("Wall-Jump & Glissade Murale")
@export var wall_slide_max_speed: float = 3.5    # Vitesse de chute max réduite contre un mur
@export var wall_jump_velocity: float = 20.0     # Impulsion verticale du wall jump
@export var wall_jump_pushback: float = 11.0     # Éjection horizontale hors du mur

@export_group("Charge au Sol / Plongeon (ZR)")
@export var dive_fall_gravity: float = 85.0            # Gravité accélérée en maintenant ZR pendant la chute
@export var dive_max_fall_speed: float = 500.0          # Vitesse de chute max pendant le plongeon
@export var break_blocks_speed_threshold: float = 20.0 # Seuil de vitesse requis pour détruire les blocs
@export var canBreakBlocks: bool = false               # Devient true quand la vitesse de charge au sol est atteinte

@export_group("Assistance & Game Feel")
@export var jump_buffer_time: float = 0.15       # Délai de mémorisation du saut

# Constantes cinématiques calculées au démarrage
var jump_velocity: float
var min_jump_velocity: float
var jump_gravity: float
var fall_gravity: float

# États & Timers
var initial_position: Vector3
var current_speed: float = 7.0
var wall_normal: Vector3 = Vector3.ZERO
var was_on_floor: bool = true

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var wall_coyote_timer: float = 0.0
var wall_jump_lock_timer: float = 0.0
var landing_burst_timer: float = 0.0

var was_jump_pressed: bool = false
var was_ability_pressed: bool = false

var current_transformation: PlayerTransformation

@onready var visuals: Node3D = $Visuals
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var foot_particles: GPUParticles3D = $FootParticles

# ==============================================================================
# INITIALISATION
# ==============================================================================
func _ready() -> void:
	initial_position = global_position
	current_speed = walk_speed
	set_transformation(NormalTransformation.new())

	spring_arm.add_excluded_object(get_rid())
	spring_arm.margin = 0.2

	# Calcul cinématique des forces du saut façon Mario
	jump_gravity = (2.0 * jump_height) / (jump_time_to_peak * jump_time_to_peak)
	fall_gravity = (2.0 * jump_height) / (jump_time_to_descent * jump_time_to_descent)
	jump_velocity = (2.0 * jump_height) / jump_time_to_peak
	min_jump_velocity = sqrt(2.0 * jump_gravity * min_jump_height)

func set_transformation(new_transfo: PlayerTransformation) -> void:
	if current_transformation:
		current_transformation.exit(self)
	current_transformation = new_transfo
	if current_transformation:
		current_transformation.enter(self)

# ==============================================================================
# BOUCLE PHYSIQUE PRINCIPALE
# ==============================================================================
func _physics_process(delta: float) -> void:
	_update_camera(delta)
	_update_transformation(delta)
	_update_timers(delta)

	_process_horizontal_movement(delta)
	_process_vertical_movement(delta)

	var prev_vertical_speed := velocity.y
	move_and_slide()

	_update_effects(delta, prev_vertical_speed)
	_check_respawn()

# ==============================================================================
# 1. GESTION DE LA CAMÉRA
# ==============================================================================
func _update_camera(delta: float) -> void:
	var look_x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var look_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)

	if abs(look_x) > 0.15:
		camera_pivot.rotation.y -= look_x * camera_sensitivity * delta

	if abs(look_y) > 0.15:
		spring_arm.rotation.x = clampf(
			spring_arm.rotation.x - look_y * camera_sensitivity * delta,
			deg_to_rad(-65.0),
			deg_to_rad(20.0)
		)

# ==============================================================================
# 2. TRANSFORMATION & CAPACITÉ SPÉCIALE
# ==============================================================================
func _update_transformation(delta: float) -> void:
	if not current_transformation:
		return
	current_transformation.physics_update(self, delta)

	var is_ability_pressed := Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	if is_ability_pressed and not was_ability_pressed:
		current_transformation.use_special_ability(self)
	was_ability_pressed = is_ability_pressed

# ==============================================================================
# 3. MISE À JOUR DES TIMERS
# ==============================================================================
func _update_timers(delta: float) -> void:
	coyote_timer = 0.12 if is_on_floor() else (coyote_timer - delta)
	jump_buffer_timer -= delta
	landing_burst_timer -= delta
	wall_jump_lock_timer -= delta

	if is_on_wall() and not is_on_floor():
		wall_normal = get_wall_normal()
		wall_coyote_timer = 0.15
	else:
		wall_coyote_timer -= delta

# ==============================================================================
# 4. DÉPLACEMENT HORIZONTAL & COURSE
# ==============================================================================
func _process_horizontal_movement(delta: float) -> void:
	var move_input := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	)
	var is_moving := move_input.length() > 0.15
	var is_running := Input.is_joy_button_pressed(0, JOY_BUTTON_X)

	# Accélération graduelle en course
	if is_running and is_moving and is_on_floor():
		current_speed = move_toward(current_speed, run_speed, run_acceleration * delta)
	elif not is_running:
		current_speed = move_toward(current_speed, walk_speed, friction * delta)
	if not is_moving and is_on_floor():
		current_speed = walk_speed

	# Direction relative à l'orientation de la caméra
	var cam_basis := camera_pivot.global_transform.basis
	var move_dir := cam_basis * Vector3(move_input.x, 0.0, move_input.y)
	move_dir.y = 0.0
	var direction := move_dir.normalized()

	# Verrou d'éjection pendant un wall-jump
	if wall_jump_lock_timer > 0.0:
		return

	if is_moving:
		var is_reversing := Vector2(velocity.x, velocity.z).dot(Vector2(direction.x, direction.z)) < -0.1
		var current_accel := (acceleration * 2.5 if is_reversing else acceleration) if is_on_floor() else air_control
		var target_vel := direction * (current_speed * current_transformation.speed_multiplier) * clampf(move_input.length(), 0.0, 1.0)

		velocity.x = move_toward(velocity.x, target_vel.x, current_accel * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, current_accel * delta)
		visuals.basis = Basis.looking_at(direction, Vector3.UP)
	else:
		var stop_friction := (friction if is_on_floor() else 0.0) * delta
		velocity.x = move_toward(velocity.x, 0.0, stop_friction)
		velocity.z = move_toward(velocity.z, 0.0, stop_friction)

# ==============================================================================
# 5. SAUT, GRAVITÉ, WALL-JUMP & PLONGEON (ZR)
# ==============================================================================
func _process_vertical_movement(delta: float) -> void:
	var is_zr_pressed := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.3 or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	var is_diving := is_zr_pressed and not is_on_floor() and velocity.y <= 0.0

	# 1. Gestion de la gravité et de la chute
	if is_on_floor():
		canBreakBlocks = false
	else:
		var current_gravity := jump_gravity if velocity.y > 0.0 else (dive_fall_gravity if is_diving else fall_gravity)
		current_gravity *= current_transformation.gravity_multiplier

		var current_fall_limit := max_fall_speed
		if is_diving:
			current_fall_limit = dive_max_fall_speed
		elif is_on_wall() and velocity.y <= 0.0:
			current_fall_limit = wall_slide_max_speed

		velocity.y = maxf(velocity.y - current_gravity * delta, -current_fall_limit)
		canBreakBlocks = is_diving and abs(velocity.y) >= break_blocks_speed_threshold

	# 2. Gestion des inputs de saut
	var is_jump_pressed := Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	var jump_just_pressed := is_jump_pressed and not was_jump_pressed
	var jump_just_released := not is_jump_pressed and was_jump_pressed
	was_jump_pressed = is_jump_pressed

	if jump_just_pressed:
		jump_buffer_timer = jump_buffer_time

	# 3. Déclenchement du saut (au sol ou wall-jump)
	if jump_buffer_timer > 0.0:
		if coyote_timer > 0.0:
			velocity.y = jump_velocity * current_transformation.jump_multiplier
			coyote_timer = 0.0
			jump_buffer_timer = 0.0
		elif wall_coyote_timer > 0.0:
			velocity.y = wall_jump_velocity
			velocity.x = wall_normal.x * wall_jump_pushback
			velocity.z = wall_normal.z * wall_jump_pushback
			wall_coyote_timer = 0.0
			jump_buffer_timer = 0.0
			wall_jump_lock_timer = 0.18

			var push_dir := Vector3(wall_normal.x, 0.0, wall_normal.z).normalized()
			if push_dir.length_squared() > 0.001:
				visuals.basis = Basis.looking_at(push_dir, Vector3.UP)

	# 4. Coupure de saut si le bouton A est relâché en montant
	if jump_just_released and velocity.y > min_jump_velocity:
		velocity.y = min_jump_velocity

# ==============================================================================
# 6. EFFETS VISUELS & PARTICULES
# ==============================================================================
func _update_effects(delta: float, prev_vertical_speed: float) -> void:
	if not foot_particles:
		return

	var currently_on_floor := is_on_floor()
	var just_landed := currently_on_floor and not was_on_floor and prev_vertical_speed < -2.0

	if just_landed:
		foot_particles.explosiveness = 1.0
		foot_particles.amount_ratio = 1.0
		foot_particles.restart()
		foot_particles.emitting = true
		landing_burst_timer = 0.12
	elif landing_burst_timer <= 0.0:
		var is_moving := Vector2(velocity.x, velocity.z).length() > 0.5
		if currently_on_floor and is_moving:
			foot_particles.explosiveness = 0.0
			var speed_factor := clampf((current_speed - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
			foot_particles.amount_ratio = lerpf(0.35, 1.0, speed_factor)
			foot_particles.emitting = true
		else:
			foot_particles.emitting = false

	was_on_floor = currently_on_floor

# ==============================================================================
# 7. RÉAPPARITION
# ==============================================================================
func _check_respawn() -> void:
	if global_position.y < fall_respawn_y or Input.is_joy_button_pressed(0, JOY_BUTTON_BACK):
		velocity = Vector3.ZERO
		current_speed = walk_speed
		canBreakBlocks = false
		set_transformation(NormalTransformation.new())
		global_position = initial_position
