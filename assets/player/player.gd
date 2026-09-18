extends CharacterBody3D


# ============================================================
# MOVEMENT
# ============================================================

@export var speed := 5.0
@export var sprint_speed := 8.0
@export var jump_velocity := 4.5
@export var gravity := 9.8

# Mouse
@export var mouse_sensitivity := 0.003
@export var max_pitch := 89.0

# Crouch
@export var crouch_camera_height := 1.0
@export var crouch_speed_multiplier := 0.5
@export var crouch_transition_speed := 6.0


# ============================================================
# STAMINA
# ============================================================

@export var max_stamina := 100.0
@export var stamina_drain_rate := 20.0
@export var stamina_regen_rate := 15.0
@export var stamina_regen_delay := 3.0

var stamina: float = 100.0
var stamina_regen_delay_timer: float = 0.0
var is_sprinting := false


# ============================================================
# ZERO-G / THRUSTERS
# ============================================================

@export var zero_g_thrust := 3.0
@export var zero_g_max_speed := 8.0
@export var zero_g_boost_multiplier := 2.0
@export var zero_g_rotation_speed := 1.5

@export var max_thruster_fuel := 100.0
@export var thruster_fuel_drain_rate := 10.0
@export var thruster_fuel_regen_rate := 5.0
@export var thruster_boost_fuel_multiplier := 2.0

var thruster_fuel: float = 100.0
var zero_gravity := false


# ============================================================
# OBJECT INTERACTION
# ============================================================

@export var throw_force := 50.0
@export var hold_rotate_force := 8.0

@export var hold_distance := 2.0
@export var min_hold_distance := 1.0
@export var max_hold_distance := 4.5
@export var hold_scroll_amount := 0.5

var held_object: RigidBody3D = null
var held_ui_local_position := Vector3.ZERO
var target_angular_velocity := Vector3.ZERO


# ============================================================
# CAMERA
# ============================================================

@export var camera_height := 1.6

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D

var yaw := 0.0
var pitch := 0.0


# ============================================================
# PLAYER STATE
# ============================================================

var is_crouching := false

var controlling_ship := false
var controlled_ship: Node3D = null


# ============================================================
# UI
# ============================================================

@onready var player_ui: CanvasLayer = $PlayerUI
@onready var grab_ui = $PlayerUI/GrabUI

@onready var player_id_label = $player_id_label

@onready var object_name_label: Label = (
	$PlayerUI/UIContainer/CenterUI/VBoxContainer/ObjectInfo
)

@onready var object_value_label: Label = (
	$PlayerUI/UIContainer/CenterUI/VBoxContainer/ObjectValue
)

@onready var interact_prompt: Label = (
	$PlayerUI/UIContainer/CenterUI/InteractPrompt
)

@onready var stamina_bar: ProgressBar = (
	$PlayerUI/UIContainer/CornerUI/VBoxContainer/StaminaBar
)

@onready var thruster_bar: ProgressBar = (
	$PlayerUI/UIContainer/CornerUI/VBoxContainer/ThrusterBar
)

@onready var debug_info: Label = $PlayerUI/DebugInfo


# ============================================================
# PLAYER MODEL
# ============================================================

@onready var playermodel = $playermodel


# ============================================================
# MULTIPLAYER
# ============================================================

func _enter_tree() -> void:
	set_multiplayer_authority(int(name))


# ============================================================
# INITIALIZATION
# ============================================================

