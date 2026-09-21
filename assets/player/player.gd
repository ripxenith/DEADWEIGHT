extends CharacterBody3D


# ============================================================
# MOVEMENT
# ============================================================

@export var speed := 5.0
@export var sprint_speed := 8.0
@export var jump_velocity := 4.5
@export var gravity := 9.8

var mouse_sensitivity := 0.00001
@export var max_pitch := 89.0

@export var crouch_camera_height := 1.0
@export var crouch_speed_multiplier := 0.5
@export var crouch_transition_speed := 6.0


# ============================================================
# HEALTH
# ============================================================

@export var max_health := 100.0
@export var oxygen_damage_rate := 10.0

var health: float = 100.0
var is_dead := false


# ============================================================
# STAMINA
# ============================================================

@export var base_max_stamina := 100.0
@export var stamina_per_upgrade := 20.0

@export var stamina_drain_rate := 20.0
@export var stamina_regen_rate := 15.0
@export var stamina_regen_delay := 3.0

var max_stamina: float = 100.0
var stamina: float = 100.0
var stamina_regen_delay_timer: float = 0.0
var is_sprinting := false


# ============================================================
# ZERO-G / THRUSTERS
# ============================================================

@export var base_zero_g_thrust := 3.0
@export var thruster_thrust_per_upgrade := 0.25

@export var zero_g_max_speed := 8.0
@export var zero_g_boost_multiplier := 2.0
@export var zero_g_rotation_speed := 1.5

@export var base_max_thruster_fuel := 100.0
@export var thruster_fuel_per_upgrade := 20.0

@export var thruster_fuel_drain_rate := 10.0
@export var thruster_fuel_regen_rate := 5.0
@export var thruster_boost_fuel_multiplier := 2.0

var zero_g_thrust: float = 3.0
var max_thruster_fuel: float = 100.0
var thruster_fuel: float = 100.0
var zero_gravity := false


# ============================================================
# OXYGEN
# ============================================================

@export var base_max_oxygen := 100.0
@export var oxygen_per_upgrade := 20.0

@export var oxygen_drain_rate := 2.0
@export var oxygen_regen_rate := 25.0

var max_oxygen: float = 100.0
var oxygen: float = 100.0

var stamina_upgrade_level: int = 0
var thruster_upgrade_level: int = 0
var oxygen_upgrade_level: int = 0


# ============================================================
# OBJECT INTERACTION
# ============================================================

@export var throw_force := 50.0
@export var hold_rotate_force := 8.0

@export var hold_distance := 2.0
@export var min_hold_distance := 1.0
@export var max_hold_distance := 4.5
@export var hold_scroll_amount := 0.5

@export var player_strength := 100.0

var held_object: RigidBody3D = null
var held_ui_local_position := Vector3.ZERO
var target_angular_velocity := Vector3.ZERO

# SERVER ONLY.
# Static, so every player node on the host shares the same data.
const MAX_HOLDERS_PER_OBJECT := 4
const HOLD_TARGET_TIMEOUT_MS := 250

# object path (String) -> Array of peer ids currently holding it
static var _object_holders: Dictionary = {}

# object path (String) -> { peer_id: { position, angular, spring, damping, time } }
# The latest hold target streamed by each holder while an object is shared.
static var _hold_targets: Dictionary = {}


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

var player_display_name: String = "Player"

var pause_menu_open := false

var settings_menu: CanvasLayer = null


# ============================================================
# UI
# ============================================================

@onready var player_ui: CanvasLayer = $PlayerUI
@onready var pause_menu: MarginContainer = $PlayerUI/UIContainer/PauseMenu
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
	$PlayerUI/UIContainer/HUD/StaminaBar
)

@onready var stamina_label: Label = (
	$PlayerUI/UIContainer/HUD/StaminaLabel
)

@onready var thruster_bar: ProgressBar = (
	$PlayerUI/UIContainer/HUD/ThrusterBar
)

@onready var thruster_label: Label = (
	$PlayerUI/UIContainer/HUD/ThrusterLabel
)

@onready var oxygen_bar: ProgressBar = (
	$PlayerUI/UIContainer/HUD/VBoxContainer2/OxygenBar
)

