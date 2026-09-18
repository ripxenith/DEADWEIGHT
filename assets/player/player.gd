extends CharacterBody3D

@export var speed := 5.0
@export var sprint_speed := 8.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.003
@export var gravity := 9.8
@export var throw_force := 50.0
@export var hold_rotate_force := 8.0

@export var hold_distance := 2.0
@export var min_hold_distance := 1.0
@export var max_hold_distance := 4.5
@export var hold_scroll_amount := 0.5

# Stamina
@export var max_stamina := 100.0
@export var stamina_drain_rate := 20.0
@export var stamina_regen_rate := 15.0
var stamina_regen_delay_timer: float = 0.0
@export var stamina_regen_delay := 3.0

# Crouch
@export var crouch_camera_height := 1.0
@export var crouch_speed_multiplier := 0.5
@export var crouch_transition_speed := 6.0

# Thruster Fuel
var thruster_fuel: float = 100.0
@export var max_thruster_fuel := 100.0
@export var thruster_fuel_drain_rate := 10.0
@export var thruster_fuel_regen_rate := 5.0
@export var thruster_boost_fuel_multiplier := 2.0

@onready var object_name_label: Label = $PlayerUI/UIContainer/CenterUI/VBoxContainer/ObjectInfo
@onready var object_value_label: Label = $PlayerUI/UIContainer/CenterUI/VBoxContainer/ObjectValue
@onready var interact_prompt: Label = $PlayerUI/UIContainer/CenterUI/InteractPrompt

# Camera
@export var camera_height := 1.6
@export var max_pitch := 89.0

# Zero-G
@export var zero_g_thrust := 3.0
@export var zero_g_max_speed := 8.0
@export var zero_g_boost_multiplier := 2.0
@export var zero_g_rotation_speed := 1.5

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var head: Node3D = $head
@onready var player_id_label = $player_id_label
@onready var player_ui: CanvasLayer = $PlayerUI
@onready var grab_ui = $PlayerUI/GrabUI

@onready var stamina_bar: ProgressBar = $PlayerUI/UIContainer/CornerUI/VBoxContainer/StaminaBar
@onready var thruster_bar: ProgressBar = $PlayerUI/UIContainer/CornerUI/VBoxContainer/ThrusterBar

# Debug UI
@onready var debug_info: Label = $PlayerUI/DebugInfo

var held_object: RigidBody3D = null
var held_ui_local_position := Vector3.ZERO
var target_angular_velocity := Vector3.ZERO

var zero_gravity := false

# Normal gravity camera angles
var yaw := 0.0
var pitch := 0.0

# Stamina
var stamina: float = 100.0
var is_sprinting := false

# Crouch
var is_crouching := false


func _enter_tree() -> void:
	set_multiplayer_authority(int(name))


func _ready() -> void:
	add_to_group("Players")
	player_id_label.text = name

	camera_pivot.top_level = false
	camera_pivot.position = Vector3(0.0, camera_height, 0.0)
	camera_pivot.rotation = Vector3.ZERO
	camera_3d.position = Vector3.ZERO
	camera_3d.rotation = Vector3.ZERO
	yaw = 0.0
	pitch = 0.0

	stamina = max_stamina
	thruster_fuel = max_thruster_fuel

	stamina_bar.min_value = 0.0
	stamina_bar.max_value = 100.0
	stamina_bar.value = 100.0

	thruster_bar.min_value = 0.0
	thruster_bar.max_value = 100.0
	thruster_bar.value = 100.0
	thruster_bar.visible = false

	if is_multiplayer_authority():
		camera_3d.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if controlling_ship:
		return

	if event is InputEventMouseMotion:
		if held_object and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			var mouse_delta: Vector2 = event.relative
			var camera_basis: Basis = camera_pivot.global_transform.basis

			target_angular_velocity = (
				camera_basis.y * mouse_delta.x
				+ camera_basis.x * mouse_delta.y
			) * hold_rotate_force * 0.01
			return

		if not zero_gravity:
			yaw -= event.relative.x * mouse_sensitivity
			pitch -= event.relative.y * mouse_sensitivity
			pitch = clamp(
				pitch,
				deg_to_rad(-max_pitch),
				deg_to_rad(max_pitch)
			)
			camera_pivot.rotation = Vector3.ZERO
			camera_pivot.rotate_y(yaw)
			camera_pivot.rotate_object_local(Vector3.RIGHT, pitch)
		else:
			var b: Basis = camera_pivot.transform.basis
			b = b.rotated(
				b.y.normalized(),
				-event.relative.x * mouse_sensitivity
			)
			b = b.rotated(
				b.x.normalized(),
				-event.relative.y * mouse_sensitivity
			)
			camera_pivot.transform.basis = b.orthonormalized()

	if event is InputEventMouseButton and event.pressed:
		if held_object:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				hold_distance -= hold_scroll_amount
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				hold_distance += hold_scroll_amount
			hold_distance = clamp(
				hold_distance,
				min_hold_distance,
				max_hold_distance
			)

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_multiplayer_authority():
		return

	if controlling_ship:
		return

	update_crouch(delta)

	# ============================================================
	# RESOURCE REGENERATION
	# These happen regardless of gravity state.
	# ============================================================

	# Stamina regeneration
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

	# Thruster fuel regeneration
	thruster_fuel += thruster_fuel_regen_rate * delta

	thruster_fuel = clamp(
		thruster_fuel,
		0.0,
		max_thruster_fuel
	)

	if held_object:
		grab_ui.show()

		var camera_basis: Basis = camera_pivot.global_transform.basis
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
	# ZERO GRAVITY
	# ============================================================

	if zero_gravity:
		var camera_basis: Basis = camera_pivot.global_transform.basis
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

		if thrust_direction.length() > 0.0 and thruster_fuel > 0.0:
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

			# Drain fuel only when actually using the thrusters.
			thruster_fuel -= (
				thruster_fuel_drain_rate
				* fuel_multiplier
				* delta
			)

			thruster_fuel = max(
				thruster_fuel,
				0.0
			)

		if velocity.length() > zero_g_max_speed:
			velocity = (
				velocity.normalized()
				* zero_g_max_speed
			)

		var roll_input := 0.0

		if Input.is_action_pressed("roll_left"):
			roll_input -= 1.0

		if Input.is_action_pressed("roll_right"):
			roll_input += 1.0

		if roll_input != 0.0:
			var b: Basis = camera_pivot.transform.basis
			var roll_axis: Vector3 = -b.z.normalized()

			b = b.rotated(
				roll_axis,
				roll_input
				* zero_g_rotation_speed
				* delta
			)

			camera_pivot.transform.basis = b.orthonormalized()

		move_and_slide()
		update_resource_bars()
		return

	# ============================================================
	# NORMAL GRAVITY
	# ============================================================

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var camera_basis: Basis = camera_pivot.global_transform.basis
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

		stamina -= stamina_drain_rate * delta

		# Start the regen delay only when stamina actually reaches 0.
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
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
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