func _ready() -> void:
	add_to_group("Players")

	player_id_label.text = name

	# Camera setup
	camera_pivot.top_level = false
	camera_pivot.position = Vector3(0.0, camera_height, 0.0)
	camera_pivot.rotation = Vector3.ZERO

	camera_3d.position = Vector3.ZERO
	camera_3d.rotation = Vector3.ZERO

	yaw = rotation.y
	pitch = 0.0

	# Resource setup
	stamina = max_stamina
	thruster_fuel = max_thruster_fuel

	stamina_bar.min_value = 0.0
	stamina_bar.max_value = 100.0
	stamina_bar.value = 100.0

	thruster_bar.min_value = 0.0
	thruster_bar.max_value = 100.0
	thruster_bar.value = 100.0
	thruster_bar.visible = false

	# --------------------------------------------------------
	# LOCAL PLAYER
	# --------------------------------------------------------

	if is_multiplayer_authority():
		camera_3d.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

		# Only the local player gets a visible UI.
		player_ui.show()

		# Hide our own character model.
		playermodel.hide()

	# --------------------------------------------------------
	# REMOTE PLAYERS
	# --------------------------------------------------------

	else:
		# Remote players should never display their UI.
		player_ui.hide()

		# Remote players should display their character model.
		playermodel.show()


# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if not is_multiplayer_authority():
		return

	if controlling_ship:
		return

	handle_mouse_motion(event)
	handle_mouse_buttons(event)
	handle_keyboard_input(event)


# ============================================================
# MOUSE LOOK
# ============================================================