@onready var health_bar: ProgressBar = (
	$PlayerUI/UIContainer/HUD/VBoxContainer/HealthBar
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
	# The player's node name is its ENet peer ID.
	set_multiplayer_authority(int(name))


func _exit_tree() -> void:
	# When a player leaves (or the host shuts down), make sure
	# nothing stays frozen forever under a dead authority.
	if not multiplayer.has_multiplayer_peer():
		return

	if not multiplayer.is_server():
		return

	var peer_id := int(str(name))

	if peer_id == 1:
		_object_holders.clear()
		_hold_targets.clear()
		return

	var orphaned: Array[String] = []

	for key in _object_holders.keys():
		if _object_holders[key].has(peer_id):
			orphaned.append(key)

	var scene := get_tree().current_scene

	if scene == null:
		return

	# Route through the HOST's player node, because this
	# node is being removed on the other peers as well.
	var host_player = scene.get_node_or_null("1")

	if host_player == null:
		return

	for key in orphaned:
		_remove_holder(
			NodePath(key),
			peer_id,
			Vector3.ZERO,
			Vector3.ZERO,
			Vector3.ZERO,
			host_player
		)


# ============================================================
# INITIALIZATION
# ============================================================

func _ready() -> void:
	add_to_group("Players")

	player_id_label.text = player_display_name

	# --------------------------------------------------------
	# CAMERA
	# --------------------------------------------------------

	camera_pivot.top_level = false

	camera_pivot.position = Vector3(
		0.0,
		camera_height,
		0.0
	)

	camera_pivot.rotation = Vector3.ZERO

	camera_3d.position = Vector3.ZERO
	camera_3d.rotation = Vector3.ZERO

	yaw = rotation.y
	pitch = 0.0

	# --------------------------------------------------------
	# RESOURCE SETUP
	# --------------------------------------------------------

	if is_multiplayer_authority():
		load_player_upgrades()

		health = max_health
		stamina = max_stamina
		thruster_fuel = max_thruster_fuel
		oxygen = max_oxygen

		is_dead = false

	# --------------------------------------------------------
	# HEALTH BAR
	# --------------------------------------------------------

	health_bar.min_value = 0.0
	health_bar.max_value = 100.0
	health_bar.value = 100.0

	# --------------------------------------------------------
	# STAMINA BAR
	# --------------------------------------------------------

	stamina_bar.min_value = 0.0
	stamina_bar.max_value = 100.0
	stamina_bar.value = 100.0

	# --------------------------------------------------------
	# THRUSTER BAR
	# --------------------------------------------------------

	thruster_bar.min_value = 0.0
	thruster_bar.max_value = 100.0
	thruster_bar.value = 100.0
	thruster_bar.visible = false

	# --------------------------------------------------------
	# OXYGEN BAR
	# --------------------------------------------------------

	oxygen_bar.min_value = 0.0
	oxygen_bar.max_value = 100.0
	oxygen_bar.value = 100.0
	oxygen_bar.visible = false

	# --------------------------------------------------------
	# PAUSE MENU
	# --------------------------------------------------------

	pause_menu_open = false

	# --------------------------------------------------------
	# LOCAL PLAYER
	# --------------------------------------------------------

	if is_multiplayer_authority():
		camera_3d.current = true

		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED
		)

		player_ui.show()
		playermodel.hide()
		settings_menu = get_tree().get_first_node_in_group("SettingsMenu")

	# --------------------------------------------------------
	# REMOTE PLAYERS
	# --------------------------------------------------------

	else:
		player_ui.hide()
		playermodel.show()


# ============================================================
# PLAYER UPGRADES
# ============================================================