func update_resource_bars() -> void:
	stamina_bar.value = (
		stamina / max_stamina
	) * 100.0

	thruster_bar.value = (
		thruster_fuel / max_thruster_fuel
	) * 100.0

	thruster_bar.visible = zero_gravity


func update_crouch(delta: float) -> void:
	# Crouching is disabled in zero-G
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


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_multiplayer_authority():
		return

	if controlling_ship:
		return

	update_debug_info()
	update_object_info()
	update_grab_ui()

	if Input.is_action_just_pressed("left_click") and held_object:
		var object: RigidBody3D = held_object

		held_object = null
		grab_ui.hide()

		var camera_basis: Basis = camera_pivot.global_transform.basis

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

		return

	if Input.is_action_just_pressed("interact"):

		if held_object:
			drop_object.rpc_id(
				1,
				held_object.get_path()
			)
			held_object = null
			grab_ui.hide()
			return

		var ray: RayCast3D = camera_3d.get_node("interact_ray")

		print("F PRESSED")

		if not ray.is_colliding():
			print("RAY IS NOT COLLIDING")
			return

		var object = ray.get_collider()

		print("RAY HIT: ", object)
		print("TYPE: ", object.get_class())
		print("GROUPS: ", object.get_groups())

		if object.is_in_group("Interactable"):
			print("OBJECT IS INTERACTABLE")

			if object.has_method("interact"):
				print("CALLING INTERACT()")
				object.interact()
			else:
				print("OBJECT HAS NO INTERACT()")

			return

		if object is RigidBody3D:
			held_object = object

			var hit_position: Vector3 = ray.get_collision_point()

			held_ui_local_position = (
				held_object.global_transform
				.affine_inverse()
				* hit_position
			)


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

@rpc("any_peer", "unreliable")
func hold_object(
	object_path: NodePath,
	target_position: Vector3,
	camera_basis: Basis,
	target_rotation_velocity: Vector3
):
	if not multiplayer.is_server():
		return

	var object = get_tree().current_scene.get_node_or_null(object_path)

	if object == null:
		return

	if not object is RigidBody3D:
		return

	var rigidbody := object as RigidBody3D

	# ------------------------------------------------
	# HOLDING SETTINGS
	# ------------------------------------------------

	var spring_strength := 80.0
	var damping := 12.0

	# Zero-G objects need to follow the player much
	# more aggressively so they don't lag behind.
	if zero_gravity:
		spring_strength = 350.0
		damping = 35.0

	# ------------------------------------------------
	# POSITION
	# ------------------------------------------------

	var offset := target_position - rigidbody.global_position

	var force := offset * spring_strength

	# Counteract existing velocity.
	force -= rigidbody.linear_velocity * damping

	rigidbody.apply_central_force(force)

	# ------------------------------------------------
	# ROTATION
	# ------------------------------------------------

	var rotation_smoothing := 15.0

	if zero_gravity:
		rotation_smoothing = 30.0

	rigidbody.angular_velocity = rigidbody.angular_velocity.lerp(
		target_rotation_velocity,
		rotation_smoothing * get_physics_process_delta_time()
	)



@rpc("any_peer", "reliable")
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


@rpc("any_peer", "reliable")
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


func set_zero_gravity(enabled: bool) -> void:
	if zero_gravity == enabled:
		return

	zero_gravity = enabled

	if not enabled:
		var forward: Vector3 = (
			-camera_pivot.global_transform.basis.z
		)

		yaw = atan2(
			-forward.x,
			-forward.z
		)

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

		camera_pivot.rotation = Vector3.ZERO

		camera_pivot.rotate_y(yaw)

		camera_pivot.rotate_object_local(
			Vector3.RIGHT,
			pitch
		)

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

	# ------------------------------------------------------------
	# INTERACTABLE DETECTION
	# Check the collider and every parent above it.
	# ------------------------------------------------------------

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

	# ------------------------------------------------------------
	# PHYSICAL OBJECT INFORMATION
	# ------------------------------------------------------------

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

	# No physical object information
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

	grab_ui.position = screen_position + Vector2(-5, -5)
	grab_ui.show()

var controlling_ship := false
var controlled_ship: Node3D = null

func set_ship_control(ship: Node3D, enabled: bool) -> void:
	controlling_ship = enabled
	controlled_ship = ship if enabled else null