func handle_mouse_motion(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return

	# --------------------------------------------------------
	# HELD OBJECT ROTATION
	# --------------------------------------------------------

	if held_object and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mouse_delta: Vector2 = event.relative
		var camera_basis: Basis = camera_pivot.global_transform.basis

		target_angular_velocity = (
			camera_basis.y * mouse_delta.x
			+ camera_basis.x * mouse_delta.y
		) * hold_rotate_force * 0.01

		return

	# --------------------------------------------------------
	# NORMAL GRAVITY
	# --------------------------------------------------------

	if not zero_gravity:
		handle_normal_mouse_look(event)
		return

	# --------------------------------------------------------
	# ZERO-G
	# --------------------------------------------------------

	handle_zero_g_mouse_look(event)


func handle_normal_mouse_look(event: InputEventMouseMotion) -> void:
	var yaw_delta: float = (
		-event.relative.x * mouse_sensitivity
	)

	var pitch_delta: float = (
		-event.relative.y * mouse_sensitivity
	)

	# Horizontal rotation
	rotate_y(yaw_delta)

	yaw = rotation.y

	# Vertical camera rotation
	pitch += pitch_delta

	pitch = clamp(
		pitch,
		deg_to_rad(-max_pitch),
		deg_to_rad(max_pitch)
	)

	camera_pivot.rotation = Vector3(
		pitch,
		0.0,
		0.0
	)


func handle_zero_g_mouse_look(event: InputEventMouseMotion) -> void:
	# Keep the camera stationary while rotating the player.
	var camera_position_before := camera_3d.global_position

	var b: Basis = global_transform.basis

	# Yaw
	b = b.rotated(
		b.y.normalized(),
		-event.relative.x * mouse_sensitivity
	)

	# Pitch
	b = b.rotated(
		b.x.normalized(),
		-event.relative.y * mouse_sensitivity
	)

	global_transform.basis = b.orthonormalized()

	# Compensate for the camera moving around the Player origin.
	var camera_position_after := camera_3d.global_position

	global_position += (
		camera_position_before
		- camera_position_after
	)

	camera_pivot.rotation = Vector3.ZERO


# ============================================================
# MOUSE BUTTONS
# ============================================================

func handle_mouse_buttons(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	if not event.pressed:
		return

	if not held_object:
		return

	match event.button_index:
		MOUSE_BUTTON_WHEEL_DOWN:
			hold_distance -= hold_scroll_amount

		MOUSE_BUTTON_WHEEL_UP:
			hold_distance += hold_scroll_amount

		_:
			return

	hold_distance = clamp(
		hold_distance,
		min_hold_distance,
		max_hold_distance
	)


# ============================================================
# KEYBOARD INPUT
# ============================================================

func handle_keyboard_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	if not event.pressed:
		return

	if event.keycode != KEY_ESCAPE:
		return

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ============================================================
# PHYSICS
# ============================================================

func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if not is_multiplayer_authority():
		return

	if controlling_ship:
		return

	update_crouch(delta)
	update_resources(delta)
	update_held_object()

	if zero_gravity:
		handle_zero_g_movement(delta)
	else:
		handle_normal_movement(delta)


# ============================================================
# RESOURCE MANAGEMENT
# ============================================================

func update_resources(delta: float) -> void:
	# Stamina
	if is_sprinting:
		stamina_regen_delay_timer = stamina_regen_delay
	else:
		if stamina_regen_delay_timer > 0.0:
			stamina_regen_delay_timer -= delta
		else:
			stamina += stamina_regen_rate * delta

	stamina = clamp(
		stamina,
		0.0,
		max_stamina
	)

	# Thruster fuel
	thruster_fuel += (
		thruster_fuel_regen_rate * delta
	)

	thruster_fuel = clamp(
		thruster_fuel,
		0.0,
		max_thruster_fuel
	)


func update_resource_bars() -> void:
	stamina_bar.value = (
		stamina / max_stamina
	) * 100.0

	thruster_bar.value = (
		thruster_fuel / max_thruster_fuel
	) * 100.0

	thruster_bar.visible = zero_gravity


# ============================================================
# HELD OBJECT
# ============================================================

func update_held_object() -> void:
	if held_object:
		grab_ui.show()

		var camera_basis: Basis = (
			camera_pivot.global_transform.basis
		)

		var target_position: Vector3 = (
			camera_3d.global_position
			- camera_basis.z * hold_distance
		)

		rpc_id(
			1,
			"hold_object",
			held_object.get_path(),
			target_position,
			camera_basis,
			target_angular_velocity
		)

	target_angular_velocity = Vector3.ZERO


# ============================================================
# ZERO-G MOVEMENT
# ============================================================

func handle_zero_g_movement(delta: float) -> void:
	var camera_basis: Basis = (
		camera_pivot.global_transform.basis
	)

	var thrust_direction := Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		thrust_direction -= camera_basis.z

	if Input.is_action_pressed("move_backward"):
		thrust_direction += camera_basis.z

	if Input.is_action_pressed("move_left"):
		thrust_direction -= camera_basis.x

	if Input.is_action_pressed("move_right"):
		thrust_direction += camera_basis.x

	if Input.is_action_pressed("move_up"):
		thrust_direction += camera_basis.y

	if Input.is_action_pressed("move_down"):
		thrust_direction -= camera_basis.y

	# Thrust
	if (
		thrust_direction.length() > 0.0
		and thruster_fuel > 0.0
	):
		thrust_direction = thrust_direction.normalized()

		var thrust_power: float = zero_g_thrust
		var fuel_multiplier: float = 1.0

		if Input.is_action_pressed("thrust_boost"):
			thrust_power *= zero_g_boost_multiplier
			fuel_multiplier = thruster_boost_fuel_multiplier

		velocity += (
			thrust_direction
			* thrust_power
			* delta
		)

		thruster_fuel -= (
			thruster_fuel_drain_rate
			* fuel_multiplier
			* delta
		)

		thruster_fuel = max(
			thruster_fuel,
			0.0
		)

	# Speed limit
	if velocity.length() > zero_g_max_speed:
		velocity = (
			velocity.normalized()
			* zero_g_max_speed
		)

	# Roll
	handle_zero_g_roll(delta)

	camera_pivot.rotation = Vector3.ZERO

	move_and_slide()
	update_resource_bars()


func handle_zero_g_roll(delta: float) -> void:
	var roll_input := 0.0

	if Input.is_action_pressed("roll_left"):
		roll_input -= 1.0

	if Input.is_action_pressed("roll_right"):
		roll_input += 1.0

	if roll_input == 0.0:
		return

	# Keep the camera stationary while rolling.
	var camera_position_before := camera_3d.global_position

	var b: Basis = global_transform.basis

	# Roll around local forward axis.
	var roll_axis := -b.z.normalized()

	b = b.rotated(
		roll_axis,
		roll_input
		* zero_g_rotation_speed
		* delta
	)

	global_transform.basis = b.orthonormalized()

	# Compensate for movement around the Player origin.
	var camera_position_after := camera_3d.global_position

	global_position += (
		camera_position_before
		- camera_position_after
	)


# ============================================================
# NORMAL MOVEMENT
# ============================================================

func handle_normal_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if (
		Input.is_action_just_pressed("jump")
		and is_on_floor()
	):
		velocity.y = jump_velocity

	var camera_basis: Basis = (
		camera_pivot.global_transform.basis
	)

	var forward_input := 0.0
	var right_input := 0.0

	if Input.is_action_pressed("move_forward"):
		forward_input += 1.0

	if Input.is_action_pressed("move_backward"):
		forward_input -= 1.0

	if Input.is_action_pressed("move_right"):
		right_input += 1.0

	if Input.is_action_pressed("move_left"):
		right_input -= 1.0

	var normal_forward: Vector3 = -camera_basis.z
	normal_forward.y = 0.0

	var normal_right: Vector3 = camera_basis.x
	normal_right.y = 0.0

	if normal_forward.length() > 0.001:
		normal_forward = normal_forward.normalized()

	if normal_right.length() > 0.001:
		normal_right = normal_right.normalized()

	var direction: Vector3 = (
		normal_forward * forward_input
		+ normal_right * right_input
	)

	if direction.length() > 0.0:
		direction = direction.normalized()

	var current_speed: float = speed

	is_sprinting = (
		Input.is_action_pressed("sprint")
		and stamina > 0.0
		and not is_crouching
	)

	if is_sprinting:
		current_speed = sprint_speed

		stamina -= (
			stamina_drain_rate * delta
		)

		if stamina <= 0.0:
			stamina = 0.0
			stamina_regen_delay_timer = stamina_regen_delay

	if is_crouching:
		current_speed *= crouch_speed_multiplier

	stamina = clamp(
		stamina,
		0.0,
		max_stamina
	)

	if direction.length() > 0.0:
		velocity.x = (
			direction.x * current_speed
		)

		velocity.z = (
			direction.z * current_speed
		)
	else:
		velocity.x = move_toward(
			velocity.x,
			0.0,
			speed
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			speed
		)

	if not is_sprinting:
		is_sprinting = false

	move_and_slide()
	update_resource_bars()


# ============================================================
# CROUCH
# ============================================================

func update_crouch(delta: float) -> void:
	if zero_gravity:
		is_crouching = false

		camera_pivot.position.y = move_toward(
			camera_pivot.position.y,
			camera_height,
			crouch_transition_speed * delta
		)

		return

	is_crouching = Input.is_action_pressed("crouch")

	var target_height: float = camera_height

	if is_crouching:
		target_height = crouch_camera_height

	camera_pivot.position.y = move_toward(
		camera_pivot.position.y,
		target_height,
		crouch_transition_speed * delta
	)


# ============================================================
# FRAME PROCESSING
# ============================================================

func _process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if not is_multiplayer_authority():
		return

	if controlling_ship:
		return

	update_debug_info()
	update_object_info()
	update_grab_ui()

	# Throw first so throwing takes priority over interaction.
	handle_throw()
	handle_interaction()


# ============================================================
# INTERACTION
# ============================================================

func handle_interaction() -> void:
	if not Input.is_action_just_pressed("interact"):
		return

	# Drop held object
	if held_object:
		drop_object.rpc_id(
			1,
			held_object.get_path()
		)

		held_object = null
		grab_ui.hide()

		return

	var ray: RayCast3D = (
		camera_3d.get_node("interact_ray")
	)

	print("F PRESSED")

	if not ray.is_colliding():
		print("RAY IS NOT COLLIDING")
		return

	var object = ray.get_collider()

	print("RAY HIT: ", object)
	print("TYPE: ", object.get_class())
	print("GROUPS: ", object.get_groups())

	# Interactable objects
	if object.is_in_group("Interactable"):
		print("OBJECT IS INTERACTABLE")

		if object.has_method("interact"):
			print("CALLING INTERACT()")
			object.interact()
		else:
			print("OBJECT HAS NO INTERACT()")

		return

	# Physical objects
	if object is RigidBody3D:
		held_object = object

		var hit_position: Vector3 = (
			ray.get_collision_point()
		)

		held_ui_local_position = (
			held_object.global_transform.affine_inverse()
			* hit_position
		)


# ============================================================
# THROWING
# ============================================================

func handle_throw() -> void:
	if not Input.is_action_just_pressed("left_click"):
		return

	if not held_object:
		return

	var object: RigidBody3D = held_object

	held_object = null
	grab_ui.hide()

	var camera_basis: Basis = (
		camera_pivot.global_transform.basis
	)

	var throw_strength: float = (
		throw_force
		* (10.0 / max(object.mass, 0.1))
	)

	throw_object.rpc_id(
		1,
		object.get_path(),
		-camera_basis.z,
		throw_strength
	)


# ============================================================
# DEBUG
# ============================================================

func update_debug_info() -> void:
	debug_info.text = (
		"Position: X %.2f  Y %.2f  Z %.2f\n"
		% [
			global_position.x,
			global_position.y,
			global_position.z
		]
		+ "Velocity: X %.2f  Y %.2f  Z %.2f\n"
		% [
			velocity.x,
			velocity.y,
			velocity.z
		]
		+ "Speed: %.2f m/s"
		% velocity.length()
	)


# ============================================================
# SERVER-SIDE OBJECT RPCS
# ============================================================

@rpc("any_peer", "unreliable", "call_local")
func hold_object(
	object_path: NodePath,
	target_position: Vector3,
	camera_basis: Basis,
	target_rotation_velocity: Vector3
):
	if not multiplayer.is_server():
		return

	var object = (
		get_tree()
		.current_scene
		.get_node_or_null(object_path)
	)

	if object == null:
		return

	if not object is RigidBody3D:
		return

	var rigidbody := object as RigidBody3D

	var spring_strength := 80.0
	var damping := 12.0

	if zero_gravity:
		spring_strength = 350.0
		damping = 35.0

	var offset := (
		target_position
		- rigidbody.global_position
	)

	var force := offset * spring_strength

	force -= (
		rigidbody.linear_velocity
		* damping
	)

	rigidbody.apply_central_force(force)

	var rotation_smoothing := 15.0

	if zero_gravity:
		rotation_smoothing = 30.0

	rigidbody.angular_velocity = (
		rigidbody.angular_velocity.lerp(
			target_rotation_velocity,
			rotation_smoothing
			* get_physics_process_delta_time()
		)
	)


@rpc("any_peer", "reliable", "call_local")
func drop_object(object_path: NodePath):
	if not multiplayer.is_server():
		return

	var object: Node = (
		get_tree()
		.current_scene
		.get_node_or_null(object_path)
	)

	if object is RigidBody3D:
		(object as RigidBody3D).sleeping = false


@rpc("any_peer", "reliable", "call_local")
func throw_object(
	object_path: NodePath,
	throw_direction: Vector3,
	force: float
):
	if not multiplayer.is_server():
		return

	var object: Node = (
		get_tree()
		.current_scene
		.get_node_or_null(object_path)
	)

	if object is RigidBody3D:
		var rigidbody: RigidBody3D = (
			object as RigidBody3D
		)

		rigidbody.sleeping = false

		rigidbody.apply_central_impulse(
			throw_direction * force
		)


# ============================================================
# ZERO-G STATE
# ============================================================

func set_zero_gravity(enabled: bool) -> void:
	if zero_gravity == enabled:
		return

	# --------------------------------------------------------
	# ENTER ZERO-G
	# --------------------------------------------------------

	if enabled:
		var camera_basis: Basis = (
			camera_3d.global_transform.basis
			.orthonormalized()
		)

		# Transfer the camera's complete orientation
		# to the Player.
		global_transform.basis = camera_basis

		camera_pivot.rotation = Vector3.ZERO

		yaw = rotation.y
		pitch = 0.0

		zero_gravity = true

		return

	# --------------------------------------------------------
	# EXIT ZERO-G
	# --------------------------------------------------------

	var forward: Vector3 = (
		-camera_3d.global_transform.basis.z
	)

	# Calculate horizontal yaw.
	var horizontal_forward := Vector3(
		forward.x,
		0.0,
		forward.z
	)

	if horizontal_forward.length() > 0.001:
		horizontal_forward = horizontal_forward.normalized()

		var new_yaw := atan2(
			-horizontal_forward.x,
			-horizontal_forward.z
		)

		rotation = Vector3(
			0.0,
			new_yaw,
			0.0
		)

		yaw = new_yaw

	# Calculate pitch.
	pitch = asin(
		clamp(
			forward.y,
			-1.0,
			1.0
		)
	)

	pitch = clamp(
		pitch,
		deg_to_rad(-max_pitch),
		deg_to_rad(max_pitch)
	)

	camera_pivot.rotation = Vector3(
		pitch,
		0.0,
		0.0
	)

	zero_gravity = false


# ============================================================
# OBJECT UI
# ============================================================

func update_object_info() -> void:
	var ray: RayCast3D = (
		camera_3d.get_node("interact_ray")
	)

	if not ray.is_colliding():
		object_name_label.text = ""
		object_value_label.text = ""
		interact_prompt.text = ""
		return

	var object: Node = ray.get_collider()

	# --------------------------------------------------------
	# INTERACTABLE DETECTION
	# --------------------------------------------------------

	var interactable := false
	var current_node: Node = object

	while current_node != null:
		if current_node.is_in_group("Interactable"):
			interactable = true
			break

		current_node = current_node.get_parent()

	if interactable:
		interact_prompt.text = "[F] - Interact"
	else:
		interact_prompt.text = ""

	# --------------------------------------------------------
	# PHYSICAL OBJECT INFORMATION
	# --------------------------------------------------------

	if object is RigidBody3D:
		var physical_object := object as RigidBody3D

		if "object_definition" in physical_object:
			var definition: ObjectDefinition = (
				physical_object.object_definition
			)

			if definition:
				var rarity_color: Color = (
					get_rarity_color(
						physical_object.rarity
					)
				)

				object_name_label.text = (
					definition.object_name
				)

				object_value_label.text = (
					"$" + str(
						physical_object.sell_value
					)
				)

				object_name_label.modulate = rarity_color
				object_value_label.modulate = rarity_color

				return

	# No physical object information.
	object_name_label.text = ""
	object_value_label.text = ""


func get_rarity_color(rarity: String) -> Color:
	match rarity:
		"Common":
			return Color.WHITE

		"Uncommon":
			return Color("#55FF55")

		"Rare":
			return Color("#5599FF")

		"Epic":
			return Color("#CC55FF")

		"Legendary":
			return Color("#FFAA00")

		_:
			return Color.WHITE


# ============================================================
# GRAB UI
# ============================================================

func update_grab_ui() -> void:
	if held_object == null:
		grab_ui.hide()
		return

	var world_position: Vector3 = (
		held_object.global_transform
		* held_ui_local_position
	)

	if camera_3d.is_position_behind(world_position):
		grab_ui.hide()
		return

	var screen_position: Vector2 = (
		camera_3d.unproject_position(world_position)
	)

	grab_ui.position = (
		screen_position
		+ Vector2(-5, -5)
	)

	grab_ui.show()


# ============================================================
# SHIP CONTROL
# ============================================================

func set_ship_control(
	ship: Node3D,
	enabled: bool
) -> void:
	controlling_ship = enabled
	controlled_ship = ship if enabled else null
