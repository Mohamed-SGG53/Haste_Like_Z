# CameraRig.gd - Third-person follow camera WITH mouse-look controls.
# ----------------------------------------------------------------------------
# Behavior:
#   - The rig follows the player's position (lerped).
#   - The camera orbits the player based on:
#       * Yaw   (mouse X) — full 360° orbit around the player
#       * Pitch (mouse Y) — clamped so you can't look from below the ground
#       * Zoom  (scroll)  — distance from player, clamped
#   - Mouse is captured when the user clicks the game window. ESC releases.
#   - The camera always looks at the player's head height.
#   - Player's forward direction is INDEPENDENT of camera (player auto-runs -Z).
# ----------------------------------------------------------------------------
extends Node3D
class_name CameraRig

@export_group("Follow")
@export var follow_lerp: float = 6.0           # higher = stiffer follow
@export var look_ahead_factor: float = 0.18    # nudge by player velocity

@export_group("Mouse Look")
@export var mouse_sensitivity: float = 0.0028
@export var min_pitch: float = -1.30           # ~-75°, can look almost straight down
@export var max_pitch: float = 0.40            # ~+23°, can't look from above (no bird's-eye)
@export var default_pitch: float = -0.25       # ~-14°, slightly above horizontal

@export_group("Zoom")
@export var zoom_default: float = 7.5
@export var zoom_min: float = 3.5
@export var zoom_max: float = 14.0
@export var zoom_step: float = 1.2

@export_group("References")
@export var target_node_path: NodePath = ".."  # Player by default

@onready var camera: Camera3D = $Camera3D
@onready var target: Node3D = get_node(target_node_path)

# Internal state
var yaw: float = 0.0
var pitch: float = -0.25
var zoom: float = 7.5
var mouse_captured: bool = false


func _ready() -> void:
	pitch = default_pitch
	zoom = zoom_default
	Input.mouse_set_mode(Input.MOUSE_MODE_VISIBLE)
	set_process_input(true)
	# Initial camera placement so the first frame doesn't snap.
	_recompute_camera_transform(1.0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if mb.pressed and not mouse_captured:
					_capture_mouse()
			MOUSE_BUTTON_WHEEL_UP:
				zoom = clamp(zoom - zoom_step, zoom_min, zoom_max)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clamp(zoom + zoom_step, zoom_min, zoom_max)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and mouse_captured:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * mouse_sensitivity
		pitch = clamp(pitch - mm.relative.y * mouse_sensitivity, min_pitch, max_pitch)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_release_mouse()


func _capture_mouse() -> void:
	Input.mouse_set_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func _release_mouse() -> void:
	Input.mouse_set_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	# Smooth position: blend toward player position.
	var desired_pos: Vector3 = target.global_position
	global_position = global_position.lerp(desired_pos, 1.0 - exp(-follow_lerp * delta))

	# Optional look-ahead based on player velocity.
	if target is CharacterBody3D:
		var vel: Vector3 = target.velocity
		vel.y = 0
		global_position += vel * look_ahead_factor * delta

	_recompute_camera_transform(delta)


# Position the camera at orbit-distance from the rig based on yaw/pitch/zoom.
func _recompute_camera_transform(_delta: float) -> void:
	# Spherical-to-cartesian orbit:
	# x = sin(yaw) * cos(pitch) * zoom
	# z = cos(yaw) * cos(pitch) * zoom
	# y = -sin(pitch) * zoom   (pitch < 0 -> camera is above the player)
	var cos_p: float = cos(pitch)
	var cam_offset := Vector3(
		sin(yaw) * cos_p * zoom,
		-sin(pitch) * zoom,           # negative pitch = above player
		cos(yaw) * cos_p * zoom
	)
	camera.position = cam_offset
	# Look at a point at the player's head height (about 1.5m above origin).
	if target:
		var look_at_point: Vector3 = target.global_position + Vector3(0, 1.5, 0)
		camera.look_at(look_at_point, Vector3.UP)


# Public: snap the camera back behind the player (e.g. on respawn).
func reset_view() -> void:
	yaw = 0.0
	pitch = default_pitch
	zoom = zoom_default
