class_name Player
extends CharacterBody3D

@export_group("Déplacements Manette")
@export var walk_speed: float = 7.0             # Vitesse de marche normale
@export var run_speed: float = 10.0             # Vitesse maximale atteinte en maintenant X (Xbox)
@export var run_acceleration: float = 2.5       # Vitesse de montée en régime (augmentation graduelle)
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
@export var jump_buffer_time: float = 0.15       # Délai de mémorisation du saut avant de toucher le sol

var jump_velocity: float
var min_jump_velocity: float
var jump_gravity: float
var fall_gravity: float

var was_jump_pressed: bool = false
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var wall_coyote_timer: float = 0.0
var wall_jump_lock_timer: float = 0.0
var wall_normal: Vector3 = Vector3.ZERO
var initial_position: Vector3
var current_speed: float = 8.0
var was_on_floor: bool = true
var landing_burst_timer: float = 0.0

var current_transformation: PlayerTransformation
var was_ability_pressed: bool = false

@onready var visuals: Node3D = $Visuals
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var foot_particles: GPUParticles3D = $FootParticles

func _ready() -> void:
	initial_position = global_position
	current_speed = walk_speed
	set_transformation(NormalTransformation.new())

	# Empêcher le SpringArm de collisionner avec le joueur (évite le glitch de caméra)
	spring_arm.add_excluded_object(get_rid())
	spring_arm.margin = 0.2
	# Calcul cinématique des forces du saut
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

func cameraProcess(delta: float) -> void:
	# 1. Contrôle de la caméra avec le joystick droit
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

