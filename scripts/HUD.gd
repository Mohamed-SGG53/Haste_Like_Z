# HUD.gd - Heads-up display for HasteLike.
# ----------------------------------------------------------------------------
# Shows: current speed (m/s), distance traveled, landing rating pop-up,
# hint controls, and a game-over overlay with a restart button.
# ----------------------------------------------------------------------------
extends CanvasLayer

@onready var speed_label: Label = $SpeedLabel
@onready var distance_label: Label = $DistanceLabel
@onready var landing_label: Label = $LandingLabel
@onready var hints_label: Label = $HintsLabel
@onready var game_over_panel: Control = $GameOverPanel
@onready var restart_button: Button = $GameOverPanel/RestartButton

var landing_flash_timer: float = 0.0
var player: Node = null


func _ready() -> void:
	landing_label.modulate.a = 0.0
	restart_button.pressed.connect(_on_restart_pressed)


func set_player(p: Node) -> void:
	player = p
	if player:
		if player.has_signal("speed_changed"):
			player.speed_changed.connect(_on_speed_changed)
		if player.has_signal("distance_changed"):
			player.distance_changed.connect(_on_distance_changed)
		if player.has_signal("landed"):
			player.landed.connect(_on_landed)
		if player.has_signal("died"):
			player.died.connect(_on_died)


func _process(delta: float) -> void:
	if landing_flash_timer > 0:
		landing_flash_timer -= delta
		if landing_flash_timer <= 0:
			landing_label.modulate.a = 0.0
	# Restart shortcut
	if Input.is_action_just_pressed("restart"):
		_restart_game()


func _on_speed_changed(new_speed: float) -> void:
	speed_label.text = "%3.0f m/s" % new_speed
	# Color tint by speed tier
	if new_speed < 14.0:
		speed_label.label_settings.font_color = Color(0.8, 0.8, 0.8)
	elif new_speed < 30.0:
		speed_label.label_settings.font_color = Color(0.5, 1.0, 0.5)
	elif new_speed < 50.0:
		speed_label.label_settings.font_color = Color(1.0, 1.0, 0.3)
	else:
		speed_label.label_settings.font_color = Color(1.0, 0.4, 0.4)


func _on_distance_changed(meters: float) -> void:
	distance_label.text = "%4.0f m" % meters


func _on_landed(rating: String, impact_speed: float, slope_deg: float) -> void:
	if rating == "":
		return
	landing_label.text = rating + "\n(slope %.1f°)" % slope_deg
	landing_label.modulate.a = 1.0
	landing_flash_timer = 1.2
	# Color by rating
	match rating:
		"Perfect!":
			landing_label.label_settings.font_color = Color(0.3, 1.0, 0.6)
		"Good!":
			landing_label.label_settings.font_color = Color(0.6, 1.0, 0.3)
		"OK":
			landing_label.label_settings.font_color = Color(1.0, 1.0, 0.4)
		"Poor":
			landing_label.label_settings.font_color = Color(1.0, 0.5, 0.3)
		"Crash!":
			landing_label.label_settings.font_color = Color(1.0, 0.2, 0.2)


func _on_died() -> void:
	game_over_panel.visible = true


func _on_restart_pressed() -> void:
	_restart_game()


func _restart_game() -> void:
	# Reload the current scene
	game_over_panel.visible = false
	get_tree().reload_current_scene()
