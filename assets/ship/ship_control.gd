extends Node3D


# ============================================================
# MOVEMENT
# ============================================================

@export var move_speed := 15.0
@export var acceleration := 10.0

@export var mouse_sensitivity := 0.003
@export var mouse_deadzone := 2.0

@export var rotation_speed := 1.5
@export var rotation_damping := 5.0


# ============================================================
# NODES
# ============================================================

@onready var pilot_area: Area3D = $Cyclops/PilotArea
@onready var interior_area: Area3D = $Cyclops/ShipGravity
@onready var multiplayer_synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer


# ============================================================
# SHIP STATE
# ============================================================

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


# ============================================================
# READY
# ============================================================

func _ready() -> void:

	pilot_area.body_entered.connect(
		_on_pilot_area_body_entered
	)

	pilot_area.body_exited.connect(
		_on_pilot_area_body_exited
	)

	interior_area.body_entered.connect(
		_on_interior_body_entered
	)

	interior_area.body_exited.connect(
		_on_interior_body_exited
	)

	ship_basis = (
		global_transform.basis
		.orthonormalized()
	)

	previous_transform = global_transform


# ============================================================
# PILOT AREA
# ============================================================

func _on_pilot_area_body_entered(body: Node3D) -> void:

	if not body.has_method("set_ship_control"):
		return

	if not body.is_in_group("Players"):
		return

	player_inside = true
	player = body

	print(
		"SHIP: Player entered pilot area: ",
		body.name,
		" | Local Peer: ",
		multiplayer.get_unique_id()
	)


func _on_pilot_area_body_exited(body: Node3D) -> void:

	if body != player:
		return

	# Don't clear the pilot while they are actually piloting.
	if piloting:
		return

	player_inside = false
	player = null


# ============================================================
# SHIP INTERIOR
# ============================================================

func _on_interior_body_entered(body: Node3D) -> void:

	if body == self:
		return

	if not ship_contents.has(body):
		ship_contents.append(body)


func _on_interior_body_exited(body: Node3D) -> void:

	ship_contents.erase(body)


# ============================================================
# MAIN PHYSICS
# ============================================================

func _physics_process(delta: float) -> void:

	# ========================================================
	# ENTER SHIP
	# ========================================================

	if (
		player_inside
		and not piloting
		and player != null
		and player.is_multiplayer_authority()
	):

		if Input.is_action_just_pressed("interact"):
			_request_enter_ship()

			# IMPORTANT:
			# Prevent the same interact press from being
			# interpreted as "exit ship" below.
			return


	# ========================================================
	# PILOT CONTROLS
	# ========================================================

	if piloting and is_multiplayer_authority():

		if player != null:
			if player.is_multiplayer_authority():

				if Input.is_action_just_pressed("interact"):
					_request_exit_ship()
				else:
					drive_ship(delta)


	# ========================================================
	# APPLY SHIP MOTION
	# ========================================================

	apply_ship_motion(previous_transform)

	previous_transform = global_transform


# ============================================================
# ENTER SHIP REQUEST
# ============================================================

func _request_enter_ship() -> void:

	if player == null:
		return

	if not player.is_multiplayer_authority():
		return

	var pilot_peer_id := (
		player.get_multiplayer_authority()
	)

	# Host/server can approve itself immediately.
	if multiplayer.is_server():

		_server_enter_ship(
			pilot_peer_id
		)

		return

	# Client asks the server.
	request_enter_ship.rpc_id(1)


@rpc("any_peer", "reliable")
func request_enter_ship() -> void:

	if not multiplayer.is_server():
		return

	var sender_peer_id := (
		multiplayer.get_remote_sender_id()
	)

	if sender_peer_id <= 0:
		return

	_server_enter_ship(
		sender_peer_id
	)


# ============================================================
# SERVER ENTER SHIP
# ============================================================