func load_player_upgrades() -> void:
	if not is_multiplayer_authority():
		return

	var player_id: int = multiplayer.get_unique_id()

	stamina_upgrade_level = SaveManager.get_player_upgrade(
		player_id,
		"stamina"
	)

	max_stamina = (
		base_max_stamina
		+ stamina_upgrade_level * stamina_per_upgrade
	)

	thruster_upgrade_level = SaveManager.get_player_upgrade(
		player_id,
		"thrusters"
	)

	max_thruster_fuel = (
		base_max_thruster_fuel
		+ thruster_upgrade_level * thruster_fuel_per_upgrade
	)

	zero_g_thrust = (
		base_zero_g_thrust
		+ thruster_upgrade_level * thruster_thrust_per_upgrade
	)

	oxygen_upgrade_level = SaveManager.get_player_upgrade(
		player_id,
		"oxygen"
	)

	max_oxygen = (
		base_max_oxygen
		+ oxygen_upgrade_level * oxygen_per_upgrade
	)

	print_debug(
		"PLAYER UPGRADES: "
		+ "Stamina Lv."
		+ str(stamina_upgrade_level)
		+ " | Thrusters Lv."
		+ str(thruster_upgrade_level)
		+ " | Oxygen Lv."
		+ str(oxygen_upgrade_level)
	)

	print_debug(
		"PLAYER STATS: "
		+ "Health "
		+ str(max_health)
		+ " | Health "
		+ str(max_health)
		+ " | Thruster Fuel "
		+ str(max_thruster_fuel)
		+ " | Thrust "
		+ str(zero_g_thrust)
		+ " | Oxygen "
		+ str(max_oxygen)
	)


# ============================================================
# HEALTH
# ============================================================

func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return

	if is_dead:
		return

	health -= amount

	health = clamp(
		health,
		0.0,
		max_health
	)

	print_debug(
		"PLAYER DAMAGE: "
		+ str(amount)
		+ " | Health: "
		+ str(health)
		+ "/"
		+ str(max_health)
	)

	if health <= 0.0:
		die()


func heal(amount: float) -> void:
	if amount <= 0.0:
		return

	if is_dead:
		return

	health += amount

	health = clamp(
		health,
		0.0,
		max_health
	)


func die() -> void:
	if is_dead:
		return

	is_dead = true

	health = 0.0
	velocity = Vector3.ZERO

	# A dead player must not keep holding an object.
	release_held_object()

	print_debug(
		"PLAYER DIED: "
		+ player_display_name
	)


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

	if event is InputEventMouseMotion:
		handle_mouse_motion(event)

	elif event is InputEventMouseButton:
		handle_mouse_buttons(event)

# ============================================================
# MOUSE LOOK
# ============================================================

