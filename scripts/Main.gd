# Main.gd - Top-level scene script that wires everything together.
# ----------------------------------------------------------------------------
# - Tells WorldManager who the player is so chunks stream around them
# - Tells CrumblingVoid who the player is so it can chase them
# - Tells HUD who the player is so it can wire up the signals
# - Handles ESC (release mouse if captured, otherwise pause)
# ----------------------------------------------------------------------------
extends Node3D

@onready var player: CharacterBody3D = $Player
@onready var void_node: Node3D = $CrumblingVoid
@onready var hud: CanvasLayer = $HUD
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var camera_rig: Node3D = $Player/CameraRig


func _ready() -> void:
	# Connect everyone up.
	# WorldManager is an autoload singleton (registered in project.godot).
	var wm := get_node("/root/WorldManager")
	if wm and wm.has_method("set_player"):
		wm.set_player(player)

	# CrumblingVoid is a child of Main
	if void_node and void_node.has_method("set_player"):
		void_node.set_player(player)

	# HUD is a child of Main
	if hud and hud.has_method("set_player"):
		hud.set_player(player)

	# Pre-spawn the first few chunks so the player has ground immediately
	if wm:
		# Spawn chunks in a 3x5 grid centered on (0, 0) so there's ground
		# in front of (negative z) and behind (positive z) the player.
		for dz in range(-2, 3):
			for dx in range(-1, 2):
				wm._spawn_chunk(dx, dz)

	# Place the player at a safe spawn height above the terrain
	if wm:
		var ground_h: float = wm.get_ground_height(player.global_position.x, player.global_position.z)
		player.global_position.y = ground_h + 2.0

	# Reset the camera view to the default third-person angle
	if camera_rig and camera_rig.has_method("reset_view"):
		camera_rig.reset_view()

	# Set time scale to normal
	Engine.time_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
	# ESC behavior:
	# - If mouse is captured (in mouse-look mode), ESC releases the mouse
	# - If mouse is free, ESC toggles pause
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var mouse_mode: int = Input.mouse_get_mode()
		if mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_set_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Engine.time_scale = 0.0 if Engine.time_scale > 0.0 else 1.0
		get_viewport().set_input_as_handled()
	# 'P' also toggles pause
	elif event is InputEventKey and event.pressed and event.keycode == KEY_P:
		Engine.time_scale = 0.0 if Engine.time_scale > 0.0 else 1.0
		get_viewport().set_input_as_handled()