func _server_enter_ship(
	pilot_peer_id: int
) -> void:

	if not multiplayer.is_server():
		return

	# Don't allow multiple pilots.
	if piloting:
		print(
			"SHIP: Enter request rejected. ",
			"Ship is already being piloted."
		)
		return

	var world := get_tree().current_scene

	if world == null:
		return

	var pilot := world.get_node_or_null(
		str(pilot_peer_id)
	)

	if pilot == null:
		print(
			"SHIP: Could not find player ",
			pilot_peer_id,
			" on server."
		)
		return

	if not pilot.has_method("set_ship_control"):
		return

	# Make sure the player is actually in the pilot area.
	if not _is_player_in_pilot_area(pilot):
		print(
			"SHIP: Player ",
			pilot_peer_id,
			" is not inside PilotArea."
		)
		return

	print(
		"SHIP: Server approving pilot: ",
		pilot_peer_id
	)

	# Tell every peer who owns the ship.
	set_ship_authority.rpc(
		pilot_peer_id
	)


# ============================================================
# CHECK PILOT AREA
# ============================================================

func _is_player_in_pilot_area(
	target_player: Node3D
) -> bool:

	if target_player == player and player_inside:
		return true

	for body in pilot_area.get_overlapping_bodies():

		if body == target_player:
			return true

	return false


# ============================================================
# EXIT SHIP REQUEST
# ============================================================

func _request_exit_ship() -> void:

	if player == null:
		return

	if not player.is_multiplayer_authority():
		return

	var pilot_peer_id := (
		player.get_multiplayer_authority()
	)

	# Host can approve itself.
	if multiplayer.is_server():

		_server_exit_ship(
			pilot_peer_id
		)

		return

	# Client asks server.
	request_exit_ship.rpc_id(1)


@rpc("any_peer", "reliable")
func request_exit_ship() -> void:

	if not multiplayer.is_server():
		return

	var sender_peer_id := (
		multiplayer.get_remote_sender_id()
	)

	if sender_peer_id <= 0:
		return

	_server_exit_ship(
		sender_peer_id
	)


# ============================================================
# SERVER EXIT SHIP
# ============================================================

func _server_exit_ship(
	pilot_peer_id: int
) -> void:

	if not multiplayer.is_server():
		return

	if not piloting:
		return

	if player == null:
		return

	if (
		player.get_multiplayer_authority()
		!= pilot_peer_id
	):
		return

	print(
		"SHIP: Server approving pilot exit: ",
		pilot_peer_id
	)

	# 0 means SERVER owns the ship.
	#
	# Peer 1 is a valid player ID because the host
	# is also a player.
	set_ship_authority.rpc(0)


# ============================================================
# SYNCHRONIZE SHIP AUTHORITY
# ============================================================

@rpc("authority", "call_local", "reliable")
func set_ship_authority(
	pilot_peer_id: int
) -> void:

	# ========================================================
	# SERVER AUTHORITY
	# ========================================================
	#
	# 0 is our special value meaning:
	# "The server owns the ship."
	#
	# We CANNOT use 1 here because peer 1 is the host player.
	#

	if pilot_peer_id == 0:

		set_multiplayer_authority(1)

		multiplayer_synchronizer.set_multiplayer_authority(
			1
		)

		piloting = false

		if player != null:

			player.set_ship_control(
				self,
				false
			)

		player_inside = false
		player = null

		print(
			"SHIP: Authority returned to server.",
			" | Local Peer: ",
			multiplayer.get_unique_id()
		)

		return


	# ========================================================
	# GIVE AUTHORITY TO PILOT
	# ========================================================

	set_multiplayer_authority(
		pilot_peer_id
	)

	multiplayer_synchronizer.set_multiplayer_authority(
		pilot_peer_id
	)

	var world := get_tree().current_scene

	if world == null:
		return

	var pilot := world.get_node_or_null(
		str(pilot_peer_id)
	)

	if pilot == null:

		print(
			"SHIP: Could not find pilot ",
			pilot_peer_id,
			" on peer ",
			multiplayer.get_unique_id()
		)

		return

	player = pilot


	# ========================================================
	# LOCAL PILOT
	# ========================================================

	if multiplayer.get_unique_id() == pilot_peer_id:

		piloting = true
		player_inside = true

		player.set_ship_control(
			self,
			true
		)

		# Start from current orientation.
		ship_basis = (
			global_transform.basis
			.orthonormalized()
		)

		# Don't inherit old mouse rotation.
		rotation_velocity = Vector3.ZERO

		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED
		)

		print(
			"SHIP: LOCAL PLAYER IS NOW PILOTING.",
			" | Peer: ",
			pilot_peer_id
		)


	# ========================================================
	# REMOTE PILOT
	# ========================================================

	else:

		piloting = false

		print(
			"SHIP: Remote player ",
			pilot_peer_id,
			" is piloting.",
			" | Local Peer: ",
			multiplayer.get_unique_id()
		)