func _physics_process(delta: float) -> void:
	cameraProcess(delta)

	# Capacité spéciale et mise à jour de la transformation active
	if current_transformation:
		current_transformation.physics_update(self, delta)

	var is_ability_pressed := Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	var ability_just_pressed := is_ability_pressed and not was_ability_pressed
	was_ability_pressed = is_ability_pressed

	if ability_just_pressed and current_transformation:
		current_transformation.use_special_ability(self)

	# 2. Lecture du joystick gauche pour le déplacement
	var move_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var move_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var input_vec := Vector2(move_x, move_y)

	# Course : augmentation graduelle de la vitesse en maintenant X (Xbox)
	var is_running := Input.is_joy_button_pressed(0, JOY_BUTTON_X)
	var is_moving := input_vec.length() > 0.15

	if is_running and is_moving and is_on_floor():
		current_speed = move_toward(current_speed, run_speed, run_acceleration * delta)
	elif not is_running:
		current_speed = move_toward(current_speed, walk_speed, friction * delta)

	if not is_moving and is_on_floor():
		current_speed = walk_speed

	# 3. Calcul de la direction relative à l'orientation de la caméra
	var cam_basis := camera_pivot.global_transform.basis
	var cam_forward := -cam_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := cam_basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var direction := (cam_forward * (-input_vec.y) + cam_right * input_vec.x).normalized()
	var is_reversing := Vector2(velocity.x, velocity.z).dot(Vector2(direction.x, direction.z)) < -0.1
	var current_accel: float = (acceleration * 2.5 if is_reversing else acceleration) if is_on_floor() else air_control
	var speed_mult := current_transformation.speed_multiplier if current_transformation else 1.0
	var target_vel := direction * (current_speed * speed_mult) * clampf(input_vec.length(), 0.0, 1.0)

	# Gestion du petit verrou de direction lors d'un wall-jump
	if wall_jump_lock_timer > 0.0:
		wall_jump_lock_timer -= delta
	else:
		if is_moving:
			velocity.x = move_toward(velocity.x, target_vel.x, current_accel * delta)
			velocity.z = move_toward(velocity.z, target_vel.z, current_accel * delta)
			# Orientation instantanée sans lissage vers la direction de course
			visuals.basis = Basis.looking_at(direction, Vector3.UP)
		else:
			var stop_friction := (friction if is_on_floor() else 0.0) * delta
			velocity.x = move_toward(velocity.x, 0.0, stop_friction)
			velocity.z = move_toward(velocity.z, 0.0, stop_friction)

	# 4. Détection du mur et glissade murale (Wall Slide)
	var is_on_wall_in_air := is_on_wall() and not is_on_floor()
	if is_on_wall_in_air:
		wall_normal = get_wall_normal()
		wall_coyote_timer = 0.15
	else:
		wall_coyote_timer -= delta

	# 5. Gravité, Glissade Murale et Plongeon Rapide (Touche ZR)
	var is_zr_pressed := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.3 or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	var is_diving := is_zr_pressed and not is_on_floor() and velocity.y <= 0.0

	if is_on_floor():
		coyote_timer = 0.12
		canBreakBlocks = false
	else:
		coyote_timer -= delta
		var current_gravity: float
		if velocity.y > 0.0:
			current_gravity = jump_gravity
		elif is_diving:
			current_gravity = dive_fall_gravity
		else:
			current_gravity = fall_gravity

		var grav_mult := current_transformation.gravity_multiplier if current_transformation else 1.0
		current_gravity *= grav_mult

		var current_fall_limit: float = max_fall_speed
		if is_diving:
			current_fall_limit = dive_max_fall_speed
		elif is_on_wall_in_air and velocity.y <= 0.0:
			current_fall_limit = wall_slide_max_speed

		velocity.y = maxf(velocity.y - current_gravity * delta, -current_fall_limit)

		# Activation de canBreakBlocks si la vitesse requise est atteinte en plongeon
		if is_diving and abs(velocity.y) >= break_blocks_speed_threshold:
			canBreakBlocks = true
		else:
			canBreakBlocks = false

	# 6. Saut (Bouton A) & Wall-Jump avec Jump Buffer
	var is_jump_pressed := Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	var jump_just_pressed := is_jump_pressed and not was_jump_pressed
	var jump_just_released := not is_jump_pressed and was_jump_pressed
	was_jump_pressed = is_jump_pressed

	# Mémorisation de l'appui sur A (Jump Buffer)
	if jump_just_pressed:
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer -= delta

	if jump_buffer_timer > 0.0:
		# Saut classique au sol
		if coyote_timer > 0.0:
			var jump_mult := current_transformation.jump_multiplier if current_transformation else 1.0
			velocity.y = jump_velocity * jump_mult
			coyote_timer = 0.0
			jump_buffer_timer = 0.0
		# Wall-Jump si on est contre un mur
		elif wall_coyote_timer > 0.0:
			velocity.y = wall_jump_velocity
			velocity.x = wall_normal.x * wall_jump_pushback
			velocity.z = wall_normal.z * wall_jump_pushback
			wall_coyote_timer = 0.0
			jump_buffer_timer = 0.0
			wall_jump_lock_timer = 0.18 # Bref verrou pour garantir l'éjection hors du mur
			# Orientation immédiate vers l'extérieur du mur
			var push_dir := Vector3(wall_normal.x, 0.0, wall_normal.z).normalized()
			if push_dir.length_squared() > 0.001:
				visuals.basis = Basis.looking_at(push_dir, Vector3.UP)

	# Coupure du saut si on relâche le bouton A en montant
	if jump_just_released and velocity.y > min_jump_velocity:
		velocity.y = min_jump_velocity

	var previous_vert_vel := velocity.y
	move_and_slide()

	# 7. Gestion des particules FootParticles (course et atterrissage)
	if foot_particles:
		var currently_on_floor := is_on_floor()
		# Détection de l'atterrissage après un saut/chute
		var just_landed := currently_on_floor and not was_on_floor and previous_vert_vel < -2.0

		if just_landed:
			foot_particles.explosiveness = 1.0
			foot_particles.amount_ratio = 1.0
			foot_particles.restart()
			foot_particles.emitting = true
			landing_burst_timer = 0.12
		elif landing_burst_timer > 0.0:
			landing_burst_timer -= delta
		else:
			var is_moving_on_floor := currently_on_floor and is_moving and Vector2(velocity.x, velocity.z).length() > 0.5
			if is_moving_on_floor:
				foot_particles.explosiveness = 0.0
				# Plus de particules quand on court vite (sprint avec X)
				var speed_factor := clampf((current_speed - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
				foot_particles.amount_ratio = lerpf(0.35, 1.0, speed_factor)
				foot_particles.emitting = true
			else:
				foot_particles.emitting = false

		was_on_floor = currently_on_floor

	# 8. Réapparition (Chute ou bouton Back/Select)
	if global_position.y < fall_respawn_y or Input.is_joy_button_pressed(0, JOY_BUTTON_BACK):
		velocity = Vector3.ZERO
		current_speed = walk_speed
		canBreakBlocks = false
		set_transformation(NormalTransformation.new())
		global_position = initial_position
