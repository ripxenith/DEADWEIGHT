extends Node3D

@export var move_speed := 15.0
@export var acceleration := 10.0

@export var mouse_sensitivity := 0.003
@export var mouse_deadzone := 2.0

@export var rotation_speed := 1.5
@export var rotation_damping := 5.0

@onready var pilot_area: Area3D = $Cyclops/PilotArea
@onready var interior_area: Area3D = $Cyclops/ShipGravity
@onready var multiplayer_synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

var previous_transform: Transform3D

var player_inside := false
var piloting := false
var player: Node3D = null

# Linear momentum.
var ship_velocity := Vector3.ZERO

# Current ship orientation.
var ship_basis := Basis.IDENTITY

# Angular momentum.
var rotation_velocity := Vector3.ZERO

# Everything currently inside the ship.
var ship_contents: Array[Node3D] = []


func _ready() -> void:
	pilot_area.body_entered.connect(_on_pilot_area_body_entered)
	pilot_area.body_exited.connect(_on_pilot_area_body_exited)

	interior_area.body_entered.connect(_on_interior_body_entered)
	interior_area.body_exited.connect(_on_interior_body_exited)

	ship_basis = global_transform.basis.orthonormalized()
	previous_transform = global_transform


func _on_pilot_area_body_entered(body: Node3D) -> void:
	if body.has_method("set_ship_control"):
		player_inside = true
		player = body


func _on_pilot_area_body_exited(body: Node3D) -> void:
	if body == player and not piloting:
		player_inside = false
		player = null


func _on_interior_body_entered(body: Node3D) -> void:
	if body == self:
		return

	if not ship_contents.has(body):
		ship_contents.append(body)


func _on_interior_body_exited(body: Node3D) -> void:
	ship_contents.erase(body)


func _physics_process(delta: float) -> void:
	# Only the current authority is allowed to actually
	# control the ship.
	if is_multiplayer_authority():
		
		# Handle entering/exiting the ship.
		if player != null and player.is_multiplayer_authority():
			if Input.is_action_just_pressed("interact"):
				if piloting:
					exit_ship()
				elif player_inside:
					enter_ship()

		# Only the pilot actually drives the ship.
		if piloting:
			drive_ship(delta)

	# Everyone needs to apply the ship's movement to
	# players and cargo inside the ship.
	apply_ship_motion(previous_transform)

	# Save this frame's transform for the next frame.
	previous_transform = global_transform


func enter_ship() -> void:
	if player == null:
		return

	piloting = true

	# Use the ship's current orientation as our starting basis.
	ship_basis = global_transform.basis.orthonormalized()

	# Don't inherit rotational input from before entering.
	rotation_velocity = Vector3.ZERO

	# Give the player authority over the ship.
	var pilot_authority := player.get_multiplayer_authority()

	set_multiplayer_authority(pilot_authority)
	multiplayer_synchronizer.set_multiplayer_authority(pilot_authority)

	player.set_ship_control(self, true)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	print("ENTERED SHIP - AUTHORITY: ", pilot_authority)


func exit_ship() -> void:
	if player == null:
		return

	piloting = false

	player.set_ship_control(self, false)

	# Give the server authority back.
	set_multiplayer_authority(1)
	multiplayer_synchronizer.set_multiplayer_authority(1)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	print("EXITED SHIP")


func _input(event: InputEvent) -> void:
	# Only the player currently piloting the ship
	# should process ship mouse input.
	if not piloting:
		return

	if not is_multiplayer_authority():
		return

	if player == null:
		return

	if not player.is_multiplayer_authority():
		return

	if event is InputEventMouseMotion:
		var mouse_x: float = event.relative.x
		var mouse_y: float = event.relative.y

		# Deadzone.
		if abs(mouse_x) < mouse_deadzone:
			mouse_x = 0.0

		if abs(mouse_y) < mouse_deadzone:
			mouse_y = 0.0

		# Add mouse input to angular velocity.
		rotation_velocity.y -= mouse_x * mouse_sensitivity
		rotation_velocity.x -= mouse_y * mouse_sensitivity


func drive_ship(delta: float) -> void:
	# =========================================
	# LINEAR THRUST
	# =========================================

	var thrust_direction := Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		thrust_direction += -ship_basis.z

	if Input.is_action_pressed("move_backward"):
		thrust_direction += ship_basis.z

	if Input.is_action_pressed("move_left"):
		thrust_direction -= ship_basis.x

	if Input.is_action_pressed("move_right"):
		thrust_direction += ship_basis.x

	if Input.is_action_pressed("move_up"):
		thrust_direction += ship_basis.y

	if Input.is_action_pressed("move_down"):
		thrust_direction -= ship_basis.y

	if thrust_direction.length() > 0.0:
		thrust_direction = thrust_direction.normalized()

		# Accelerate instead of directly setting velocity.
		ship_velocity += thrust_direction * acceleration * delta

		# Maximum velocity.
		if ship_velocity.length() > move_speed:
			ship_velocity = ship_velocity.normalized() * move_speed


	# =========================================
	# ANGULAR MOMENTUM
	# =========================================

	# Gradually slow rotational movement.
	rotation_velocity = rotation_velocity.move_toward(
		Vector3.ZERO,
		rotation_damping * delta
	)

	if rotation_velocity.length() > 0.0:
		var yaw := rotation_velocity.y * delta
		var pitch := rotation_velocity.x * delta

		# Yaw around the ship's local/up direction.
		ship_basis = Basis(
			Quaternion(Vector3.UP, yaw)
		) * ship_basis

		# Pitch around the ship's local/right direction.
		ship_basis = ship_basis * Basis(
			Quaternion(Vector3.RIGHT, pitch)
		)


	# =========================================
	# ROLL
	# =========================================

	var roll_input := 0.0

	if Input.is_action_pressed("roll_left"):
		roll_input -= 1.0

	if Input.is_action_pressed("roll_right"):
		roll_input += 1.0

	if roll_input != 0.0:
		ship_basis = ship_basis * Basis(
			Quaternion(
				Vector3.FORWARD,
				roll_input * rotation_speed * delta
			)
		)


	# Clean up accumulated floating-point errors.
	ship_basis = ship_basis.orthonormalized()

	# Apply rotation.
	global_transform.basis = ship_basis

	# Apply linear momentum.
	global_position += ship_velocity * delta


func apply_ship_motion(old_transform: Transform3D) -> void:
	var new_transform := global_transform

	# If the ship hasn't moved, there's nothing to carry.
	if old_transform == new_transform:
		return

	for body in ship_contents:
		if not is_instance_valid(body):
			continue

		if body == self:
			continue

		# Only these things inherit ship movement.
		if not body.is_in_group("Grabbable") and not body.is_in_group("Players"):
			continue

		# Calculate the object's transform relative to
		# the ship before the ship moved.
		var relative_transform := (
			old_transform.affine_inverse()
			* body.global_transform
		)

		# Apply the same ship movement to the object.
		body.global_transform = new_transform * relative_transform