# ============================================================
# MOUSE INPUT
# ============================================================

func _input(event: InputEvent) -> void:

	# Only the pilot processes mouse input.
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

		# Mouse deadzone.
		if abs(mouse_x) < mouse_deadzone:
			mouse_x = 0.0

		if abs(mouse_y) < mouse_deadzone:
			mouse_y = 0.0

		# Accumulate angular momentum.
		rotation_velocity.y -= (
			mouse_x
			* mouse_sensitivity
		)

		rotation_velocity.x -= (
			mouse_y
			* mouse_sensitivity
		)


# ============================================================
# DRIVE SHIP
# ============================================================

func drive_ship(delta: float) -> void:

	# ========================================================
	# LINEAR THRUST
	# ========================================================

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

		thrust_direction = (
			thrust_direction.normalized()
		)

		ship_velocity += (
			thrust_direction
			* acceleration
			* delta
		)

		# Maximum velocity.
		if ship_velocity.length() > move_speed:

			ship_velocity = (
				ship_velocity.normalized()
				* move_speed
			)


	# ========================================================
	# ANGULAR MOMENTUM
	# ========================================================

	rotation_velocity = (
		rotation_velocity.move_toward(
			Vector3.ZERO,
			rotation_damping * delta
		)
	)

	if rotation_velocity.length() > 0.0:

		var yaw := (
			rotation_velocity.y
			* delta
		)

		var pitch := (
			rotation_velocity.x
			* delta
		)

		# Yaw around ship-local up.
		ship_basis = Basis(
			Quaternion(
				Vector3.UP,
				yaw
			)
		) * ship_basis

		# Pitch around ship-local right.
		ship_basis = ship_basis * Basis(
			Quaternion(
				Vector3.RIGHT,
				pitch
			)
		)


	# ========================================================
	# ROLL
	# ========================================================

	var roll_input := 0.0

	if Input.is_action_pressed("roll_left"):
		roll_input -= 1.0

	if Input.is_action_pressed("roll_right"):
		roll_input += 1.0

	if roll_input != 0.0:

		ship_basis = ship_basis * Basis(
			Quaternion(
				Vector3.FORWARD,
				roll_input
				* rotation_speed
				* delta
			)
		)


	# ========================================================
	# CLEANUP
	# ========================================================

	ship_basis = (
		ship_basis.orthonormalized()
	)


	# ========================================================
	# APPLY ROTATION
	# ========================================================

	global_transform.basis = ship_basis


	# ========================================================
	# APPLY LINEAR MOMENTUM
	# ========================================================

	global_position += (
		ship_velocity * delta
	)


# ============================================================
# APPLY SHIP MOTION TO CONTENTS
# ============================================================

func apply_ship_motion(
	old_transform: Transform3D
) -> void:

	var new_transform := global_transform

	# Ship didn't move.
	if old_transform == new_transform:
		return

	for body in ship_contents:

		if not is_instance_valid(body):
			continue

		if body == self:
			continue

		# Only players and grabbable objects inherit
		# the ship's movement.
		if (
			not body.is_in_group("Grabbable")
			and not body.is_in_group("Players")
		):
			continue

		# Calculate the object's transform relative to
		# the ship before the ship moved.
		var relative_transform := (
			old_transform.affine_inverse()
			* body.global_transform
		)

		# Apply the ship's movement.
		body.global_transform = (
			new_transform
			* relative_transform
		)