func handle_mouse_motion(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return

	if pause_menu_open:
		return

	if (
		is_instance_valid(held_object)
		and Input.is_mouse_button_pressed(
			MOUSE_BUTTON_RIGHT
		)
	):
		var mouse_delta: Vector2 = event.relative

		var camera_basis: Basis = (
			camera_pivot.global_transform.basis
		)

		target_angular_velocity = (
			camera_basis.y * mouse_delta.x
			+ camera_basis.x * mouse_delta.y
		) * hold_rotate_force * 0.01

		return

	if not zero_gravity:
		handle_normal_mouse_look(event)
		return

	handle_zero_g_mouse_look(event)


func handle_normal_mouse_look(
	event: InputEventMouseMotion
) -> void:

	var yaw_delta: float = (
		-event.relative.x * mouse_sensitivity
	)

	var pitch_delta: float = (
		-event.relative.y * mouse_sensitivity
	)

	rotate_y(yaw_delta)

	yaw = rotation.y

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


func handle_zero_g_mouse_look(
	event: InputEventMouseMotion
) -> void:

	var camera_position_before := (
		camera_3d.global_position
	)

	var b: Basis = global_transform.basis

	b = b.rotated(
		b.y.normalized(),
		-event.relative.x * mouse_sensitivity
	)

	b = b.rotated(
		b.x.normalized(),
		-event.relative.y * mouse_sensitivity
	)

	global_transform.basis = (
		b.orthonormalized()
	)

	var camera_position_after := (
		camera_3d.global_position
	)

	global_position += (
		camera_position_before
		- camera_position_after
	)

	camera_pivot.rotation = Vector3.ZERO


# ============================================================
# MOUSE BUTTONS
# ============================================================

func handle_mouse_buttons(
	event: InputEventMouseButton
) -> void:

	if not event.pressed:
		return

	if not is_instance_valid(held_object):
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
# PHYSICS
# ============================================================

func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if not is_multiplayer_authority():
		return

	# The host applies the combined pull of everyone sharing an
	# object. Only the host's own player node passes the checks
	# above on the server, so this runs exactly once per frame,
	# even while the host is paused or dead.
	if multiplayer.is_server():
		_server_update_shared_objects()

	if controlling_ship:
		return

	if pause_menu_open:
		return

	if is_dead:
		update_resource_bars()
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

	thruster_fuel += (
		thruster_fuel_regen_rate * delta
	)

	thruster_fuel = clamp(
		thruster_fuel,
		0.0,
		max_thruster_fuel
	)

	if zero_gravity:
		oxygen -= oxygen_drain_rate * delta
	else:
		oxygen += oxygen_regen_rate * delta

	oxygen = clamp(
		oxygen,
		0.0,
		max_oxygen
	)

	if oxygen <= 0.0:
		take_damage(
			oxygen_damage_rate * delta
		)


func update_resource_bars() -> void:

	if max_health > 0.0:
		health_bar.value = (
			health / max_health
		) * 100.0

	if max_stamina > 0.0:
		stamina_bar.value = (
			stamina / max_stamina
		) * 100.0

	if max_thruster_fuel > 0.0:
		thruster_bar.value = (
			thruster_fuel / max_thruster_fuel
		) * 100.0

	if max_oxygen > 0.0:
		oxygen_bar.value = (
			oxygen / max_oxygen
		) * 100.0

	thruster_bar.visible = zero_gravity
	thruster_label.visible = zero_gravity

	stamina_bar.visible = !zero_gravity
	stamina_label.visible = !zero_gravity

	oxygen_bar.visible = true
	health_bar.visible = true


# ============================================================
# HELD OBJECT
# ============================================================

func update_held_object() -> void:

	# The object may have been freed (sold, destroyed...).
	if held_object != null and not is_instance_valid(held_object):
		held_object = null
		grab_ui.hide()

	if held_object:
		grab_ui.show()

		var camera_basis: Basis = (
			camera_pivot.global_transform.basis
		)

		var target_position: Vector3 = (
			camera_3d.global_position
			- camera_basis.z * hold_distance
		)

		# Sole holder: we own the object and simulate it.
		# Shared (or authority transfer still pending): the
		# object is not ours to simulate, so we stream where we
		# want it and the host combines everyone's pull.
		if _simulates_held_object_locally():
			update_local_held_object(
				target_position,
				camera_basis
			)
		else:
			_send_hold_target(target_position)

	target_angular_velocity = Vector3.ZERO


func update_local_held_object(
	target_position: Vector3,
	camera_basis: Basis
) -> void:

	if held_object == null:
		return

	var hold_params := _get_hold_spring()

	var spring_strength: float = hold_params.x
	var damping: float = hold_params.y

	var offset: Vector3 = (
		target_position
		- held_object.global_position
	)

	var force: Vector3 = (
		offset * spring_strength
	)

	force -= (
		held_object.linear_velocity
		* damping
	)

	held_object.apply_central_force(force)

	var rotation_smoothing := 15.0

	if zero_gravity:
		rotation_smoothing = 30.0

	held_object.angular_velocity = (
		held_object.angular_velocity.lerp(
			target_angular_velocity,
			rotation_smoothing
			* get_physics_process_delta_time()
		)
	)


# ============================================================
# SHARED HOLDING
# ============================================================

func _get_hold_spring() -> Vector2:
	# x = spring strength, y = damping. Both are scaled by how
	# well THIS player can control the object they're holding.

	var object_mass: float = max(
		held_object.mass,
		0.1
	)

	var strength_factor: float = clamp(
		player_strength / 100.0,
		0.1,
		2.0
	)

	var weight_factor: float = clamp(
		10.0 / object_mass,
		0.25,
		1.0
	)

	var control_factor: float = (
		strength_factor
		* weight_factor
	)

	var spring_strength: float = 120.0
	var damping: float = 18.0

	if zero_gravity:
		spring_strength = 400.0
		damping = 40.0

	return Vector2(
		spring_strength * control_factor,
		damping * control_factor
	)


func _simulates_held_object_locally() -> bool:
	if not held_object.is_multiplayer_authority():
		return false

	# On the host, authority 1 is ambiguous: it is also what a
	# shared object has. The holder registry tells them apart.
	if multiplayer.is_server():
		var holders: Array = _object_holders.get(
			str(held_object.get_path()),
			[]
		)

		return holders.size() <= 1

	return true


func _send_hold_target(target_position: Vector3) -> void:
	var hold_params := _get_hold_spring()
	var path := held_object.get_path()

	if multiplayer.is_server():
		_store_hold_target(
			str(path),
			1,
			target_position,
			target_angular_velocity,
			hold_params.x,
			hold_params.y
		)

	else:
		hold_object.rpc_id(
			1,
			path,
			target_position,
			target_angular_velocity,
			hold_params.x,
			hold_params.y
		)


# SERVER ONLY.
static func _store_hold_target(
	key: String,
	peer_id: int,
	target_position: Vector3,
	target_rotation_velocity: Vector3,
	spring_strength: float,
	damping: float
) -> void:

	var holders: Array = _object_holders.get(key, [])

	# Ignore targets from peers that aren't actually holding it.
	if not holders.has(peer_id):
		return

	var targets: Dictionary = _hold_targets.get(key, {})

	targets[peer_id] = {
		"position": target_position,
		"angular": target_rotation_velocity,
		"spring": spring_strength,
		"damping": damping,
		"time": Time.get_ticks_msec()
	}

	_hold_targets[key] = targets


# SERVER ONLY. Called every physics frame by the host's player.
func _server_update_shared_objects() -> void:
	var now := Time.get_ticks_msec()

	for key in _object_holders.keys():
		var holders: Array = _object_holders[key]

		# One holder simulates the object on their own client.
		if holders.size() < 2:
			continue

		var rigidbody := _get_rigidbody(NodePath(key))

		if rigidbody == null:
			_object_holders.erase(key)
			_hold_targets.erase(key)
			continue

		# Authority handoff to the host is still in flight.
		if not rigidbody.is_multiplayer_authority():
			continue

		var targets: Dictionary = _hold_targets.get(key, {})

		var force := Vector3.ZERO
		var angular_sum := Vector3.ZERO
		var active := 0

		for holder_id in holders:
			var t = targets.get(holder_id)

			if t == null:
				continue

			# Stale target (lagging or paused holder): no pull.
			if now - t["time"] > HOLD_TARGET_TIMEOUT_MS:
				continue

			force += (
				(t["position"] - rigidbody.global_position)
				* t["spring"]
			)

			force -= (
				rigidbody.linear_velocity
				* t["damping"]
			)

			angular_sum += t["angular"]
			active += 1

		if active == 0:
			continue

		rigidbody.sleeping = false

		rigidbody.apply_central_force(force)

		rigidbody.angular_velocity = (
			rigidbody.angular_velocity.lerp(
				angular_sum / active,
				15.0 * get_physics_process_delta_time()
			)
		)


# ============================================================
# ZERO-G MOVEMENT
# ============================================================

func handle_zero_g_movement(
	delta: float
) -> void:

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

	if (
		thrust_direction.length() > 0.0
		and thruster_fuel > 0.0
	):
		thrust_direction = (
			thrust_direction.normalized()
		)

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

	if velocity.length() > zero_g_max_speed:
		velocity = (
			velocity.normalized()
			* zero_g_max_speed
		)

	handle_zero_g_roll(delta)

	move_and_slide()

	update_resource_bars()


func handle_zero_g_roll(
	delta: float
) -> void:

	var roll_input := 0.0

	if Input.is_action_pressed("roll_left"):
		roll_input -= 1.0

	if Input.is_action_pressed("roll_right"):
		roll_input += 1.0

	if roll_input == 0.0:
		return

	var camera_position_before := (
		camera_3d.global_position
	)

	var b: Basis = global_transform.basis

	var roll_axis := -b.z.normalized()

	b = b.rotated(
		roll_axis,
		roll_input
		* zero_g_rotation_speed
		* delta
	)

	global_transform.basis = (
		b.orthonormalized()
	)

	var camera_position_after := (
		camera_3d.global_position
	)

	global_position += (
		camera_position_before
		- camera_position_after
	)


# ============================================================
# NORMAL MOVEMENT
# ============================================================

func handle_normal_movement(
	delta: float
) -> void:

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
		normal_forward = (
			normal_forward.normalized()
		)

	if normal_right.length() > 0.001:
		normal_right = (
			normal_right.normalized()
		)

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


# ============================================================
# CROUCH
# ============================================================

func update_crouch(
	delta: float
) -> void:

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

	mouse_sensitivity = Settings.get_mouse_sensitivity() * 0.00001

	if controlling_ship:
		return

	update_debug_info()
	update_object_info()
	update_grab_ui()
	update_resource_bars()

	if pause_menu_open:
		return

	handle_throw()
	handle_interaction()


# ============================================================
# INTERACTION
# ============================================================

func handle_interaction() -> void:

	if not Input.is_action_just_pressed("interact"):
		return

	if is_instance_valid(held_object):
		release_held_object()
		return

	held_object = null

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

	if object.is_in_group("Interactable"):
		print("OBJECT IS INTERACTABLE")

		if object.has_method("interact"):
			print("CALLING INTERACT()")
			object.interact()
		else:
			print("OBJECT HAS NO INTERACT()")

		return

	if object is RigidBody3D:
		var rigidbody := object as RigidBody3D

		# No "already held" check here any more: the host decides
		# whether we can join (up to MAX_HOLDERS_PER_OBJECT) and
		# tells us if we can't.
		held_object = rigidbody

		var hit_position: Vector3 = (
			ray.get_collision_point()
		)

		held_ui_local_position = (
			held_object.global_transform.affine_inverse()
			* hit_position
		)

		# Ask the host to transfer authority to us.
		request_object_authority.rpc_id(
			1,
			held_object.get_path()
		)


func release_held_object() -> void:
	# Drops whatever we are holding and hands authority
	# back to the host, keeping the object's momentum.

	if held_object == null:
		return

	var object := held_object

	held_object = null
	grab_ui.hide()

	if not is_instance_valid(object):
		return

	drop_object.rpc_id(
		1,
		object.get_path(),
		object.linear_velocity,
		object.angular_velocity
	)


# ============================================================
# THROWING
# ============================================================

func handle_throw() -> void:

	if not Input.is_action_just_pressed("left_click"):
		return

	if not is_instance_valid(held_object):
		return

	var object: RigidBody3D = held_object

	held_object = null
	grab_ui.hide()

	var camera_basis: Basis = (
		camera_pivot.global_transform.basis
	)

	var throw_strength: float = (
		throw_force
		* (
			10.0
			/ max(object.mass, 0.1)
		)
	)

	throw_object.rpc_id(
		1,
		object.get_path(),
		-camera_basis.z,
		throw_strength,
		object.linear_velocity,
		object.angular_velocity
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
		+ "Speed: %.2f m/s\n"
		% velocity.length()
		+ "Health: %.1f / %.1f\n"
		% [
			health,
			max_health
		]
		+ "Oxygen: %.1f / %.1f"
		% [
			oxygen,
			max_oxygen
		]
	)


# ============================================================
# OBJECT AUTHORITY HELPERS
# ============================================================

func _get_sender_id() -> int:
	# remote_sender_id is 0 when an RPC runs locally
	# (call_local), which for the server means peer 1.
	var id := multiplayer.get_remote_sender_id()

	if id == 0:
		return 1

	return id


func _get_rigidbody(
	object_path: NodePath
) -> RigidBody3D:

	var scene := get_tree().current_scene

	if scene == null:
		return null

	return scene.get_node_or_null(object_path) as RigidBody3D


static func _apply_release_velocity(
	rigidbody: RigidBody3D,
	lin_vel: Vector3,
	ang_vel: Vector3,
	impulse: Vector3
) -> void:

	# Wait one physics frame so the body has definitely
	# left its frozen state before we give it velocity.
	await rigidbody.get_tree().physics_frame

	if not is_instance_valid(rigidbody):
		return

	rigidbody.sleeping = false
	rigidbody.linear_velocity = lin_vel
	rigidbody.angular_velocity = ang_vel

	if impulse != Vector3.ZERO:
		rigidbody.apply_central_impulse(impulse)


# SERVER ONLY.
# Removes one holder from an object and moves authority to
# whoever should simulate it now:
#   no holders left  -> host
#   one holder left  -> that holder (smooth for them again)
#   several left     -> unchanged (host keeps simulating)
#
# rpc_node lets _exit_tree route the RPC through a player node
# that will still exist on every peer.
func _remove_holder(
	object_path: NodePath,
	peer_id: int,
	lin_vel: Vector3,
	ang_vel: Vector3,
	impulse: Vector3,
	rpc_node = null
) -> void:

	var key := str(object_path)

	var holders: Array = _object_holders.get(key, [])

	# Only an actual holder may drop / throw it.
	if not holders.has(peer_id):
		return

	var was_shared := holders.size() >= 2

	holders.erase(peer_id)

	var targets: Dictionary = _hold_targets.get(key, {})
	targets.erase(peer_id)

	if holders.is_empty():
		_object_holders.erase(key)
		_hold_targets.erase(key)
	else:
		_object_holders[key] = holders
		_hold_targets[key] = targets

	var rigidbody := _get_rigidbody(object_path)

	if rigidbody == null:
		return

	var node = rpc_node if rpc_node != null else self

	if holders.is_empty():
		if was_shared:
			# The host was already simulating it. Keep ITS
			# velocity (the leaver's copy is a frozen follower
			# with zero velocity) and only add the throw.
			node.set_object_authority.rpc(
				object_path,
				1,
				true,
				rigidbody.linear_velocity,
				rigidbody.angular_velocity,
				impulse
			)

		else:
			# Sole holder released it: carry the velocity
			# their client was simulating.
			node.set_object_authority.rpc(
				object_path,
				1,
				true,
				lin_vel,
				ang_vel,
				impulse
			)

	elif holders.size() == 1:
		# Back to a sole holder. Hand them the object with the
		# velocity the host had, so it doesn't stall. (A throw
		# is treated as a drop while others still hold it.)
		node.set_object_authority.rpc(
			object_path,
			holders[0],
			true,
			rigidbody.linear_velocity,
			rigidbody.angular_velocity,
			Vector3.ZERO
		)


# ============================================================
# OBJECT AUTHORITY RPCS
# ============================================================

@rpc("any_peer", "reliable", "call_local")
func request_object_authority(
	object_path: NodePath
) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := _get_sender_id()

	var rigidbody := _get_rigidbody(object_path)

	if rigidbody == null:
		object_request_denied.rpc_id(
			sender_id,
			object_path
		)
		return

	var key := str(object_path)

	var holders: Array = _object_holders.get(key, [])

	# Already holding it: nothing to do (and don't clear their hold).
	if holders.has(sender_id):
		return

	# Too many people already holding it.
	if holders.size() >= MAX_HOLDERS_PER_OBJECT:
		object_request_denied.rpc_id(
			sender_id,
			object_path
		)
		return

	holders.append(sender_id)
	_object_holders[key] = holders

	if holders.size() == 1:
		# First holder: they simulate the object themselves.
		set_object_authority.rpc(
			object_path,
			sender_id,
			true,
			rigidbody.linear_velocity,
			rigidbody.angular_velocity,
			Vector3.ZERO
		)

	elif rigidbody.get_multiplayer_authority() != 1:
		# A second holder joined a client-owned object: the host
		# takes over and combines everyone's pull.
		set_object_authority.rpc(
			object_path,
			1,
			false,
			Vector3.ZERO,
			Vector3.ZERO,
			Vector3.ZERO
		)


@rpc("any_peer", "reliable", "call_local")
func object_request_denied(
	object_path: NodePath
) -> void:

	# Only ever accepted from the host.
	var sender := multiplayer.get_remote_sender_id()

	if sender != 0 and sender != 1:
		return

	if not is_multiplayer_authority():
		return

	if (
		is_instance_valid(held_object)
		and held_object.get_path() == object_path
	):
		held_object = null
		grab_ui.hide()


@rpc("any_peer", "reliable", "call_local")
func set_object_authority(
	object_path: NodePath,
	peer_id: int,
	apply_velocity: bool,
	lin_vel: Vector3,
	ang_vel: Vector3,
	impulse: Vector3
) -> void:

	# Only the host is allowed to move authority around.
	var sender := multiplayer.get_remote_sender_id()

	if sender != 0 and sender != 1:
		return

	var rigidbody := _get_rigidbody(object_path)

	if rigidbody == null:
		return

	rigidbody.set_multiplayer_authority(peer_id)

	var local_id := multiplayer.get_unique_id()
	var is_local_authority := (peer_id == local_id)

	rigidbody.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rigidbody.freeze = not is_local_authority

	if is_local_authority:
		rigidbody.sleeping = false

		# Only the new simulator applies velocity, so the object
		# keeps its momentum across the handoff.
		if apply_velocity:
			_apply_release_velocity(
				rigidbody,
				lin_vel,
				ang_vel,
				impulse
			)

	# --------------------------------------------------------
	# SYNCHRONIZER VISIBILITY
	#
	# Sellable synchronizers are private (public_visibility is
	# false) and the HOST enables them per peer once that peer
	# has spawned the object.
	#
	# Visibility lives on the sender. When a CLIENT becomes the
	# authority, its synchronizer has nobody marked visible, so
	# it would sync to no one and the object would look frozen
	# for everybody else. The new authority therefore has to
	# mark the other peers visible itself.
	# --------------------------------------------------------

	var sync := (
		rigidbody.get_node_or_null("MultiplayerSynchronizer")
		as MultiplayerSynchronizer
	)

	if sync != null:
		if is_local_authority and peer_id != 1:
			for other_peer in multiplayer.get_peers():
				sync.set_visibility_for(other_peer, true)

		sync.update_visibility()

	print(
		"OBJECT AUTHORITY | ",
		rigidbody.name,
		" | authority = ",
		peer_id,
		" | local peer = ",
		local_id
	)


# ============================================================
# SERVER-SIDE OBJECT RPCS
# ============================================================

@rpc("any_peer", "unreliable")
func hold_object(
	object_path: NodePath,
	target_position: Vector3,
	target_rotation_velocity: Vector3,
	spring_strength: float,
	damping: float
) -> void:

	# Sent by clients that are holding a SHARED object. It only
	# records where the holder wants the object; the host applies
	# the forces itself in _server_update_shared_objects().
	if not multiplayer.is_server():
		return

	_store_hold_target(
		str(object_path),
		_get_sender_id(),
		target_position,
		target_rotation_velocity,
		spring_strength,
		damping
	)


@rpc("any_peer", "reliable", "call_local")
func drop_object(
	object_path: NodePath,
	lin_vel: Vector3,
	ang_vel: Vector3
) -> void:

	if not multiplayer.is_server():
		return

	_remove_holder(
		object_path,
		_get_sender_id(),
		lin_vel,
		ang_vel,
		Vector3.ZERO
	)


@rpc("any_peer", "reliable", "call_local")
func throw_object(
	object_path: NodePath,
	throw_direction: Vector3,
	force: float,
	lin_vel: Vector3,
	ang_vel: Vector3
) -> void:

	if not multiplayer.is_server():
		return

	_remove_holder(
		object_path,
		_get_sender_id(),
		lin_vel,
		ang_vel,
		throw_direction * force
	)


# ============================================================
# ZERO-G STATE
# ============================================================

func set_zero_gravity(
	enabled: bool
) -> void:

	if zero_gravity == enabled:
		return

	if enabled:

		var camera_basis: Basis = (
			camera_3d.global_transform.basis
			.orthonormalized()
		)

		global_transform.basis = camera_basis

		camera_pivot.rotation = Vector3.ZERO

		yaw = rotation.y
		pitch = 0.0

		zero_gravity = true

		return

	var forward: Vector3 = (
		-camera_3d.global_transform.basis.z
	)

	var horizontal_forward := Vector3(
		forward.x,
		0.0,
		forward.z
	)

	if horizontal_forward.length() > 0.001:

		horizontal_forward = (
			horizontal_forward.normalized()
		)

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

	var interactable := false
	var grabbable := false
	var current_node: Node = object

	while current_node != null:

		if current_node.is_in_group("Interactable"):
			interactable = true
			break

		if current_node.is_in_group("Grabbable"):
			grabbable = true
			break

		current_node = current_node.get_parent()

	if interactable:
		interact_prompt.text = "[F] - Interact"

	elif grabbable and not is_instance_valid(held_object):
		interact_prompt.text = "[F] - Grab"

	else:
		interact_prompt.text = ""

	if object is RigidBody3D:

		var physical_object := (
			object as RigidBody3D
		)

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
					"$"
					+ str(
						physical_object.sell_value
					)
				)

				object_name_label.modulate = rarity_color
				object_value_label.modulate = rarity_color

				return

	object_name_label.text = ""
	object_value_label.text = ""


func get_rarity_color(
	rarity: String
) -> Color:

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

	if not is_instance_valid(held_object):
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
		camera_3d.unproject_position(
			world_position
		)
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

	controlled_ship = (
		ship if enabled else null
	)
